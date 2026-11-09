package credentials

import (
	"crypto/ecdh"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestSealOpenAndContextBinding(t *testing.T) {
	device, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	context := Context{AccountID: "account-a", DeviceID: "device-a", NodeID: "node-a", Version: 2}
	want := []byte(`{"vless_reality":"example-only"}`)
	sealed, err := Seal(device.PublicKey().Bytes(), want, context)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Open(device.Bytes(), sealed, context)
	if err != nil || string(got) != string(want) {
		t.Fatalf("Open() = %q, %v", got, err)
	}
	wrong := context
	wrong.DeviceID = "device-b"
	if _, err := Open(device.Bytes(), sealed, wrong); err == nil {
		t.Fatal("accepted another device ID")
	}
	wrong = context
	wrong.Version++
	if _, err := Open(device.Bytes(), sealed, wrong); err == nil {
		t.Fatal("accepted another bundle version")
	}
	parts := strings.Split(sealed, ".")
	if parts[3][0] == 'A' {
		parts[3] = "B" + parts[3][1:]
	} else {
		parts[3] = "A" + parts[3][1:]
	}
	if _, err := Open(device.Bytes(), strings.Join(parts, "."), context); err == nil {
		t.Fatal("accepted changed ciphertext")
	}
}

func TestSharedClientVector(t *testing.T) {
	raw, err := os.ReadFile("../../../../test-vectors/credential-box.json")
	if err != nil {
		t.Fatal(err)
	}
	var vector struct {
		DeviceSeedB64 string  `json:"device_seed_b64"`
		Context       Context `json:"context"`
		Plaintext     string  `json:"plaintext"`
		Sealed        string  `json:"sealed"`
	}
	if err := json.Unmarshal(raw, &vector); err != nil {
		t.Fatal(err)
	}
	seed, err := base64.RawURLEncoding.DecodeString(vector.DeviceSeedB64)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Open(seed, vector.Sealed, vector.Context)
	if err != nil || string(got) != vector.Plaintext {
		t.Fatalf("shared vector failed: %v", err)
	}
}
