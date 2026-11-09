package auth

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSessionLifecycleAgainstPostgres(t *testing.T) {
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
	username := "alice_" + suffix[:8]
	accountID, err := service.CreateAccount(ctx, username, "a long test password")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Exec(context.Background(), `DELETE FROM accounts WHERE id=$1`, accountID)
	now := time.Now().UTC()
	if _, err := service.Login(ctx, username, "wrong password here", now); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("wrong password accepted: %v", err)
	}
	first, err := service.Login(ctx, username, "a long test password", now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Authenticate(ctx, first.AccessToken, now); err != nil {
		t.Fatal(err)
	}
	second, err := service.Refresh(ctx, first.RefreshToken, now.Add(time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Authenticate(ctx, first.AccessToken, now.Add(time.Minute)); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("rotated access token accepted: %v", err)
	}
	if _, err := service.Authenticate(ctx, second.AccessToken, now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Refresh(ctx, first.RefreshToken, now.Add(2*time.Minute)); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("reused refresh token accepted: %v", err)
	}
	if _, err := service.Authenticate(ctx, second.AccessToken, now.Add(2*time.Minute)); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("replayed refresh token did not revoke session: %v", err)
	}
	third, err := service.Login(ctx, username, "a long test password", now)
	if err != nil {
		t.Fatal(err)
	}
	if err := service.Logout(ctx, third.AccessToken, now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Authenticate(ctx, third.AccessToken, now.Add(time.Minute)); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("logged out token accepted: %v", err)
	}
}
