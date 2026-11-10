package main

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/term"
	"nona.example/control-api/internal/auth"
	"nona.example/control-api/internal/configbundle"
	"nona.example/control-api/internal/database"
)

func usage() {
	fmt.Fprintln(os.Stderr, "usage: admin serve | create-user USERNAME | install-configuration ACCOUNT_ID DEVICE_ID ENVELOPE_FILE | provision-device ACCOUNT_ID DEVICE_ID | retire-device ACCOUNT_ID DEVICE_ID")
	os.Exit(2)
}

func openService() (*pgxpool.Pool, *auth.Service) {
	url := os.Getenv("NONA_DATABASE_URL")
	if url == "" {
		log.Fatal("NONA_DATABASE_URL is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool, err := database.Open(ctx, url)
	if err != nil {
		log.Fatal("invalid database configuration")
	}
	service, err := auth.NewService(pool)
	if err != nil {
		pool.Close()
		log.Fatal("account service initialization failed")
	}
	if err := service.CheckSchema(ctx); err != nil {
		pool.Close()
		log.Fatal("database migration is missing")
	}
	return pool, service
}

func createUser(service *auth.Service, username string) {
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
	id, err := service.CreateAccount(ctx, username, string(first))
	if err != nil {
		log.Fatalf("could not create account: %v", err)
	}
	fmt.Printf("Account created: %s\n", id)
}

func installConfiguration(service *auth.Service, accountID, deviceID, filePath string) {
	keyID := os.Getenv("NONA_CONFIG_KEY_ID")
	encodedKey := os.Getenv("NONA_CONFIG_VERIFY_KEY_B64")
	key, err := base64.RawURLEncoding.DecodeString(encodedKey)
	if keyID == "" || err != nil || len(key) != ed25519.PublicKeySize || base64.RawURLEncoding.EncodeToString(key) != encodedKey {
		log.Fatal("a valid NONA_CONFIG_KEY_ID and NONA_CONFIG_VERIFY_KEY_B64 are required")
	}
	file, err := os.Open(filePath)
	if err != nil {
		log.Fatal("could not open configuration file")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > 1500000 {
		log.Fatal("configuration file must be a regular file under 1.5 MB")
	}
	decoder := json.NewDecoder(io.LimitReader(file, 1500001))
	decoder.DisallowUnknownFields()
	var envelope configbundle.Envelope
	if err := decoder.Decode(&envelope); err != nil {
		log.Fatal("invalid configuration envelope")
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		log.Fatal("configuration file has trailing data or exceeds size limit")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := service.InstallConfiguration(ctx, accountID, deviceID, envelope, map[string]ed25519.PublicKey{keyID: key}, time.Now().UTC()); err != nil {
		log.Fatal("configuration was rejected")
	}
	fmt.Println("Configuration installed for device", deviceID)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	switch os.Args[1] {
	case "serve":
		if len(os.Args) != 2 {
			usage()
		}
		serveAdmin()
	case "create-user":
		if len(os.Args) != 3 {
			usage()
		}
		pool, service := openService()
		defer pool.Close()
		createUser(service, os.Args[2])
	case "install-configuration":
		if len(os.Args) != 5 {
			usage()
		}
		pool, service := openService()
		defer pool.Close()
		installConfiguration(service, os.Args[2], os.Args[3], os.Args[4])
	case "provision-device":
		if len(os.Args) != 4 {
			usage()
		}
		pool, service := openService()
		defer pool.Close()
		if err := provisionDevice(pool, service, os.Args[2], os.Args[3]); err != nil {
			log.Print(err)
			os.Exit(1)
		}
	case "retire-device":
		if len(os.Args) != 4 {
			usage()
		}
		pool, service := openService()
		defer pool.Close()
		if err := retireDevice(service, os.Args[2], os.Args[3]); err != nil {
			log.Print(err)
			os.Exit(1)
		}
	default:
		usage()
	}
}
