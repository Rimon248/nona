package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"nona.example/control-api/internal/auth"
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
	if first.AccessToken == "" || first.RefreshToken == "" {
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
	if second.RefreshToken == first.RefreshToken || second.AccessToken == first.AccessToken {
		t.Fatal("tokens were not rotated")
	}
	request = httptest.NewRequest(http.MethodDelete, "/v1/sessions/current", nil)
	request.Header.Set("Authorization", "Bearer "+second.AccessToken)
	record = httptest.NewRecorder()
	mux.ServeHTTP(record, request)
	if record.Code != http.StatusNoContent {
		t.Fatalf("logout returned %d", record.Code)
	}
}
