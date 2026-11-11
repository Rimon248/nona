package main

import (
	"testing"
	"time"
)

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
