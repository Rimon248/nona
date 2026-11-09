package database

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestPasswordComesFromFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "password")
	if err := os.WriteFile(path, []byte("test-password\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NONA_DATABASE_PASSWORD_FILE", path)
	pool, err := Open(context.Background(), "postgres://nona@db:5432/nona?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	if pool.Config().ConnConfig.Password != "test-password" {
		t.Fatal("database password was not loaded from file")
	}
}

func TestPasswordFileRejectsExtraLines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "password")
	if err := os.WriteFile(path, []byte("first\nsecond"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("NONA_DATABASE_PASSWORD_FILE", path)
	if pool, err := Open(context.Background(), "postgres://nona@db:5432/nona?sslmode=disable"); err == nil {
		pool.Close()
		t.Fatal("multiline password file was accepted")
	}
}
