package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"nona.example/control-api/internal/auth"
	"nona.example/control-api/internal/oidc"
)

const adminOrigin = "https://nona.server.basketref.ru"

func adminHandler(service *auth.Service, verifier *oidc.Verifier, keycloak *keycloakAdmin, ownerSub string) http.Handler {
	mux := http.NewServeMux()
	authorized := func(w http.ResponseWriter, r *http.Request) (oidc.Identity, map[string]bool, bool) {
		w.Header().Set("Cache-Control", "no-store")
		if verifier == nil {
			http.Error(w, "admin authentication unavailable", http.StatusServiceUnavailable)
			return oidc.Identity{}, nil, false
		}
		// oauth2-proxy supplies this token after its own role check. The token is
		// independently verified here, so direct access to the private service
		// cannot turn an untrusted header into operator access.
		identity, err := verifier.Verify(r.Context(), r.Header.Get("X-Forwarded-Access-Token"), time.Now().UTC())
		if err != nil {
			http.Error(w, "forbidden", http.StatusForbidden)
			return oidc.Identity{}, nil, false
		}
		operators, err := keycloak.Operators(r.Context())
		if err != nil {
			http.Error(w, "administrator check unavailable", http.StatusServiceUnavailable)
			return oidc.Identity{}, nil, false
		}
		if !operators[identity.Subject] {
			http.Error(w, "forbidden", http.StatusForbidden)
			return oidc.Identity{}, nil, false
		}
		allowed, err := service.OperatorAccountAllowed(r.Context(), identity.Subject)
		if err != nil {
			http.Error(w, "administrator check unavailable", http.StatusServiceUnavailable)
			return oidc.Identity{}, nil, false
		}
		if !allowed {
			http.Error(w, "forbidden", http.StatusForbidden)
			return oidc.Identity{}, nil, false
		}
		return identity, operators, true
	}
	mux.HandleFunc("GET /admin/api/users", func(w http.ResponseWriter, r *http.Request) {
		identity, operators, ok := authorized(w, r)
		if !ok {
			return
		}
		users, err := service.ListAccounts(r.Context())
		if err != nil {
			http.Error(w, "could not load users", http.StatusInternalServerError)
			return
		}
		for i := range users {
			users[i].Operator = operators[users[i].Subject]
			users[i].Owner = users[i].Subject == ownerSub
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{"users": users,
			"can_manage_operators": identity.Subject == ownerSub, "can_delete_users": identity.Subject == ownerSub})
	})
	mux.HandleFunc("POST /admin/api/users/{id}/access", func(w http.ResponseWriter, r *http.Request) {
		if _, _, ok := authorized(w, r); !ok {
			return
		}
		if r.Header.Get("Origin") != adminOrigin || !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			http.Error(w, "invalid request origin", http.StatusForbidden)
			return
		}
		var input struct {
			Decision string `json:"decision"`
		}
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&input); err != nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		var trailing any
		if decoder.Decode(&trailing) != io.EOF {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		var status string
		switch input.Decision {
		case "approve":
			status = "approved"
		case "deny":
			status = "revoking"
		default:
			http.Error(w, "invalid decision", http.StatusBadRequest)
			return
		}
		if err := service.SetAccessStatus(r.Context(), r.PathValue("id"), status); err != nil {
			switch {
			case errors.Is(err, auth.ErrAccountNotFound):
				http.Error(w, "user not found", http.StatusNotFound)
			case errors.Is(err, auth.ErrAccessTransition):
				http.Error(w, "revocation in progress", http.StatusConflict)
			default:
				http.Error(w, "could not change access", http.StatusInternalServerError)
			}
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": status})
	})
	mux.HandleFunc("POST /admin/api/users/{id}/operator", func(w http.ResponseWriter, r *http.Request) {
		identity, _, ok := authorized(w, r)
		if !ok {
			return
		}
		if identity.Subject != ownerSub || ownerSub == "" {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		if r.Header.Get("Origin") != adminOrigin || !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			http.Error(w, "invalid request origin", http.StatusForbidden)
			return
		}
		var input struct {
			Enabled *bool `json:"enabled"`
		}
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
		decoder.DisallowUnknownFields()
		if decoder.Decode(&input) != nil || input.Enabled == nil {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		var trailing any
		if decoder.Decode(&trailing) != io.EOF {
			http.Error(w, "invalid request", http.StatusBadRequest)
			return
		}
		subject, err := service.OIDCSubject(r.Context(), r.PathValue("id"))
		if errors.Is(err, auth.ErrAccountNotFound) {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}
		if err != nil {
			http.Error(w, "could not load user", http.StatusInternalServerError)
			return
		}
		if subject == ownerSub {
			http.Error(w, "owner role is protected", http.StatusForbidden)
			return
		}
		if err := keycloak.SetOperator(r.Context(), subject, *input.Enabled); err != nil {
			http.Error(w, "could not change administrator", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]bool{"operator": *input.Enabled})
	})
	mux.HandleFunc("DELETE /admin/api/users/{id}", func(w http.ResponseWriter, r *http.Request) {
		identity, _, ok := authorized(w, r)
		if !ok {
			return
		}
		if identity.Subject != ownerSub || ownerSub == "" || r.Header.Get("Origin") != adminOrigin {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		accountID := r.PathValue("id")
		subject, err := service.OIDCSubject(r.Context(), accountID)
		if errors.Is(err, auth.ErrAccountNotFound) {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}
		if err != nil {
			http.Error(w, "could not load user", http.StatusInternalServerError)
			return
		}
		if subject == ownerSub || subject == identity.Subject {
			http.Error(w, "owner account is protected", http.StatusForbidden)
			return
		}
		if err := service.MarkAccountDeleting(r.Context(), accountID); err != nil {
			switch {
			case errors.Is(err, auth.ErrAccountNotFound):
				http.Error(w, "user not found", http.StatusNotFound)
			case errors.Is(err, auth.ErrAccessTransition):
				http.Error(w, "deletion in progress", http.StatusConflict)
			default:
				http.Error(w, "could not schedule deletion", http.StatusInternalServerError)
			}
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusAccepted)
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "deleting"})
	})
	return mux
}

func removeDeviceAccess(pool *pgxpool.Pool, accountID, deviceID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	nodes, err := loadNodes()
	if err != nil {
		return err
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, deviceID); err != nil {
		return err
	}
	var hasCredentials bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM device_remote_credentials r
		JOIN devices d ON d.id=r.device_id WHERE r.device_id=$1 AND d.account_id=$2)`, deviceID, accountID).Scan(&hasCredentials); err != nil {
		return err
	}
	if hasCredentials {
		if err := deleteRemoteClients(ctx, pool, accountID, deviceID, nodes); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `DELETE FROM device_configurations WHERE device_id=$1`, deviceID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM device_remote_credentials WHERE device_id=$1`, deviceID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM device_provisioning_attempts WHERE device_id=$1`, deviceID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func provisioningRetryDelay(attempts int) time.Duration {
	if attempts <= 1 {
		return time.Minute
	}
	delay := time.Minute * time.Duration(1<<min(attempts-1, 4))
	if delay > 15*time.Minute {
		return 15 * time.Minute
	}
	return delay
}

func recordProvisionFailure(ctx context.Context, pool *pgxpool.Pool, deviceID string) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var attempts int
	err = tx.QueryRow(ctx, `INSERT INTO device_provisioning_attempts
		(device_id, attempts, last_failed_at, next_attempt_at) VALUES ($1,1,now(),now())
		ON CONFLICT (device_id) DO UPDATE SET
		attempts=LEAST(device_provisioning_attempts.attempts+1,1000), last_failed_at=now()
		RETURNING attempts`, deviceID).Scan(&attempts)
	if err != nil {
		return err
	}
	seconds := int(provisioningRetryDelay(attempts).Seconds())
	if _, err := tx.Exec(ctx, `UPDATE device_provisioning_attempts
		SET next_attempt_at=now()+$2*interval '1 second' WHERE device_id=$1`, deviceID, seconds); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func reconcileAccess(pool *pgxpool.Pool, service *auth.Service, keycloak *keycloakAdmin, ownerSub string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	// Finish withdrawals and deletions before issuing new access. Both states
	// remain blocked until every VDSina credential has been removed.
	rows, err := pool.Query(ctx, `SELECT id, oidc_subject, vpn_access_status FROM accounts
		WHERE vpn_access_status IN ('revoking','deleting') AND oidc_subject IS NOT NULL
		ORDER BY created_at LIMIT 10`)
	if err != nil {
		return err
	}
	type withdrawal struct{ account, subject, status string }
	var withdrawals []withdrawal
	for rows.Next() {
		var item withdrawal
		if err := rows.Scan(&item.account, &item.subject, &item.status); err != nil {
			rows.Close()
			return err
		}
		withdrawals = append(withdrawals, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()
	for _, item := range withdrawals {
		if item.status == "deleting" && item.subject == ownerSub {
			log.Print("refusing to delete the original administrator")
			continue
		}
		deviceRows, err := pool.Query(ctx, `SELECT id FROM devices WHERE account_id=$1 ORDER BY id`, item.account)
		if err != nil {
			return err
		}
		var devices []string
		for deviceRows.Next() {
			var id string
			if err := deviceRows.Scan(&id); err != nil {
				deviceRows.Close()
				return err
			}
			devices = append(devices, id)
		}
		if err := deviceRows.Err(); err != nil {
			deviceRows.Close()
			return err
		}
		deviceRows.Close()
		failed := false
		for _, deviceID := range devices {
			if err := removeDeviceAccess(pool, item.account, deviceID); err != nil {
				log.Printf("could not revoke VPN credentials for device %s", deviceID)
				failed = true
			}
		}
		if !failed {
			if item.status == "deleting" {
				if err := keycloak.DeleteUser(ctx, item.subject); err != nil {
					log.Printf("could not delete Keycloak user for account %s", item.account)
					continue
				}
				if err := service.DeleteOIDCAccount(ctx, item.account, item.subject); err != nil {
					log.Printf("could not finish account deletion for %s", item.account)
					continue
				}
			} else if err := service.SetAccessStatus(ctx, item.account, "denied"); err != nil {
				return err
			}
		}
	}
	nodeIDs, err := configuredNodeIDs()
	if err != nil {
		return err
	}
	rows, err = pool.Query(ctx, `SELECT d.account_id, d.id FROM devices d
		JOIN accounts a ON a.id=d.account_id
		LEFT JOIN device_configurations c ON c.device_id=d.id
		LEFT JOIN device_provisioning_attempts p ON p.device_id=d.id
		WHERE a.vpn_access_status='approved' AND a.oidc_subject IS NOT NULL
		AND d.revoked_at IS NULL AND (c.device_id IS NULL OR c.expires_at<now()+interval '7 days' OR p.device_id IS NOT NULL
			OR (SELECT count(DISTINCT r.node_id) FROM device_remote_credentials r
				WHERE r.device_id=d.id AND r.node_id=ANY($1::text[]))<cardinality($1::text[]))
		AND (p.device_id IS NULL OR p.next_attempt_at<=now())
		ORDER BY d.created_at LIMIT 10`, nodeIDs)
	if err != nil {
		return err
	}
	type pending struct{ account, device string }
	var pendingDevices []pending
	for rows.Next() {
		var item pending
		if err := rows.Scan(&item.account, &item.device); err != nil {
			rows.Close()
			return err
		}
		pendingDevices = append(pendingDevices, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()
	for _, item := range pendingDevices {
		if err := provisionDevice(pool, service, item.account, item.device); err != nil {
			if retryErr := recordProvisionFailure(ctx, pool, item.device); retryErr != nil {
				return errors.New("could not schedule provisioning retry")
			}
			log.Printf("VPN provisioning deferred for device %s", item.device)
		}
	}
	return nil
}

func serveAdmin() {
	pool, service := openService()
	defer pool.Close()
	issuer, jwks := os.Getenv("NONA_OIDC_ISSUER"), os.Getenv("NONA_OIDC_JWKS_URL")
	if !strings.HasPrefix(issuer, "https://") || jwks == "" {
		log.Fatal("panel OIDC configuration is required")
	}
	verifier := &oidc.Verifier{
		Issuer: issuer, Audience: "nona-panel", ClientID: "nona-panel", RequiredRole: "nona-operator",
		JWKSURL: jwks, HTTP: &http.Client{Timeout: 3 * time.Second},
	}
	keycloak, err := newKeycloakAdmin(os.Getenv("NONA_KC_ADMIN_CLIENT_SECRET_FILE"))
	if err != nil {
		log.Fatal(err)
	}
	ownerSub := os.Getenv("NONA_OWNER_SUB")
	if ownerSub == "" || len(ownerSub) > 256 {
		log.Fatal("Nona owner subject is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	if err := service.CheckOIDCSchema(ctx); err != nil {
		log.Fatal(err)
	}
	cancel()
	go func() {
		for {
			if err := reconcileAccess(pool, service, keycloak, ownerSub); err != nil {
				log.Printf("VPN access reconciliation failed: %v", err)
			}
			time.Sleep(15 * time.Second)
		}
	}()
	server := &http.Server{Addr: "0.0.0.0:8081", Handler: adminHandler(service, verifier, keycloak, ownerSub),
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second,
		WriteTimeout: 15 * time.Second, IdleTimeout: 30 * time.Second}
	log.Print("Nona private admin service listening")
	log.Fatal(server.ListenAndServe())
}
