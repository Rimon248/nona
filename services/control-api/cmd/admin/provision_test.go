package main

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
)

func TestManagedClientIDIsStableAndScoped(t *testing.T) {
	one := managedClientID("account-a", "device-a")
	if len(one) != 37 || one[:5] != "nona_" || one != managedClientID("account-a", "device-a") {
		t.Fatal("invalid managed client identifier")
	}
	if one == managedClientID("account-a", "device-b") || one == managedClientID("account-b", "device-a") {
		t.Fatal("client identifier is not device and account scoped")
	}
}

func TestProvisionSettingsRejectInvalidMetadataBeforeNodeMutation(t *testing.T) {
	var settings provisionSettings
	settings.PanelURL = "https://panel.example.invalid/secret/"
	settings.Host = "192.0.2.1"
	settings.VLESS.InboundID = 2
	settings.VLESS.Port = 8443
	settings.VLESS.ServerName = "front.example.invalid"
	settings.VLESS.RealityPublicKey = base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	settings.VLESS.ClientEncryption = "mlkem768x25519plus.native.1rtt." + base64.RawURLEncoding.EncodeToString(make([]byte, 32))
	settings.VLESS.ShortID = "a1b2"
	settings.Hysteria.InboundID = 1
	settings.Hysteria.Port = 443
	settings.Hysteria.ServerName = "192.0.2.1"
	settings.Hysteria.ObfsPassword = "fictional-obfs"
	if !validSettings(settings) {
		t.Fatal("rejected valid settings")
	}
	settings.Hysteria.ObfsPassword = ""
	if validSettings(settings) {
		t.Fatal("accepted missing obfuscation password")
	}
	settings.Hysteria.ObfsPassword = "fictional-obfs"
	settings.VLESS.ShortID = "not-hex"
	if validSettings(settings) {
		t.Fatal("accepted invalid short ID")
	}
}

func TestPrivateFilesRequireRestrictedPermissions(t *testing.T) {
	path := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(path, []byte("fictional-token"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readPrivateFile(path, 100); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := readPrivateFile(path, 100); err == nil {
		t.Fatal("accepted a world-readable secret")
	}
}
