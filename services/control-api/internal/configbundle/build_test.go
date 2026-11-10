package configbundle

import (
	"bytes"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"testing"
	"time"

	"nona.example/control-api/internal/credentials"
)

func TestBuildForDeviceEncryptsAndSigns(t *testing.T) {
	deviceKey, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	public, signer, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	access := []byte(`{"schema_version":1,"vless_reality":{"host":"node.example.invalid","port":8443,"user_id":"00000000-0000-4000-8000-000000000001","server_name":"front.example.invalid","reality_password":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","short_id":"a1b2c3d4","flow":"xtls-rprx-vision"},"hysteria2":{"host":"node.example.invalid","port":443,"auth":"fictional-password","server_name":"node.example.invalid","obfs_password":"fictional-obfs-password"}}`)
	node := PlainNode{ID: "node-a", Provider: "vdsina", Endpoint: "node.example.invalid", Transports: []string{"vless-reality", "hysteria2"}, Access: access}
	now := time.Date(2026, 11, 10, 7, 0, 0, 0, time.UTC)
	envelope, err := BuildForDevice("account-a", "device-a", deviceKey.PublicKey().Bytes(), 1, 1,
		now, now.Add(time.Hour), []PlainNode{node}, "key-1", signer)
	if err != nil {
		t.Fatal(err)
	}
	payload, err := Verify(envelope, map[string]ed25519.PublicKey{"key-1": public}, "account-a", "device-a", 1, now)
	if err != nil || len(payload.Nodes) != 1 {
		t.Fatalf("built bundle rejected: %v", err)
	}
	opened, err := credentials.Open(deviceKey.Bytes(), payload.Nodes[0].EncryptedCredentials,
		credentials.Context{AccountID: "account-a", DeviceID: "device-a", NodeID: "node-a", Version: 1})
	if err != nil || !bytes.Equal(opened, access) {
		t.Fatalf("device could not open its access document: %v", err)
	}
	otherKey, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := credentials.Open(otherKey.Bytes(), payload.Nodes[0].EncryptedCredentials,
		credentials.Context{AccountID: "account-a", DeviceID: "device-a", NodeID: "node-a", Version: 1}); err == nil {
		t.Fatal("another device opened credentials")
	}

	node.Endpoint = "other.example.invalid"
	if _, err := BuildForDevice("account-a", "device-a", deviceKey.PublicKey().Bytes(), 2, 1,
		now, now.Add(time.Hour), []PlainNode{node}, "key-1", signer); err == nil {
		t.Fatal("mismatched endpoint signed")
	}
	node.Endpoint = "node.example.invalid"
	node.Transports = []string{"vless-reality"}
	if _, err := BuildForDevice("account-a", "device-a", deviceKey.PublicKey().Bytes(), 2, 1,
		now, now.Add(time.Hour), []PlainNode{node}, "key-1", signer); err == nil {
		t.Fatal("mismatched transport list signed")
	}
}
