package auth

import (
	"strings"
	"testing"
)

func TestPasswordHashing(t *testing.T) {
	first, err := HashPassword("a sufficiently long passphrase")
	if err != nil {
		t.Fatal(err)
	}
	second, err := HashPassword("a sufficiently long passphrase")
	if err != nil {
		t.Fatal(err)
	}
	if first == second {
		t.Fatal("salts must differ")
	}
	good, err := VerifyPassword(first, "a sufficiently long passphrase")
	if err != nil || !good {
		t.Fatalf("correct password rejected: %v", err)
	}
	bad, err := VerifyPassword(first, "a different long passphrase")
	if err != nil || bad {
		t.Fatalf("incorrect password accepted: %v", err)
	}
}

func TestPasswordHashRejectsOversizedParameters(t *testing.T) {
	hash, err := HashPassword("a sufficiently long passphrase")
	if err != nil {
		t.Fatal(err)
	}
	hash = strings.Replace(hash, "m=65536", "m=999999999", 1)
	if _, err := VerifyPassword(hash, "a sufficiently long passphrase"); err == nil {
		t.Fatal("oversized Argon2 allocation accepted")
	}
}
