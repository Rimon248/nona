package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInfoDoesNotClaimProvisioning(t *testing.T) {
	r := httptest.NewRecorder()
	handler(nil).ServeHTTP(r, httptest.NewRequest(http.MethodGet, "/v1/info", nil))
	if r.Code != http.StatusOK || !strings.Contains(r.Body.String(), `"provisioning_enabled":false`) {
		t.Fatalf("unexpected response: %d %s", r.Code, r.Body.String())
	}
	if r.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("response must not be cached")
	}
}

func TestReadinessRequiresAccountService(t *testing.T) {
	r := httptest.NewRecorder()
	handler(nil).ServeHTTP(r, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if r.Code != http.StatusServiceUnavailable {
		t.Fatalf("unexpected readiness response: %d", r.Code)
	}
}

func TestJSONBodyRejectsTrailingData(t *testing.T) {
	r := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(`{"a":1} {"b":2}`))
	request.Header.Set("Content-Type", "application/json")
	var value map[string]any
	if decodeJSON(r, request, &value) || r.Code != http.StatusBadRequest {
		t.Fatalf("trailing JSON accepted: %d", r.Code)
	}
}
