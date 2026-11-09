// Package configbundle signs and validates device-specific configuration
// updates. It does not provision nodes, encrypt credentials, or store keys.
package configbundle

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"
)

const (
	schemaVersion  = 1
	maxPayloadSize = 1 << 20
	domainPrefix   = "NONA-CONFIG-BUNDLE-v1\x00"
)

type Node struct {
	ID                   string   `json:"id"`
	Provider             string   `json:"provider"`
	Endpoint             string   `json:"endpoint"`
	Transports           []string `json:"transports"`
	EncryptedCredentials string   `json:"encrypted_credentials"`
}

type Payload struct {
	SchemaVersion int       `json:"schema_version"`
	AccountID     string    `json:"account_id"`
	DeviceID      string    `json:"device_id"`
	Version       uint64    `json:"version"`
	IssuedAt      time.Time `json:"issued_at"`
	ExpiresAt     time.Time `json:"expires_at"`
	RulesVersion  uint64    `json:"rules_version"`
	Nodes         []Node    `json:"nodes"`
}

type Envelope struct {
	KeyID      string `json:"key_id"`
	PayloadB64 string `json:"payload_b64"`
	Signature  string `json:"signature"`
}

func NewPayload(accountID, deviceID string, version, rulesVersion uint64, issuedAt, expiresAt time.Time, nodes []Node) Payload {
	return Payload{
		SchemaVersion: schemaVersion,
		AccountID:     accountID,
		DeviceID:      deviceID,
		Version:       version,
		IssuedAt:      issuedAt.UTC(),
		ExpiresAt:     expiresAt.UTC(),
		RulesVersion:  rulesVersion,
		Nodes:         nodes,
	}
}

func (p Payload) validate() error {
	if p.SchemaVersion != schemaVersion || p.AccountID == "" || p.DeviceID == "" || p.Version == 0 || p.RulesVersion == 0 {
		return errors.New("invalid bundle identity or version")
	}
	if p.IssuedAt.IsZero() || p.ExpiresAt.IsZero() || !p.ExpiresAt.After(p.IssuedAt) {
		return errors.New("invalid bundle validity interval")
	}
	if len(p.Nodes) == 0 {
		return errors.New("bundle has no nodes")
	}
	seen := make(map[string]bool, len(p.Nodes))
	for _, node := range p.Nodes {
		if node.ID == "" || seen[node.ID] || node.Provider == "" || node.Endpoint == "" || len(node.Transports) == 0 || node.EncryptedCredentials == "" {
			return errors.New("invalid or duplicate node")
		}
		seen[node.ID] = true
	}
	return nil
}

func signedBytes(payload []byte) []byte {
	message := make([]byte, 0, len(domainPrefix)+len(payload))
	message = append(message, domainPrefix...)
	return append(message, payload...)
}

// Sign accepts a server-held private key. The caller must never log the key
// or embed it in a client build.
func Sign(payload Payload, keyID string, privateKey ed25519.PrivateKey) (Envelope, error) {
	if err := payload.validate(); err != nil {
		return Envelope{}, err
	}
	if keyID == "" || len(privateKey) != ed25519.PrivateKeySize {
		return Envelope{}, errors.New("invalid signing key")
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return Envelope{}, err
	}
	if len(raw) > maxPayloadSize {
		return Envelope{}, errors.New("bundle exceeds size limit")
	}
	return Envelope{
		KeyID:      keyID,
		PayloadB64: base64.RawURLEncoding.EncodeToString(raw),
		Signature:  base64.RawURLEncoding.EncodeToString(ed25519.Sign(privateKey, signedBytes(raw))),
	}, nil
}

// Verify checks signature, identity, validity and rollback floor before a
// client may use the payload. Trusted keys and the version floor are supplied
// by the caller's secure state.
func Verify(envelope Envelope, trustedKeys map[string]ed25519.PublicKey, accountID, deviceID string, minimumVersion uint64, now time.Time) (Payload, error) {
	var payload Payload
	raw, err := base64.RawURLEncoding.DecodeString(envelope.PayloadB64)
	if err != nil || len(raw) == 0 || len(raw) > maxPayloadSize {
		return payload, errors.New("invalid payload size")
	}
	publicKey, ok := trustedKeys[envelope.KeyID]
	if !ok || len(publicKey) != ed25519.PublicKeySize {
		return payload, errors.New("unknown signing key")
	}
	signature, err := base64.RawURLEncoding.DecodeString(envelope.Signature)
	if err != nil || !ed25519.Verify(publicKey, signedBytes(raw), signature) {
		return payload, errors.New("invalid bundle signature")
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return Payload{}, fmt.Errorf("invalid bundle payload: %w", err)
	}
	canonical, err := json.Marshal(payload)
	if err != nil || !bytes.Equal(canonical, raw) {
		return Payload{}, errors.New("noncanonical bundle payload")
	}
	if err := payload.validate(); err != nil {
		return Payload{}, err
	}
	if payload.AccountID != accountID || payload.DeviceID != deviceID {
		return Payload{}, errors.New("bundle belongs to another account or device")
	}
	if payload.Version < minimumVersion {
		return Payload{}, errors.New("bundle version rollback")
	}
	if now.Before(payload.IssuedAt.Add(-5*time.Minute)) || !now.Before(payload.ExpiresAt) {
		return Payload{}, errors.New("bundle not currently valid")
	}
	return payload, nil
}
