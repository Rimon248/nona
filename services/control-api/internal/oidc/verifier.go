package oidc

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

var ErrInvalidToken = errors.New("invalid OIDC access token")

type Identity struct {
	Subject  string
	Username string
}

// Verifier accepts only Keycloak RS256 access tokens for this API and client.
// The JWKS URL is fixed by the operator, never taken from an untrusted token.
type Verifier struct {
	Issuer       string
	Audience     string
	ClientID     string
	RequiredRole string
	JWKSURL      string
	HTTP         *http.Client

	mu          sync.Mutex
	keys        map[string]*rsa.PublicKey
	keysExpires time.Time
}

type jwkSet struct {
	Keys []struct {
		KID string `json:"kid"`
		KTY string `json:"kty"`
		ALG string `json:"alg"`
		Use string `json:"use"`
		N   string `json:"n"`
		E   string `json:"e"`
	} `json:"keys"`
}

func (v *Verifier) key(ctx context.Context, kid string, now time.Time) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.keys != nil && now.Before(v.keysExpires) {
		if key := v.keys[kid]; key != nil {
			return key, nil
		}
	}
	if v.JWKSURL == "" || (v.HTTP == nil && !strings.HasPrefix(v.JWKSURL, "https://")) {
		return nil, ErrInvalidToken
	}
	client := v.HTTP
	if client == nil {
		client = &http.Client{Timeout: 3 * time.Second}
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, v.JWKSURL, nil)
	if err != nil {
		return nil, err
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("JWKS returned %d", response.StatusCode)
	}
	var set jwkSet
	if err := json.NewDecoder(io.LimitReader(response.Body, 65537)).Decode(&set); err != nil {
		return nil, err
	}
	if len(set.Keys) == 0 || len(set.Keys) > 32 {
		return nil, ErrInvalidToken
	}
	keys := make(map[string]*rsa.PublicKey, len(set.Keys))
	for _, item := range set.Keys {
		if item.KTY != "RSA" || (item.ALG != "" && item.ALG != "RS256") ||
			(item.Use != "" && item.Use != "sig") || item.KID == "" || item.N == "" || item.E == "" {
			continue
		}
		n, errN := base64.RawURLEncoding.DecodeString(item.N)
		e, errE := base64.RawURLEncoding.DecodeString(item.E)
		if errN != nil || errE != nil || len(n) < 256 || len(n) > 1024 || len(e) == 0 || len(e) > 4 {
			continue
		}
		exponent := new(big.Int).SetBytes(e)
		if !exponent.IsInt64() || exponent.Int64() < 3 || exponent.Int64() > 65537 || exponent.Int64()%2 == 0 {
			continue
		}
		keys[item.KID] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(exponent.Int64())}
	}
	if len(keys) == 0 {
		return nil, ErrInvalidToken
	}
	v.keys = keys
	v.keysExpires = now.Add(5 * time.Minute)
	if key := keys[kid]; key != nil {
		return key, nil
	}
	return nil, ErrInvalidToken
}

func audienceContains(value json.RawMessage, expected string) bool {
	var one string
	if json.Unmarshal(value, &one) == nil {
		return one == expected
	}
	var many []string
	if json.Unmarshal(value, &many) != nil {
		return false
	}
	for _, item := range many {
		if item == expected {
			return true
		}
	}
	return false
}

func (v *Verifier) Verify(ctx context.Context, token string, now time.Time) (Identity, error) {
	if len(token) < 20 || len(token) > 16384 || strings.Count(token, ".") != 2 {
		return Identity{}, ErrInvalidToken
	}
	parts := strings.Split(token, ".")
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil || len(headerBytes) > 1024 {
		return Identity{}, ErrInvalidToken
	}
	var header struct {
		ALG string `json:"alg"`
		KID string `json:"kid"`
	}
	if json.Unmarshal(headerBytes, &header) != nil || header.ALG != "RS256" || header.KID == "" {
		return Identity{}, ErrInvalidToken
	}
	key, err := v.key(ctx, header.KID, now)
	if err != nil {
		return Identity{}, ErrInvalidToken
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return Identity{}, ErrInvalidToken
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], signature) != nil {
		return Identity{}, ErrInvalidToken
	}
	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || len(payloadBytes) > 12288 {
		return Identity{}, ErrInvalidToken
	}
	var claims struct {
		Issuer      string          `json:"iss"`
		Audience    json.RawMessage `json:"aud"`
		ClientID    string          `json:"azp"`
		Subject     string          `json:"sub"`
		Username    string          `json:"preferred_username"`
		Expires     int64           `json:"exp"`
		NotBefore   int64           `json:"nbf"`
		IssuedAt    int64           `json:"iat"`
		RealmAccess struct {
			Roles []string `json:"roles"`
		} `json:"realm_access"`
	}
	if json.Unmarshal(payloadBytes, &claims) != nil || claims.Issuer != v.Issuer ||
		!audienceContains(claims.Audience, v.Audience) || claims.ClientID != v.ClientID ||
		claims.Subject == "" || len(claims.Subject) > 256 ||
		claims.Expires <= now.Unix() || claims.IssuedAt <= 0 || claims.IssuedAt > now.Add(time.Minute).Unix() ||
		claims.NotBefore > now.Unix() {
		return Identity{}, ErrInvalidToken
	}
	if v.RequiredRole != "" {
		found := false
		for _, role := range claims.RealmAccess.Roles {
			if role == v.RequiredRole {
				found = true
				break
			}
		}
		if !found {
			return Identity{}, ErrInvalidToken
		}
	}
	return Identity{Subject: claims.Subject, Username: claims.Username}, nil
}
