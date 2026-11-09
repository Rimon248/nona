package database

import (
	"context"
	"errors"
	"io"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Open accepts a database URL and, for container deployments, a password file.
// The file avoids placing the password in the Compose file or process environment.
func Open(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, err
	}
	if path := os.Getenv("NONA_DATABASE_PASSWORD_FILE"); path != "" {
		file, err := os.Open(path)
		if err != nil {
			return nil, err
		}
		defer file.Close()
		info, err := file.Stat()
		if err != nil || !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > 256 {
			return nil, errors.New("invalid database password file")
		}
		password, err := io.ReadAll(io.LimitReader(file, 257))
		if err != nil || len(password) > 256 {
			return nil, errors.New("invalid database password file")
		}
		value := strings.TrimSuffix(string(password), "\n")
		if value == "" || strings.ContainsAny(value, "\r\n") {
			return nil, errors.New("invalid database password file")
		}
		config.ConnConfig.Password = value
		clear(password)
	}
	return pgxpool.NewWithConfig(ctx, config)
}
