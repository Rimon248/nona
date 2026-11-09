package auth

import (
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"nona.example/control-api/internal/configbundle"
)

var ErrConfigurationNotFound = errors.New("configuration not found")
var ErrConfigurationRollback = errors.New("configuration version rollback")

// InstallConfiguration is for a trusted local provisioner or operator path,
// never an authenticated end-user route. Only sealed, signed data is stored.
func (s *Service) InstallConfiguration(ctx context.Context, accountID, deviceID string, envelope configbundle.Envelope, trustedKeys map[string]ed25519.PublicKey, now time.Time) error {
	payload, err := configbundle.Verify(envelope, trustedKeys, accountID, deviceID, 0, now)
	if err != nil {
		return err
	}
	if payload.Version > math.MaxInt64 {
		return errors.New("configuration version is too large")
	}
	raw, err := json.Marshal(envelope)
	if err != nil || len(raw) > 1500000 {
		return errors.New("configuration envelope is too large")
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var owner string
	var revokedAt *time.Time
	if err := tx.QueryRow(ctx, `SELECT account_id, revoked_at FROM devices WHERE id=$1 FOR UPDATE`, deviceID).Scan(&owner, &revokedAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrDeviceNotFound
		}
		return err
	}
	if owner != accountID || revokedAt != nil {
		return ErrDeviceNotFound
	}
	var storedVersion int64
	var storedEnvelope string
	err = tx.QueryRow(ctx, `SELECT version, envelope FROM device_configurations WHERE device_id=$1`, deviceID).Scan(&storedVersion, &storedEnvelope)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if err == nil {
		if payload.Version < uint64(storedVersion) || (payload.Version == uint64(storedVersion) && string(raw) != storedEnvelope) {
			return ErrConfigurationRollback
		}
		if payload.Version == uint64(storedVersion) {
			return tx.Commit(ctx)
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO device_configurations (device_id, version, expires_at, envelope)
		VALUES ($1,$2,$3,$4) ON CONFLICT (device_id) DO UPDATE
		SET version=EXCLUDED.version, expires_at=EXCLUDED.expires_at, envelope=EXCLUDED.envelope, updated_at=now()`,
		deviceID, payload.Version, payload.ExpiresAt, string(raw))
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// DeviceConfiguration reveals the envelope only to the active owner of an
// active device. Missing, foreign, revoked and expired data all look the same.
func (s *Service) DeviceConfiguration(ctx context.Context, accountID, deviceID string, now time.Time) (string, error) {
	var envelope string
	err := s.pool.QueryRow(ctx, `SELECT c.envelope FROM device_configurations c
		JOIN devices d ON d.id=c.device_id
		WHERE d.id=$1 AND d.account_id=$2 AND d.revoked_at IS NULL AND c.expires_at>$3`,
		deviceID, accountID, now).Scan(&envelope)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrConfigurationNotFound
	}
	return envelope, err
}
