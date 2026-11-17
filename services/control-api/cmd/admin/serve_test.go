package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"nona.example/control-api/internal/auth"
)

func TestAdminDeviceViewsHidePublicKeysAndKeepRevocation(t *testing.T) {
	created := time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)
	views := adminDeviceViews([]auth.Device{{
		ID: "device-1", Label: "Android", PublicKey: "private-device-key",
		CreatedAt: created, RevokedAt: &created,
	}})
	encoded, err := json.Marshal(views)
	if err != nil {
		t.Fatal(err)
	}
	if len(views) != 1 || views[0].RevokedAt == nil ||
		strings.Contains(string(encoded), "private-device-key") ||
		!strings.Contains(string(encoded), "revoked_at") {
		t.Fatalf("invalid admin device view: %s", encoded)
	}
}

func TestProvisioningRetryDelay(t *testing.T) {
	for _, test := range []struct {
		attempts int
		want     time.Duration
	}{
		{1, time.Minute}, {2, 2 * time.Minute}, {3, 4 * time.Minute},
		{4, 8 * time.Minute}, {5, 15 * time.Minute}, {1000, 15 * time.Minute},
	} {
		if got := provisioningRetryDelay(test.attempts); got != test.want {
			t.Fatalf("attempt %d: retry after %s, want %s", test.attempts, got, test.want)
		}
	}
}
