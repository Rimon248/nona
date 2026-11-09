package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"nona.example/control-api/internal/auth"
	"nona.example/control-api/internal/database"
	"nona.example/control-api/internal/oidc"
)

type loginLimiter struct {
	mu         sync.Mutex
	global     []time.Time
	byUsername map[string][]time.Time
}

func (l *loginLimiter) allow(username string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.byUsername == nil {
		l.byUsername = make(map[string][]time.Time)
	}
	keep := func(times []time.Time, duration time.Duration) []time.Time {
		var result []time.Time
		for _, at := range times {
			if now.Sub(at) < duration {
				result = append(result, at)
			}
		}
		return result
	}
	l.global = keep(l.global, time.Minute)
	if len(l.global) >= 30 {
		return false
	}
	username = strings.ToLower(strings.TrimSpace(username))
	if len(l.byUsername) > 1000 {
		clear(l.byUsername)
	}
	recent := keep(l.byUsername[username], 5*time.Minute)
	if len(recent) >= 5 {
		l.byUsername[username] = recent
		return false
	}
	l.global = append(l.global, now)
	l.byUsername[username] = append(recent, now)
	return true
}

func decodeJSON(w http.ResponseWriter, r *http.Request, value any) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		http.Error(w, "Content-Type must be application/json", http.StatusUnsupportedMediaType)
		return false
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return false
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		http.Error(w, "trailing JSON", http.StatusBadRequest)
		return false
	}
	return true
}

func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(header, "Bearer ")
}

func handler(service *auth.Service) http.Handler {
	return handlerWithOIDC(service, nil)
}

func handlerWithOIDC(service *auth.Service, verifier *oidc.Verifier) http.Handler {
	mux := http.NewServeMux()
	limiter := &loginLimiter{}
	loginSlots := make(chan struct{}, 2)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if service == nil {
			http.Error(w, "account service unavailable", http.StatusServiceUnavailable)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := service.Ready(ctx); err != nil {
			http.Error(w, "account service unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	})
	mux.HandleFunc("GET /v1/info", func(w http.ResponseWriter, r *http.Request) {
		provider := "local"
		if verifier != nil {
			provider = "keycloak"
		}
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"service":              "nona-control-api",
			"api_version":          1,
			"provisioning_enabled": false,
			"accounts_enabled":     service != nil,
			"authentication":       provider,
		})
	})
	if service != nil {
		if verifier == nil {
			mux.HandleFunc("POST /v1/sessions", func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Cache-Control", "no-store")
				var input struct {
					Username string `json:"username"`
					Password string `json:"password"`
				}
				if !decodeJSON(w, r, &input) {
					return
				}
				if !limiter.allow(input.Username, time.Now()) {
					http.Error(w, "too many attempts", http.StatusTooManyRequests)
					return
				}
				select {
				case loginSlots <- struct{}{}:
					defer func() { <-loginSlots }()
				default:
					http.Error(w, "server busy", http.StatusTooManyRequests)
					return
				}
				tokens, err := service.Login(r.Context(), input.Username, input.Password, time.Now().UTC())
				if errors.Is(err, auth.ErrInvalidCredentials) {
					http.Error(w, "invalid credentials", http.StatusUnauthorized)
					return
				}
				if err != nil {
					http.Error(w, "server error", http.StatusInternalServerError)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				_ = json.NewEncoder(w).Encode(tokens)
			})
			mux.HandleFunc("POST /v1/sessions/refresh", func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Cache-Control", "no-store")
				var input struct {
					RefreshToken string `json:"refresh_token"`
				}
				if !decodeJSON(w, r, &input) {
					return
				}
				tokens, err := service.Refresh(r.Context(), input.RefreshToken, time.Now().UTC())
				if errors.Is(err, auth.ErrInvalidCredentials) {
					http.Error(w, "invalid credentials", http.StatusUnauthorized)
					return
				}
				if err != nil {
					http.Error(w, "server error", http.StatusInternalServerError)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				_ = json.NewEncoder(w).Encode(tokens)
			})
			mux.HandleFunc("DELETE /v1/sessions/current", func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Cache-Control", "no-store")
				err := service.Logout(r.Context(), bearerToken(r), time.Now().UTC())
				if errors.Is(err, auth.ErrInvalidCredentials) {
					http.Error(w, "unauthorized", http.StatusUnauthorized)
					return
				}
				if err != nil {
					http.Error(w, "server error", http.StatusInternalServerError)
					return
				}
				w.WriteHeader(http.StatusNoContent)
			})
		}
		currentAccount := func(w http.ResponseWriter, r *http.Request) (string, bool) {
			var session auth.Session
			var err error
			if verifier != nil {
				var identity oidc.Identity
				identity, err = verifier.Verify(r.Context(), bearerToken(r), time.Now().UTC())
				if err == nil {
					session, err = service.AuthenticateOIDC(r.Context(), identity.Subject)
				}
				if errors.Is(err, oidc.ErrInvalidToken) {
					err = auth.ErrInvalidCredentials
				}
			} else {
				session, err = service.Authenticate(r.Context(), bearerToken(r), time.Now().UTC())
			}
			if errors.Is(err, auth.ErrInvalidCredentials) {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return "", false
			}
			if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				return "", false
			}
			return session.AccountID, true
		}
		if verifier != nil {
			mux.HandleFunc("GET /v1/account", func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Cache-Control", "no-store")
				accountID, ok := currentAccount(w, r)
				if !ok {
					return
				}
				identity, err := verifier.Verify(r.Context(), bearerToken(r), time.Now().UTC())
				if err != nil {
					http.Error(w, "unauthorized", http.StatusUnauthorized)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				_ = json.NewEncoder(w).Encode(map[string]string{
					"account_id": accountID, "username": identity.Username, "provider": "keycloak",
				})
			})
		}
		mux.HandleFunc("POST /v1/devices", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			accountID, ok := currentAccount(w, r)
			if !ok {
				return
			}
			var input struct {
				Label     string `json:"label"`
				PublicKey string `json:"public_key"`
			}
			if !decodeJSON(w, r, &input) {
				return
			}
			device, err := service.RegisterDevice(r.Context(), accountID, input.Label, input.PublicKey)
			if errors.Is(err, auth.ErrInvalidDevice) {
				http.Error(w, "invalid device", http.StatusBadRequest)
				return
			}
			if errors.Is(err, auth.ErrDeviceExists) {
				http.Error(w, "device key already registered", http.StatusConflict)
				return
			}
			if errors.Is(err, auth.ErrDeviceLimit) {
				http.Error(w, "device limit reached", http.StatusConflict)
				return
			}
			if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusCreated)
			_ = json.NewEncoder(w).Encode(device)
		})
		mux.HandleFunc("GET /v1/devices", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			accountID, ok := currentAccount(w, r)
			if !ok {
				return
			}
			devices, err := service.ListDevices(r.Context(), accountID)
			if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(devices)
		})
		mux.HandleFunc("GET /v1/devices/{id}/configuration", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			accountID, ok := currentAccount(w, r)
			if !ok {
				return
			}
			envelope, err := service.DeviceConfiguration(r.Context(), accountID, r.PathValue("id"), time.Now().UTC())
			if errors.Is(err, auth.ErrConfigurationNotFound) {
				http.Error(w, "configuration not found", http.StatusNotFound)
				return
			}
			if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = io.WriteString(w, envelope)
		})
		mux.HandleFunc("DELETE /v1/devices/{id}", func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Cache-Control", "no-store")
			accountID, ok := currentAccount(w, r)
			if !ok {
				return
			}
			if err := service.RevokeDevice(r.Context(), accountID, r.PathValue("id"), time.Now().UTC()); errors.Is(err, auth.ErrDeviceNotFound) {
				http.Error(w, "device not found", http.StatusNotFound)
			} else if err != nil {
				http.Error(w, "server error", http.StatusInternalServerError)
			} else {
				w.WriteHeader(http.StatusNoContent)
			}
		})
	}
	return mux
}

func main() {
	addr := os.Getenv("NONA_LISTEN_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8080"
	}
	var service *auth.Service
	var verifier *oidc.Verifier
	if databaseURL := os.Getenv("NONA_DATABASE_URL"); databaseURL != "" {
		host, _, err := net.SplitHostPort(addr)
		ip := net.ParseIP(host)
		containerPrivateListen := host == "0.0.0.0" && os.Getenv("NONA_DOCKER_UNPUBLISHED") == "1"
		if err != nil || (!containerPrivateListen && host != "localhost" && (ip == nil || !ip.IsLoopback())) {
			log.Fatal("account API must listen on loopback or an explicitly unpublished Docker network behind HTTPS")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		pool, err := database.Open(ctx, databaseURL)
		if err != nil {
			log.Fatal("invalid database configuration")
		}
		defer pool.Close()
		if err := pool.Ping(ctx); err != nil {
			log.Fatal("database unavailable")
		}
		service, err = auth.NewService(pool)
		if err != nil {
			log.Fatal("account service initialization failed")
		}
		if err := service.CheckSchema(ctx); err != nil {
			log.Fatal("database migration is missing")
		}
		if issuer := os.Getenv("NONA_OIDC_ISSUER"); issuer != "" {
			if !strings.HasPrefix(issuer, "https://") || os.Getenv("NONA_OIDC_JWKS_URL") == "" {
				log.Fatal("invalid OIDC configuration")
			}
			if err := service.CheckOIDCSchema(ctx); err != nil {
				log.Fatal("OIDC database migration is missing")
			}
			verifier = &oidc.Verifier{
				Issuer: issuer, Audience: "nona-api", ClientID: "nona-client",
				JWKSURL: os.Getenv("NONA_OIDC_JWKS_URL"), HTTP: &http.Client{Timeout: 3 * time.Second},
			}
		}
		go func() {
			ticker := time.NewTicker(24 * time.Hour)
			defer ticker.Stop()
			for range ticker.C {
				pruneContext, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				if err := service.PruneExpiredSessions(pruneContext, time.Now().UTC()); err != nil {
					log.Print("could not prune expired sessions")
				}
				cancel()
			}
		}()
	}
	server := &http.Server{
		Addr:              addr,
		Handler:           handlerWithOIDC(service, verifier),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Printf("control API listening on %s", addr)
	log.Fatal(server.ListenAndServe())
}
