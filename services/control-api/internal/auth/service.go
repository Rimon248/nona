package auth

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	accessLifetime  = 15 * time.Minute
	refreshLifetime = 30 * 24 * time.Hour
	sessionLifetime = 90 * 24 * time.Hour
)

var usernamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9._-]{2,31}$`)

type Tokens struct {
	AccountID        string    `json:"account_id"`
	AccessToken      string    `json:"access_token"`
	AccessExpiresAt  time.Time `json:"access_expires_at"`
	RefreshToken     string    `json:"refresh_token"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
}

type Session struct {
	ID        string
	AccountID string
}

type Service struct {
	pool      *pgxpool.Pool
	dummyHash string
}

// Ready reports whether the account database can currently answer requests.
func (s *Service) Ready(ctx context.Context) error {
	return s.pool.Ping(ctx)
}

func NewService(pool *pgxpool.Pool) (*Service, error) {
	if pool == nil {
		return nil, errors.New("database pool is required")
	}
	dummyHash, err := HashPassword("dummy-password-never-used")
	if err != nil {
		return nil, err
	}
	return &Service{pool: pool, dummyHash: dummyHash}, nil
}

// AuthenticateOIDC links a verified Keycloak subject to one local account.
// The caller must verify the JWT signature, issuer, audience and client first.
func (s *Service) AuthenticateOIDC(ctx context.Context, subject, username string) (Session, error) {
	if subject == "" || len(subject) > 256 {
		return Session{}, ErrInvalidCredentials
	}
	username = strings.TrimSpace(username)
	if len(username) < 1 || len(username) > 128 || strings.ContainsAny(username, "\x00\r\n") {
		return Session{}, ErrInvalidCredentials
	}
	id, err := newID()
	if err != nil {
		return Session{}, err
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Session{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, subject); err != nil {
		return Session{}, err
	}
	var deleted bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM deleted_oidc_subjects WHERE oidc_subject=$1)`, subject).Scan(&deleted); err != nil {
		return Session{}, err
	}
	if deleted {
		return Session{}, ErrInvalidCredentials
	}
	_, err = tx.Exec(ctx, `INSERT INTO accounts (id, username, password_hash, oidc_subject, display_username)
		VALUES ($1, $2, $3, $4, $5) ON CONFLICT (oidc_subject) WHERE oidc_subject IS NOT NULL
		DO UPDATE SET display_username=EXCLUDED.display_username`,
		id, "oidc:"+subject, "oidc-managed", subject, username)
	if err != nil {
		return Session{}, err
	}
	var accountID string
	err = tx.QueryRow(ctx, `SELECT id FROM accounts WHERE oidc_subject=$1 AND disabled_at IS NULL`, subject).Scan(&accountID)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrInvalidCredentials
	}
	if err != nil {
		return Session{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Session{}, err
	}
	return Session{ID: "oidc:" + subject, AccountID: accountID}, nil
}

func (s *Service) CheckOIDCSchema(ctx context.Context) error {
	var count int
	err := s.pool.QueryRow(ctx, `SELECT count(*) FROM information_schema.columns
		WHERE table_name='accounts' AND column_name IN ('oidc_subject','display_username','vpn_access_status')`).Scan(&count)
	if err != nil {
		return err
	}
	if count != 3 {
		return errors.New("OIDC or VPN access migration is missing")
	}
	var retryTable *string
	if err := s.pool.QueryRow(ctx, `SELECT to_regclass('public.device_provisioning_attempts')::text`).Scan(&retryTable); err != nil {
		return err
	}
	if retryTable == nil {
		return errors.New("provisioning retry migration is missing")
	}
	var deletedSubjectsTable *string
	if err := s.pool.QueryRow(ctx, `SELECT to_regclass('public.deleted_oidc_subjects')::text`).Scan(&deletedSubjectsTable); err != nil {
		return err
	}
	if deletedSubjectsTable == nil {
		return errors.New("account deletion migration is missing")
	}
	return nil
}

func normalizeUsername(username string) (string, error) {
	username = strings.ToLower(strings.TrimSpace(username))
	if !usernamePattern.MatchString(username) {
		return "", errors.New("username must have 3-32 ASCII letters, digits, dots, underscores or hyphens")
	}
	return username, nil
}

// CreateAccount is for an authenticated operator CLI, never a public route.
func (s *Service) CreateAccount(ctx context.Context, username, password string) (string, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return "", err
	}
	hash, err := HashPassword(password)
	if err != nil {
		return "", err
	}
	id, err := newID()
	if err != nil {
		return "", err
	}
	_, err = s.pool.Exec(ctx,
		`INSERT INTO accounts (id, username, password_hash) VALUES ($1, $2, $3)`,
		id, username, hash)
	if err != nil {
		return "", err
	}
	return id, nil
}

func (s *Service) Login(ctx context.Context, username, password string, now time.Time) (Tokens, error) {
	username, err := normalizeUsername(username)
	if err != nil {
		return Tokens{}, ErrInvalidCredentials
	}
	var accountID, storedHash string
	err = s.pool.QueryRow(ctx,
		`SELECT id, password_hash FROM accounts WHERE username=$1 AND disabled_at IS NULL`, username,
	).Scan(&accountID, &storedHash)
	if errors.Is(err, pgx.ErrNoRows) {
		_, _ = VerifyPassword(s.dummyHash, password)
		return Tokens{}, ErrInvalidCredentials
	}
	if err != nil {
		return Tokens{}, err
	}
	valid, err := VerifyPassword(storedHash, password)
	if err != nil || !valid {
		return Tokens{}, ErrInvalidCredentials
	}

	sessionID, err := newID()
	if err != nil {
		return Tokens{}, err
	}
	access, accessHash, err := newToken()
	if err != nil {
		return Tokens{}, err
	}
	refresh, refreshHash, err := newToken()
	if err != nil {
		return Tokens{}, err
	}
	tokens := Tokens{
		AccountID: accountID, AccessToken: access, AccessExpiresAt: now.Add(accessLifetime),
		RefreshToken: refresh, RefreshExpiresAt: now.Add(refreshLifetime),
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Tokens{}, err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx,
		`INSERT INTO sessions (id, account_id, access_hash, access_expires_at, expires_at) VALUES ($1,$2,$3,$4,$5)`,
		sessionID, accountID, accessHash, tokens.AccessExpiresAt, now.Add(sessionLifetime))
	if err != nil {
		return Tokens{}, err
	}
	_, err = tx.Exec(ctx,
		`INSERT INTO refresh_tokens (token_hash, session_id, expires_at) VALUES ($1,$2,$3)`,
		refreshHash, sessionID, tokens.RefreshExpiresAt)
	if err != nil {
		return Tokens{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Tokens{}, err
	}
	return tokens, nil
}

func (s *Service) Refresh(ctx context.Context, token string, now time.Time) (Tokens, error) {
	hash, err := tokenDigest(token)
	if err != nil {
		return Tokens{}, ErrInvalidCredentials
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Tokens{}, err
	}
	defer tx.Rollback(ctx)
	var sessionID, accountID string
	var expiresAt, sessionExpiresAt time.Time
	var consumedAt, revokedAt, disabledAt *time.Time
	err = tx.QueryRow(ctx, `SELECT r.session_id, s.account_id, r.expires_at, s.expires_at, r.consumed_at, s.revoked_at, a.disabled_at
		FROM refresh_tokens r JOIN sessions s ON s.id=r.session_id
		JOIN accounts a ON a.id=s.account_id WHERE r.token_hash=$1 FOR UPDATE OF r, s`, hash,
	).Scan(&sessionID, &accountID, &expiresAt, &sessionExpiresAt, &consumedAt, &revokedAt, &disabledAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Tokens{}, ErrInvalidCredentials
	}
	if err != nil {
		return Tokens{}, err
	}
	if consumedAt != nil {
		if _, err := tx.Exec(ctx, `UPDATE sessions SET revoked_at=$2 WHERE id=$1 AND revoked_at IS NULL`, sessionID, now); err != nil {
			return Tokens{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return Tokens{}, err
		}
		return Tokens{}, ErrInvalidCredentials
	}
	if revokedAt != nil || disabledAt != nil || !now.Before(expiresAt) || !now.Before(sessionExpiresAt) {
		return Tokens{}, ErrInvalidCredentials
	}
	access, accessHash, err := newToken()
	if err != nil {
		return Tokens{}, err
	}
	refresh, refreshHash, err := newToken()
	if err != nil {
		return Tokens{}, err
	}
	tokens := Tokens{
		AccountID: accountID, AccessToken: access, AccessExpiresAt: now.Add(accessLifetime),
		RefreshToken: refresh, RefreshExpiresAt: now.Add(refreshLifetime),
	}
	if tokens.RefreshExpiresAt.After(sessionExpiresAt) {
		tokens.RefreshExpiresAt = sessionExpiresAt
	}
	if tokens.AccessExpiresAt.After(sessionExpiresAt) {
		tokens.AccessExpiresAt = sessionExpiresAt
	}
	if _, err := tx.Exec(ctx, `UPDATE refresh_tokens SET consumed_at=$2 WHERE token_hash=$1`, hash, now); err != nil {
		return Tokens{}, err
	}
	if _, err := tx.Exec(ctx, `UPDATE sessions SET access_hash=$2, access_expires_at=$3 WHERE id=$1`,
		sessionID, accessHash, tokens.AccessExpiresAt); err != nil {
		return Tokens{}, err
	}
	if _, err := tx.Exec(ctx, `INSERT INTO refresh_tokens (token_hash, session_id, expires_at) VALUES ($1,$2,$3)`,
		refreshHash, sessionID, tokens.RefreshExpiresAt); err != nil {
		return Tokens{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Tokens{}, err
	}
	return tokens, nil
}

func (s *Service) Authenticate(ctx context.Context, token string, now time.Time) (Session, error) {
	hash, err := tokenDigest(token)
	if err != nil {
		return Session{}, ErrInvalidCredentials
	}
	var session Session
	var expiresAt, sessionExpiresAt time.Time
	err = s.pool.QueryRow(ctx, `SELECT s.id, s.account_id, s.access_expires_at, s.expires_at
		FROM sessions s JOIN accounts a ON a.id=s.account_id
		WHERE s.access_hash=$1 AND s.revoked_at IS NULL AND a.disabled_at IS NULL`, hash,
	).Scan(&session.ID, &session.AccountID, &expiresAt, &sessionExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrInvalidCredentials
	}
	if err != nil {
		return Session{}, err
	}
	if !now.Before(expiresAt) || !now.Before(sessionExpiresAt) {
		return Session{}, ErrInvalidCredentials
	}
	return session, nil
}

func (s *Service) Logout(ctx context.Context, token string, now time.Time) error {
	hash, err := tokenDigest(token)
	if err != nil {
		return ErrInvalidCredentials
	}
	command, err := s.pool.Exec(ctx,
		`UPDATE sessions SET revoked_at=$2 WHERE access_hash=$1 AND revoked_at IS NULL AND access_expires_at>$2`, hash, now)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		return ErrInvalidCredentials
	}
	return nil
}

func (s *Service) CheckSchema(ctx context.Context) error {
	for _, table := range []string{"accounts", "sessions", "refresh_tokens", "devices", "device_configurations", "device_remote_credentials"} {
		var exists bool
		if err := s.pool.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, table).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return fmt.Errorf("database table %s is missing; apply migration", table)
		}
	}
	if _, err := s.pool.Exec(ctx, `SELECT expires_at FROM sessions LIMIT 0`); err != nil {
		return errors.New("database schema is outdated; apply migration")
	}
	return nil
}

// PruneExpiredSessions removes token history only after the absolute session
// lifetime. Old refresh tokens remain available for replay detection until then.
func (s *Service) PruneExpiredSessions(ctx context.Context, now time.Time) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE expires_at<$1`, now)
	return err
}
