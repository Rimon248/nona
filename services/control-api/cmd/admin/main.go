package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/term"
	"nona.example/control-api/internal/auth"
)

func main() {
	if len(os.Args) != 3 || os.Args[1] != "create-user" {
		fmt.Fprintln(os.Stderr, "usage: go run ./cmd/admin create-user USERNAME")
		os.Exit(2)
	}
	url := os.Getenv("NONA_DATABASE_URL")
	if url == "" {
		log.Fatal("NONA_DATABASE_URL is required")
	}
	fd := int(os.Stdin.Fd())
	if !term.IsTerminal(fd) {
		log.Fatal("password must be entered in an interactive terminal")
	}
	fmt.Fprint(os.Stderr, "New password: ")
	first, err := term.ReadPassword(fd)
	if err != nil {
		log.Fatal("could not read password")
	}
	defer clear(first)
	fmt.Fprint(os.Stderr, "\nRepeat password: ")
	second, err := term.ReadPassword(fd)
	if err != nil {
		log.Fatal("could not read password")
	}
	defer clear(second)
	fmt.Fprintln(os.Stderr)
	if string(first) != string(second) {
		log.Fatal("passwords do not match")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		log.Fatal("invalid database configuration")
	}
	defer pool.Close()
	service, err := auth.NewService(pool)
	if err != nil {
		log.Fatal("account service initialization failed")
	}
	if err := service.CheckSchema(ctx); err != nil {
		log.Fatal("database migration is missing")
	}
	id, err := service.CreateAccount(ctx, os.Args[2], string(first))
	if err != nil {
		log.Fatalf("could not create account: %v", err)
	}
	fmt.Printf("Account created: %s\n", id)
}
