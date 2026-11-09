package main

import (
	"context"
	"crypto/ecdh"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"nona.example/control-api/internal/auth"
	"nona.example/control-api/internal/configbundle"
	"nona.example/control-api/internal/credentials"
)

func TestSessionHTTPAgainstPostgres(t *testing.T) {
	url := os.Getenv("NONA_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("set NONA_TEST_DATABASE_URL to run PostgreSQL integration test")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	service, err := auth.NewService(pool)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.CheckSchema(ctx); err != nil {
		t.Fatal(err)
	}
	username := fmt.Sprintf("api_%d", time.Now().UnixNano())
	accountID, err := service.CreateAccount(ctx, username, "a long test password")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM accounts WHERE id=$1`, accountID)
	mux := handler(service)
	ready := httptest.NewRecorder()
	mux.ServeHTTP(ready, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if ready.Code != http.StatusOK {
		t.Fatalf("healthy database returned %d from readiness endpoint", ready.Code)
	}

	request := httptest.NewRequest(http.MethodPost, "/v1/sessions",
		strings.NewReader(fmt.Sprintf(`{"username":%q,"password":"a long test password"}`, username)))
	request.Header.Set("Content-Type", "application/json")
	record := httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusOK {
		t.Fatalf("login returned %d: %s", record.Code, record.Body.String())
	}
	if record.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("token response may be cached")
	}
	var first auth.Tokens
	if err := json.Unmarshal(record.Body.Bytes(), &first); err != nil {
		t.Fatal(err)
	}
	if first.AccountID != accountID || first.AccessToken == "" || first.RefreshToken == "" {
		t.Fatal("login returned empty token")
	}

	request = httptest.NewRequest(http.MethodPost, "/v1/sessions/refresh",
		strings.NewReader(fmt.Sprintf(`{"refresh_token":%q}`, first.RefreshToken)))
	request.Header.Set("Content-Type", "application/json")
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusOK {
		t.Fatalf("refresh returned %d: %s", record.Code, record.Body.String())
	}
	var second auth.Tokens
	if err := json.Unmarshal(record.Body.Bytes(), &second); err != nil {
		t.Fatal(err)
	}
	if second.AccountID != accountID || second.RefreshToken == first.RefreshToken || second.AccessToken == first.AccessToken {
		t.Fatal("tokens were not rotated")
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices", nil)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated device list returned %d", record.Code)
	}
	privateBytes := make([]byte, 32)
	privateBytes[0] = 8
	private, err := ecdh.X25519().NewPrivateKey(privateBytes)
	if err != nil {
		t.Fatal(err)
	}
	public := base64.RawURLEncoding.EncodeToString(private.PublicKey().Bytes())
	request = httptest.NewRequest(http.MethodPost, "/v1/devices", strings.NewReader(fmt.Sprintf(`{"label":"Test phone","public_key":%q}`, public)))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusCreated {
		t.Fatalf("register device returned %d: %s", record.Code, record.Body.String())
	}
	var device auth.Device
	if err := json.Unmarshal(record.Body.Bytes(), &device); err != nil {
		t.Fatal(err)
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices", nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusOK || !strings.Contains(record.Body.String(), device.ID) {
		t.Fatalf("device list returned %d: %s", record.Code, record.Body.String())
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices/"+device.ID+"/configuration", nil)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusUnauthorized {
		t.Fatalf("unauthenticated configuration returned %d", record.Code)
	}
	now := time.Now().UTC()
	sealed, err := credentials.Seal(private.PublicKey().Bytes(), []byte(`{"example":"test-only"}`), credentials.Context{
		AccountID: accountID, DeviceID: device.ID, NodeID: "node-a", Version: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	key, signingKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	payload := configbundle.NewPayload(accountID, device.ID, 1, 1, now.Add(-time.Minute), now.Add(time.Hour), []configbundle.Node{{
		ID: "node-a", Provider: "vdsina", Endpoint: "example.invalid", Transports: []string{"vless-reality"}, EncryptedCredentials: sealed,
	}})
	envelope, err := configbundle.Sign(payload, "test-key", signingKey)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.InstallConfiguration(ctx, accountID, device.ID, envelope, map[string]ed25519.PublicKey{"test-key": key}, now); err != nil {
		t.Fatal(err)
	}
	if err := service.InstallConfiguration(ctx, accountID, device.ID, envelope, map[string]ed25519.PublicKey{"test-key": key}, now); err != nil {
		t.Fatalf("identical install was not idempotent: %v", err)
	}
	payload.Nodes[0].Endpoint = "changed.example.invalid"
	conflicting, err := configbundle.Sign(payload, "test-key", signingKey)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.InstallConfiguration(ctx, accountID, device.ID, conflicting, map[string]ed25519.PublicKey{"test-key": key}, now); !errors.Is(err, auth.ErrConfigurationRollback) {
		t.Fatalf("same-version replacement returned %v", err)
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices/"+device.ID+"/configuration", nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusOK || record.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("configuration returned %d: %s", record.Code, record.Body.String())
	}
	var served configbundle.Envelope
	if err := json.Unmarshal(record.Body.Bytes(), &served); err != nil || served.Signature != envelope.Signature {
		t.Fatal("wrong configuration returned")
	}
	otherUsername := fmt.Sprintf("other_%d", time.Now().UnixNano())
	otherID, err := service.CreateAccount(ctx, otherUsername, "a long test password")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM accounts WHERE id=$1`, otherID)
	otherTokens, err := service.Login(ctx, otherUsername, "a long test password", now)
	if err != nil {
		t.Fatal(err)
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices/"+device.ID+"/configuration", nil)
	request.Header.Set("Authorization", "Bearer "+otherTokens.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusNotFound {
		t.Fatalf("foreign configuration returned %d", record.Code)
	}
	request = httptest.NewRequest(http.MethodDelete, "/v1/devices/"+device.ID, nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusNoContent {
		t.Fatalf("revoke device returned %d: %s", record.Code, record.Body.String())
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/devices/"+device.ID+"/configuration", nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusNotFound {
		t.Fatalf("revoked configuration returned %d", record.Code)
	}
	request = httptest.NewRequest(http.MethodDelete, "/v1/sessions/current", nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusNoContent {
		t.Fatalf("logout returned %d", record.Code)
	}
}
