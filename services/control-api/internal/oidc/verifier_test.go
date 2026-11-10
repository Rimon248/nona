package oidc

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"math/big"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestVerifierRequiresSignatureIssuerAudienceAndClient(t *testing.T) {
	private, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	encoded := base64.RawURLEncoding
	jwks, _ := json.Marshal(map[string]any{"keys": []map[string]string{{
		"kid": "test-key", "kty": "RSA", "alg": "RS256", "use": "sig",
		"n": encoded.EncodeToString(private.N.Bytes()),
		"e": encoded.EncodeToString(big.NewInt(int64(private.E)).Bytes()),
	}}})
	client := &http.Client{Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(string(jwks)))}, nil
	})}
	verifier := &Verifier{
		Issuer: "https://nona.example/auth/realms/nona", Audience: "nona-api",
		ClientID: "nona-client", JWKSURL: "https://nona.example/jwks", HTTP: client,
	}
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	base := map[string]any{
		"iss": verifier.Issuer, "aud": []string{"account", "nona-api"},
		"azp": "nona-client", "sub": "account-subject", "preferred_username": "roman",
		"iat": now.Unix(), "exp": now.Add(5 * time.Minute).Unix(),
	}
	sign := func(claims map[string]any) string {
		t.Helper()
		header, _ := json.Marshal(map[string]string{"alg": "RS256", "kid": "test-key"})
		payload, _ := json.Marshal(claims)
		message := encoded.EncodeToString(header) + "." + encoded.EncodeToString(payload)
		digest := sha256.Sum256([]byte(message))
		signature, err := rsa.SignPKCS1v15(rand.Reader, private, crypto.SHA256, digest[:])
		if err != nil {
			t.Fatal(err)
		}
		return message + "." + encoded.EncodeToString(signature)
	}
	identity, err := verifier.Verify(context.Background(), sign(base), now)
	if err != nil || identity.Subject != "account-subject" || identity.Username != "roman" {
		t.Fatalf("valid Keycloak token rejected: %v %+v", err, identity)
	}
	verifier.RequiredRole = "nona-operator"
	if _, err := verifier.Verify(context.Background(), sign(base), now); err != ErrInvalidToken {
		t.Fatalf("token without operator role accepted: %v", err)
	}
	base["realm_access"] = map[string]any{"roles": []string{"nona-operator"}}
	if _, err := verifier.Verify(context.Background(), sign(base), now); err != nil {
		t.Fatalf("operator token rejected: %v", err)
	}
	for name, change := range map[string]func(map[string]any){
		"issuer":   func(c map[string]any) { c["iss"] = "https://other.example" },
		"audience": func(c map[string]any) { c["aud"] = "other-api" },
		"client":   func(c map[string]any) { c["azp"] = "other-client" },
		"expired":  func(c map[string]any) { c["exp"] = now.Unix() },
	} {
		t.Run(name, func(t *testing.T) {
			claims := make(map[string]any, len(base))
			for k, v := range base {
				claims[k] = v
			}
			change(claims)
			if _, err := verifier.Verify(context.Background(), sign(claims), now); err != ErrInvalidToken {
				t.Fatalf("unwanted token accepted: %v", err)
			}
		})
	}
	tampered := []byte(sign(base))
	position := len(tampered) - 16
	if tampered[position] == 'A' {
		tampered[position] = 'B'
	} else {
		tampered[position] = 'A'
	}
	if _, err := verifier.Verify(context.Background(), string(tampered), now); err != ErrInvalidToken {
		t.Fatalf("tampered signature accepted: %v", err)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
