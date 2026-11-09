package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestInfoDoesNotClaimProvisioning(t *testing.T) {
	r := httptest.NewRecorder()
	handler().ServeHTTP(r, httptest.NewRequest(http.MethodGet, "/v1/info", nil))
	if r.Code != http.StatusOK || !strings.Contains(r.Body.String(), `"provisioning_enabled":false`) {
		t.Fatalf("unexpected response: %d %s", r.Code, r.Body.String())
	}
	if r.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("response must not be cached")
	}
}
