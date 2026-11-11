package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const keycloakInternal = "http://nona-keycloak:8080/auth"

type keycloakAdmin struct {
	client *http.Client
	secret string
}

func newKeycloakAdmin(secretFile string) (*keycloakAdmin, error) {
	raw, err := readPrivateFile(secretFile, 512)
	if err != nil {
		return nil, errors.New("could not read Keycloak role manager credential")
	}
	secret := strings.TrimSpace(string(raw))
	clear(raw)
	if secret == "" || strings.ContainsAny(secret, "\r\n") {
		return nil, errors.New("invalid Keycloak role manager credential")
	}
	return &keycloakAdmin{secret: secret, client: &http.Client{Timeout: 6 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}, nil
}

func (k *keycloakAdmin) token(ctx context.Context) (string, error) {
	form := url.Values{"grant_type": {"client_credentials"}, "client_id": {"nona-role-manager"}, "client_secret": {k.secret}}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, keycloakInternal+"/realms/nona/protocol/openid-connect/token", strings.NewReader(form.Encode()))
	if err != nil {
		return "", err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := k.client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", errors.New("Keycloak role manager authentication failed")
	}
	var output struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 16384)).Decode(&output); err != nil || output.AccessToken == "" {
		return "", errors.New("invalid Keycloak role manager response")
	}
	return output.AccessToken, nil
}

func (k *keycloakAdmin) call(ctx context.Context, token, method, path string, body io.Reader) (*http.Response, error) {
	request, err := http.NewRequestWithContext(ctx, method, keycloakInternal+"/admin/realms/nona"+path, body)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	return k.client.Do(request)
}

func (k *keycloakAdmin) Operators(ctx context.Context) (map[string]bool, error) {
	token, err := k.token(ctx)
	if err != nil {
		return nil, err
	}
	response, err := k.call(ctx, token, http.MethodGet, "/roles/nona-operator/users?max=500", nil)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Keycloak operator query returned %d", response.StatusCode)
	}
	var users []struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 131072)).Decode(&users); err != nil {
		return nil, err
	}
	result := make(map[string]bool, len(users))
	for _, user := range users {
		result[user.ID] = true
	}
	return result, nil
}

func (k *keycloakAdmin) SetOperator(ctx context.Context, subject string, enabled bool) error {
	if subject == "" || len(subject) > 256 || strings.ContainsAny(subject, "/?#%") {
		return errors.New("invalid Keycloak user")
	}
	token, err := k.token(ctx)
	if err != nil {
		return err
	}
	response, err := k.call(ctx, token, http.MethodGet, "/roles/nona-operator", nil)
	if err != nil {
		return err
	}
	if response.StatusCode != http.StatusOK {
		response.Body.Close()
		return errors.New("Keycloak operator role unavailable")
	}
	role, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	response.Body.Close()
	if err != nil {
		return err
	}
	var representation struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if json.Unmarshal(role, &representation) != nil || representation.ID == "" || representation.Name != "nona-operator" {
		return errors.New("invalid Keycloak operator role")
	}
	method := http.MethodPost
	if !enabled {
		method = http.MethodDelete
	}
	response, err = k.call(ctx, token, method, "/users/"+subject+"/role-mappings/realm", strings.NewReader("["+string(role)+"]"))
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		return fmt.Errorf("Keycloak operator update returned %d", response.StatusCode)
	}
	return nil
}

func (k *keycloakAdmin) DeleteUser(ctx context.Context, subject string) error {
	if subject == "" || len(subject) > 256 || strings.ContainsAny(subject, "/?#%") {
		return errors.New("invalid Keycloak user")
	}
	token, err := k.token(ctx)
	if err != nil {
		return err
	}
	response, err := k.call(ctx, token, http.MethodDelete, "/users/"+subject, nil)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent && response.StatusCode != http.StatusNotFound {
		return errors.New("Keycloak user deletion failed")
	}
	return nil
}
