package configbundle

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"
)

func fixture(t *testing.T) (Payload, Envelope, ed25519.PublicKey, time.Time) {
	t.Helper()
	credentialData, err := os.ReadFile("../../../../test-vectors/credential-box.json")
	if err != nil {
		t.Fatal(err)
	}
	var credentialVector struct {
		Sealed string `json:"sealed"`
	}
	if err := json.Unmarshal(credentialData, &credentialVector); err != nil {
		t.Fatal(err)
	}
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	payload := NewPayload("account-a", "device-a", 2, 1, now.Add(-time.Minute), now.Add(time.Hour), []Node{{
		ID: "node-a", Provider: "vdsina", Endpoint: "example.invalid",
		Transports: []string{"vless-reality", "hysteria2"}, EncryptedCredentials: credentialVector.Sealed,
	}})
	envelope, err := Sign(payload, "key-1", privateKey)
	if err != nil {
		t.Fatal(err)
	}
	return payload, envelope, publicKey, now
}

func TestVerifyValidBundle(t *testing.T) {
	want, envelope, key, now := fixture(t)
	got, err := Verify(envelope, map[string]ed25519.PublicKey{"key-1": key}, "account-a", "device-a", 2, now)
	if err != nil || got.Version != want.Version {
		t.Fatalf("Verify() = %#v, %v", got, err)
	}
}

func TestSignRejectsPlaintextCredentials(t *testing.T) {
	payload, _, _, _ := fixture(t)
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	payload.Nodes[0].EncryptedCredentials = "plaintext-password"
	if _, err := Sign(payload, "key-1", private); err == nil {
		t.Fatal("signed plaintext credentials")
	}
}

func TestSharedClientVector(t *testing.T) {
	data, err := os.ReadFile("../../../../test-vectors/config-bundle.json")
	if err != nil {
		t.Fatal(err)
	}
	var fixture struct {
		PublicKeyB64 string   `json:"public_key_b64"`
		Envelope     Envelope `json:"envelope"`
	}
	if err := json.Unmarshal(data, &fixture); err != nil {
		t.Fatal(err)
	}
	publicKey, err := base64.RawURLEncoding.DecodeString(fixture.PublicKeyB64)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	if _, err := Verify(fixture.Envelope, map[string]ed25519.PublicKey{"test-key-1": publicKey}, "account-a", "device-a", 2, now); err != nil {
		t.Fatal(err)
	}
}

func TestVerifyRejectsTamperingWrongDeviceExpiryAndRollback(t *testing.T) {
	_, envelope, key, now := fixture(t)
	keys := map[string]ed25519.PublicKey{"key-1": key}
	modified := envelope
	raw, err := base64.RawURLEncoding.DecodeString(envelope.PayloadB64)
	if err != nil {
		t.Fatal(err)
	}
	raw[10] ^= 1
	modified.PayloadB64 = base64.RawURLEncoding.EncodeToString(raw)
	if _, err := Verify(modified, keys, "account-a", "device-a", 2, now); err == nil {
		t.Fatal("tampered payload accepted")
	}
	for _, test := range []struct {
		name    string
		device  string
		minimum uint64
		at      time.Time
	}{
		{"wrong device", "device-b", 2, now},
		{"rollback", "device-a", 3, now},
		{"expired", "device-a", 2, now.Add(2 * time.Hour)},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := Verify(envelope, keys, "account-a", test.device, test.minimum, test.at); err == nil {
				t.Fatal("invalid bundle accepted")
			}
		})
	}
}

func TestVerifyRejectsSignedButAmbiguousPayload(t *testing.T) {
	_, envelope, _, now := fixture(t)
	_, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := base64.RawURLEncoding.DecodeString(envelope.PayloadB64)
	if err != nil {
		t.Fatal(err)
	}
	raw = []byte(strings.Replace(string(raw), `"schema_version":1`, `"schema_version":1,"schema_version":1`, 1))
	envelope.PayloadB64 = base64.RawURLEncoding.EncodeToString(raw)
	envelope.Signature = ""
	// Sign the ambiguous bytes directly to prove canonical parsing is checked
	// after signature verification, rather than relying on a bad signature.
	publicKey := privateKey.Public().(ed25519.PublicKey)
	envelope.Signature = base64.RawURLEncoding.EncodeToString(ed25519.Sign(privateKey, signedBytes(raw)))
	if _, err := Verify(envelope, map[string]ed25519.PublicKey{"key-1": publicKey}, "account-a", "device-a", 2, now); err == nil {
		t.Fatal("duplicate field accepted")
	}
}
