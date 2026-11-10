package main

import (
	"context"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/netip"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"nona.example/control-api/internal/auth"
	"nona.example/control-api/internal/configbundle"
	"nona.example/control-api/internal/node3xui"
)

type provisionSettings struct {
	PanelURL string `json:"panel_url"`
	Host     string `json:"host"`
	VLESS    struct {
		InboundID        int    `json:"inbound_id"`
		Port             int    `json:"port"`
		ServerName       string `json:"server_name"`
		RealityPublicKey string `json:"reality_public_key"`
		ClientEncryption string `json:"client_encryption"`
		ShortID          string `json:"short_id"`
	} `json:"vless_reality"`
	Hysteria struct {
		InboundID    int    `json:"inbound_id"`
		Port         int    `json:"port"`
		ServerName   string `json:"server_name"`
		ObfsPassword string `json:"obfs_password"`
	} `json:"hysteria2"`
}

func managedClientID(accountID, deviceID string) string {
	sum := sha256.Sum256([]byte(accountID + "\x00" + deviceID))
	return "nona_" + hex.EncodeToString(sum[:16])
}

func readPrivateFile(path string, max int64) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() < 1 || info.Size() > max {
		return nil, errors.New("invalid private file")
	}
	return os.ReadFile(path)
}

func validHost(value string) bool {
	if _, err := netip.ParseAddr(value); err == nil {
		return true
	}
	if len(value) < 1 || len(value) > 253 || strings.ContainsAny(value, "/:@ \r\n\t") || strings.HasPrefix(value, ".") || strings.HasSuffix(value, ".") || strings.Contains(value, "..") {
		return false
	}
	for _, part := range strings.Split(value, ".") {
		if len(part) < 1 || len(part) > 63 || strings.HasPrefix(part, "-") || strings.HasSuffix(part, "-") {
			return false
		}
		for _, char := range part {
			if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || char == '-') {
				return false
			}
		}
	}
	return true
}

func validSettings(settings provisionSettings) bool {
	key, err := base64.RawURLEncoding.DecodeString(settings.VLESS.RealityPublicKey)
	short, shortErr := hex.DecodeString(settings.VLESS.ShortID)
	parts := strings.Split(settings.VLESS.ClientEncryption, ".")
	encryptionValid := len(parts) == 4 && parts[0] == "mlkem768x25519plus" &&
		(parts[1] == "native" || parts[1] == "xorpub" || parts[1] == "random") &&
		(parts[2] == "1rtt" || parts[2] == "0rtt")
	if encryptionValid {
		public, decodeErr := base64.RawURLEncoding.DecodeString(parts[3])
		encryptionValid = decodeErr == nil && len(public) == 32 && base64.RawURLEncoding.EncodeToString(public) == parts[3]
	}
	return encryptionValid && validHost(settings.Host) && validHost(settings.VLESS.ServerName) && validHost(settings.Hysteria.ServerName) &&
		settings.VLESS.Port > 0 && settings.VLESS.Port <= 65535 && settings.Hysteria.Port > 0 && settings.Hysteria.Port <= 65535 &&
		settings.VLESS.InboundID > 0 && settings.Hysteria.InboundID > 0 && settings.VLESS.InboundID != settings.Hysteria.InboundID &&
		err == nil && len(key) == 32 && base64.RawURLEncoding.EncodeToString(key) == settings.VLESS.RealityPublicKey &&
		shortErr == nil && len(short) <= 8 && settings.Hysteria.ObfsPassword != ""
}

func loadSigner() (ed25519.PrivateKey, string, error) {
	keyID := os.Getenv("NONA_CONFIG_KEY_ID")
	if keyID == "" {
		return nil, "", errors.New("configuration key ID is required")
	}
	signerRaw, err := readPrivateFile(os.Getenv("NONA_CONFIG_SIGNING_KEY_FILE"), 4096)
	if err != nil {
		return nil, "", errors.New("could not read signing key")
	}
	block, _ := pem.Decode(signerRaw)
	if block == nil {
		return nil, "", errors.New("invalid signing key")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, "", errors.New("invalid signing key")
	}
	signer, ok := parsed.(ed25519.PrivateKey)
	if !ok {
		return nil, "", errors.New("invalid signing key")
	}
	return signer, keyID, nil
}

func loadPanel() (provisionSettings, *node3xui.Client, error) {
	var settings provisionSettings
	settingsRaw, err := readPrivateFile(os.Getenv("NONA_NODE_SETTINGS_FILE"), 8192)
	if err != nil {
		return settings, nil, errors.New("could not read private node settings")
	}
	if err := json.Unmarshal(settingsRaw, &settings); err != nil || !validSettings(settings) {
		return settings, nil, errors.New("invalid private node settings")
	}
	tokenRaw, err := readPrivateFile(os.Getenv("NONA_3XUI_TOKEN_FILE"), 512)
	if err != nil {
		return settings, nil, errors.New("could not read panel token")
	}
	token := strings.TrimSpace(string(tokenRaw))
	caRaw, err := os.ReadFile(os.Getenv("NONA_3XUI_CA_FILE"))
	if err != nil {
		return settings, nil, errors.New("could not read panel certificate")
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(caRaw) {
		return settings, nil, errors.New("invalid panel certificate")
	}
	panel, err := node3xui.New(settings.PanelURL, token, &http.Client{
		Timeout:   10 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: roots}},
	})
	if err != nil {
		return settings, nil, errors.New("invalid panel connection")
	}
	return settings, panel, nil
}

func provisionDevice(pool *pgxpool.Pool, service *auth.Service, accountID, deviceID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	guard, err := pool.Begin(ctx)
	if err != nil {
		return errors.New("could not lock device provisioning")
	}
	defer guard.Rollback(ctx)
	if _, err := guard.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, deviceID); err != nil {
		return errors.New("could not lock device provisioning")
	}
	var devicePublic []byte
	var previousVersion int64
	err = guard.QueryRow(ctx, `SELECT d.public_key, COALESCE(c.version,0) FROM devices d
		LEFT JOIN device_configurations c ON c.device_id=d.id
		WHERE d.id=$1 AND d.account_id=$2 AND d.revoked_at IS NULL`, deviceID, accountID).Scan(&devicePublic, &previousVersion)
	if errors.Is(err, pgx.ErrNoRows) {
		return errors.New("active device not found")
	}
	if err != nil || previousVersion < 0 || previousVersion > 1000000 {
		return errors.New("could not load device")
	}
	settings, panel, err := loadPanel()
	if err != nil {
		return err
	}
	signer, keyID, err := loadSigner()
	if err != nil {
		return err
	}
	id := managedClientID(accountID, deviceID)
	// Commit the marker before contacting the panel. A failed request may still
	// have created a client, so a retry or operator retirement must resolve it.
	if _, err := pool.Exec(ctx, `INSERT INTO device_remote_credentials (device_id, node_id, client_id)
		VALUES ($1,'vdsina-1',$2) ON CONFLICT (device_id,node_id) DO NOTHING`, deviceID, id); err != nil {
		return errors.New("could not record remote credential intent")
	}
	var recordedID string
	if err := pool.QueryRow(ctx, `SELECT client_id FROM device_remote_credentials WHERE device_id=$1 AND node_id='vdsina-1'`, deviceID).Scan(&recordedID); err != nil || recordedID != id {
		return errors.New("remote credential record mismatch")
	}
	inboundIDs := []int{settings.Hysteria.InboundID, settings.VLESS.InboundID}
	if err := panel.Add(ctx, id, inboundIDs); err != nil {
		// A retry can encounter the client created by the preceding attempt.
		// Only a matching, enabled Nona client may be reused.
		if _, getErr := panel.Get(ctx, id); getErr != nil {
			return errors.New("could not create VPN client")
		}
	}
	record, err := panel.Get(ctx, id)
	if err != nil || !record.Enable || record.UUID == "" || record.Auth == "" ||
		!slices.Contains(record.InboundIDs, settings.Hysteria.InboundID) || !slices.Contains(record.InboundIDs, settings.VLESS.InboundID) {
		return errors.New("VPN client is incomplete")
	}
	access, err := json.Marshal(map[string]any{
		"schema_version": 2,
		"vless_reality": map[string]any{"host": settings.Host, "port": settings.VLESS.Port,
			"user_id": record.UUID, "server_name": settings.VLESS.ServerName,
			"reality_password": settings.VLESS.RealityPublicKey, "encryption": settings.VLESS.ClientEncryption,
			"short_id": settings.VLESS.ShortID, "flow": record.Flow},
		"hysteria2": map[string]any{"host": settings.Host, "port": settings.Hysteria.Port,
			"auth": record.Auth, "server_name": settings.Hysteria.ServerName,
			"obfs_password": settings.Hysteria.ObfsPassword},
	})
	if err != nil {
		return errors.New("could not build node access")
	}
	now := time.Now().UTC()
	envelope, err := configbundle.BuildForDevice(accountID, deviceID, devicePublic, uint64(previousVersion+1), 1,
		now, now.Add(30*24*time.Hour), []configbundle.PlainNode{{ID: "vdsina-1", Provider: "VDSina", Endpoint: settings.Host,
			Transports: []string{"vless-reality", "hysteria2"}, Access: access}}, keyID, signer)
	clear(access)
	if err != nil {
		return errors.New("could not seal configuration")
	}
	if err := service.InstallConfiguration(ctx, accountID, deviceID, envelope,
		map[string]ed25519.PublicKey{keyID: signer.Public().(ed25519.PublicKey)}, now); err != nil {
		return errors.New("could not install configuration")
	}
	if err := guard.Commit(ctx); err != nil {
		return errors.New("could not release provisioning lock")
	}
	fmt.Println("Configuration installed for device", deviceID)
	return nil
}

func retireDevice(service *auth.Service, accountID, deviceID string) error {
	_, panel, err := loadPanel()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	id := managedClientID(accountID, deviceID)
	if err := service.RevokeProvisionedDevice(ctx, accountID, deviceID, time.Now().UTC(), func(ctx context.Context) error {
		if err := panel.Delete(ctx, id); err != nil {
			return errors.New("could not delete remote VPN client")
		}
		return nil
	}); err != nil {
		return err
	}
	fmt.Println("VPN client removed and device revoked", deviceID)
	return nil
}
