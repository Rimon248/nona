package auth

import (
	"context"
	"crypto/ecdh"
	"encoding/base64"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var ErrInvalidDevice = errors.New("invalid device")
var ErrDeviceLimit = errors.New("device limit reached")
var ErrDeviceExists = errors.New("device key already registered")
var ErrDeviceNotFound = errors.New("device not found")

type Device struct {
	ID        string     `json:"id"`
	Label     string     `json:"label"`
	PublicKey string     `json:"public_key"`
	CreatedAt time.Time  `json:"created_at"`
	RevokedAt *time.Time `json:"revoked_at"`
}

func validateDevice(label, encodedKey string) ([]byte, string, error) {
	label = strings.TrimSpace(label)
	if label == "" || len([]rune(label)) > 64 || len(label) > 256 || strings.ContainsAny(label, "\x00\r\n") {
		return nil, "", ErrInvalidDevice
	}
	key, err := base64.RawURLEncoding.DecodeString(encodedKey)
	if err != nil || len(key) != 32 || base64.RawURLEncoding.EncodeToString(key) != encodedKey {
		return nil, "", ErrInvalidDevice
	}
	public, err := ecdh.X25519().NewPublicKey(key)
	if err != nil {
		return nil, "", ErrInvalidDevice
	}
	probe := make([]byte, 32)
	probe[0] = 8
	private, err := ecdh.X25519().NewPrivateKey(probe)
	if err != nil {
		return nil, "", err
	}
	if _, err := private.ECDH(public); err != nil {
		return nil, "", ErrInvalidDevice
	}
	return key, label, nil
}

// RegisterDevice serializes registrations per account, enforcing an eight-device cap.
func (s *Service) RegisterDevice(ctx context.Context, accountID, label, encodedKey string) (Device, error) {
	key, label, err := validateDevice(label, encodedKey)
	if err != nil {
		return Device{}, err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Device{}, err
	}
	defer tx.Rollback(ctx)
	var lockedID string
	if err := tx.QueryRow(ctx, `SELECT id FROM accounts WHERE id=$1 AND disabled_at IS NULL FOR UPDATE`, accountID).Scan(&lockedID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Device{}, ErrInvalidCredentials
		}
		return Device{}, err
	}
	var count int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM devices WHERE account_id=$1 AND revoked_at IS NULL`, accountID).Scan(&count); err != nil {
		return Device{}, err
	}
	if count >= 8 {
		return Device{}, ErrDeviceLimit
	}
	id, err := newID()
	if err != nil {
		return Device{}, err
	}
	device := Device{ID: id, Label: label, PublicKey: encodedKey}
	err = tx.QueryRow(ctx, `INSERT INTO devices (id, account_id, label, public_key) VALUES ($1,$2,$3,$4) RETURNING created_at`, id, accountID, label, key).Scan(&device.CreatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Device{}, ErrDeviceExists
		}
		return Device{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Device{}, err
	}
	return device, nil
}

func (s *Service) ListDevices(ctx context.Context, accountID string) ([]Device, error) {
	rows, err := s.pool.Query(ctx, `SELECT id, label, public_key, created_at, revoked_at FROM devices WHERE account_id=$1 ORDER BY created_at, id`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]Device, 0)
	for rows.Next() {
		var device Device
		var key []byte
		if err := rows.Scan(&device.ID, &device.Label, &key, &device.CreatedAt, &device.RevokedAt); err != nil {
			return nil, err
		}
		device.PublicKey = base64.RawURLEncoding.EncodeToString(key)
		result = append(result, device)
	}
	return result, rows.Err()
}

// RevokeDevice marks the device inactive. Transport credentials are not yet
// issued by this service, so no remote node state needs changing at this stage.
func (s *Service) RevokeDevice(ctx context.Context, accountID, deviceID string, now time.Time) error {
	command, err := s.pool.Exec(ctx, `UPDATE devices SET revoked_at=$3 WHERE id=$1 AND account_id=$2 AND revoked_at IS NULL`, deviceID, accountID, now)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrDeviceNotFound
	}
	return nil
}
