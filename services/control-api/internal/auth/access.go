package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

var ErrAccountNotFound = errors.New("account not found")
var ErrAccessTransition = errors.New("VPN credentials are still being revoked")

type AccountAccess struct {
	ID                string    `json:"id"`
	Username          string    `json:"username"`
	Subject           string    `json:"-"`
	Status            string    `json:"status"`
	Operator          bool      `json:"operator"`
	Owner             bool      `json:"owner"`
	CreatedAt         time.Time `json:"created_at"`
	ActiveDevices     int       `json:"active_devices"`
	ReadyDevices      int       `json:"ready_devices"`
	RemoteCredentials int       `json:"remote_credentials"`
}

func (s *Service) AccessStatus(ctx context.Context, accountID string) (string, error) {
	var status string
	err := s.pool.QueryRow(ctx, `SELECT vpn_access_status FROM accounts WHERE id=$1 AND disabled_at IS NULL`, accountID).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrAccountNotFound
	}
	return status, err
}

func (s *Service) ListAccounts(ctx context.Context) ([]AccountAccess, error) {
	rows, err := s.pool.Query(ctx, `SELECT a.id, COALESCE(a.display_username,a.username), a.oidc_subject, a.vpn_access_status, a.created_at,
		count(DISTINCT d.id) FILTER (WHERE d.revoked_at IS NULL),
		count(DISTINCT c.device_id) FILTER (WHERE d.revoked_at IS NULL AND c.expires_at>now()),
		count(DISTINCT r.device_id) FILTER (WHERE d.revoked_at IS NULL)
		FROM accounts a LEFT JOIN devices d ON d.account_id=a.id
		LEFT JOIN device_configurations c ON c.device_id=d.id
		LEFT JOIN device_remote_credentials r ON r.device_id=d.id
		WHERE a.oidc_subject IS NOT NULL AND a.disabled_at IS NULL
		GROUP BY a.id ORDER BY a.created_at DESC LIMIT 500`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]AccountAccess, 0)
	for rows.Next() {
		var item AccountAccess
		if err := rows.Scan(&item.ID, &item.Username, &item.Subject, &item.Status, &item.CreatedAt,
			&item.ActiveDevices, &item.ReadyDevices, &item.RemoteCredentials); err != nil {
			return nil, err
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func (s *Service) OIDCSubject(ctx context.Context, accountID string) (string, error) {
	var subject string
	err := s.pool.QueryRow(ctx, `SELECT oidc_subject FROM accounts WHERE id=$1
		AND oidc_subject IS NOT NULL AND disabled_at IS NULL`, accountID).Scan(&subject)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrAccountNotFound
	}
	return subject, err
}

// SetAccessStatus changes only OIDC users. The caller must authenticate an
// operator, and perform remote revocation when setting "revoking".
func (s *Service) SetAccessStatus(ctx context.Context, accountID, status string) error {
	if status != "approved" && status != "revoking" && status != "denied" {
		return errors.New("invalid VPN access status")
	}
	command, err := s.pool.Exec(ctx, `UPDATE accounts SET vpn_access_status=$2
		WHERE id=$1 AND oidc_subject IS NOT NULL AND disabled_at IS NULL
		AND ($2 <> 'approved' OR vpn_access_status <> 'revoking')`, accountID, status)
	if err != nil {
		return err
	}
	if command.RowsAffected() != 1 {
		if _, err := s.AccessStatus(ctx, accountID); err == nil {
			return ErrAccessTransition
		}
		return ErrAccountNotFound
	}
	return nil
}
