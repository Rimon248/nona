package auth

import (
	"context"
	"crypto/ecdh"
	"encoding/base64"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func testPublicKey(t *testing.T, seed byte) string {
	t.Helper()
	private := make([]byte, 32)
	private[0] = seed << 3
	key, err := ecdh.X25519().NewPrivateKey(private)
	if err != nil {
		t.Fatal(err)
	}
	return base64.RawURLEncoding.EncodeToString(key.PublicKey().Bytes())
}

func TestDeviceValidation(t *testing.T) {
	key := testPublicKey(t, 1)
	if _, label, err := validateDevice("  My phone  ", key); err != nil || label != "My phone" {
		t.Fatalf("valid device rejected: %v", err)
	}
	for _, input := range []struct{ label, key string }{
		{"", key}, {"bad\nlabel", key}, {"phone", "invalid"}, {"phone", key + "="},
		{"phone", base64.RawURLEncoding.EncodeToString(make([]byte, 32))},
	} {
		if _, _, err := validateDevice(input.label, input.key); !errors.Is(err, ErrInvalidDevice) {
			t.Fatalf("invalid device accepted: %+v", input)
		}
	}
}

func TestDeviceOwnershipAndRevocationAgainstPostgres(t *testing.T) {
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
	service, err := NewService(pool)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.CheckSchema(ctx); err != nil {
		t.Fatal(err)
	}
	suffix, err := newID()
	if err != nil {
		t.Fatal(err)
	}
	first, err := service.CreateAccount(ctx, "dev_a_"+suffix[:8], "a long test password")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM accounts WHERE id=$1`, first)
	second, err := service.CreateAccount(ctx, "dev_b_"+suffix[:8], "a long test password")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM accounts WHERE id=$1`, second)
	key := testPublicKey(t, 1)
	device, err := service.RegisterDevice(ctx, first, "Laptop", key)
	if err != nil {
		t.Fatal(err)
	}
	if device.ID == "" || device.PublicKey != key || device.CreatedAt.IsZero() {
		t.Fatalf("bad device: %+v", device)
	}
	if _, err := service.RegisterDevice(ctx, first, "Other", key); !errors.Is(err, ErrDeviceExists) {
		t.Fatalf("duplicate key accepted: %v", err)
	}
	devices, err := service.ListDevices(ctx, second)
	if err != nil || len(devices) != 0 {
		t.Fatalf("other account saw devices: %+v %v", devices, err)
	}
	if err := service.RevokeDevice(ctx, second, device.ID, time.Now().UTC()); !errors.Is(err, ErrDeviceNotFound) {
		t.Fatalf("other account revoked device: %v", err)
	}
	if err := service.RevokeDevice(ctx, first, device.ID, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	devices, err = service.ListDevices(ctx, first)
	if err != nil || len(devices) != 1 || devices[0].RevokedAt == nil {
		t.Fatalf("revocation missing: %+v %v", devices, err)
	}
	if _, err := service.RegisterDevice(ctx, first, "Reused", key); !errors.Is(err, ErrDeviceExists) {
		t.Fatalf("revoked key reused: %v", err)
	}
	for i := byte(2); i <= 9; i++ {
		if _, err := service.RegisterDevice(ctx, first, "Device", testPublicKey(t, i)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := service.RegisterDevice(ctx, first, "Ninth", testPublicKey(t, 10)); !errors.Is(err, ErrDeviceLimit) {
		t.Fatalf("limit not enforced: %v", err)
	}
}
