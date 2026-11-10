// Package node3xui talks to the private operator API of 3x-ui v3.11.
// A token is a full panel credential and must never be sent to app clients.
package node3xui

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

const maxResponse = 1 << 20

var nonaClientID = regexp.MustCompile(`^nona_[0-9a-f]{32}$`)

type Client struct {
	base  *url.URL
	token string
	http  *http.Client
}

type Record struct {
	Email      string `json:"email"`
	UUID       string `json:"uuid"`
	Auth       string `json:"auth"`
	Flow       string `json:"flow"`
	Enable     bool   `json:"enable"`
	InboundIDs []int  `json:"-"`
}

type response struct {
	Success bool            `json:"success"`
	Object  json.RawMessage `json:"obj"`
}

func New(baseURL, token string, transport *http.Client) (*Client, error) {
	base, err := url.Parse(baseURL)
	if err != nil || base.Scheme != "https" || base.Host == "" || base.User != nil ||
		base.RawQuery != "" || base.Fragment != "" || !strings.HasSuffix(base.Path, "/") ||
		strings.Contains(base.Path, "..") || len(token) < 32 || strings.ContainsAny(token, "\r\n") {
		return nil, errors.New("invalid panel connection settings")
	}
	if transport == nil {
		transport = &http.Client{Timeout: 10 * time.Second}
	}
	client := *transport
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	if client.Timeout == 0 || client.Timeout > 30*time.Second {
		client.Timeout = 10 * time.Second
	}
	return &Client{base: base, token: token, http: &client}, nil
}

func (c *Client) call(ctx context.Context, method, path string, body any) (json.RawMessage, error) {
	var input io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, errors.New("invalid panel request")
		}
		input = bytes.NewReader(encoded)
	}
	target := *c.base
	target.Path = c.base.Path + "panel/api/clients/" + path
	req, err := http.NewRequestWithContext(ctx, method, target.String(), input)
	if err != nil {
		return nil, errors.New("invalid panel request")
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, errors.New("panel request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("panel returned HTTP %d", resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, maxResponse+1))
	if err != nil || len(raw) > maxResponse {
		return nil, errors.New("invalid panel response size")
	}
	var result response
	if json.Unmarshal(raw, &result) != nil || !result.Success {
		return nil, errors.New("panel rejected request")
	}
	return result.Object, nil
}

func (c *Client) Get(ctx context.Context, email string) (Record, error) {
	if err := validateEmail(email); err != nil {
		return Record{}, err
	}
	object, err := c.call(ctx, http.MethodGet, "get/"+email, nil)
	if err != nil {
		return Record{}, err
	}
	var payload struct {
		Client     Record `json:"client"`
		InboundIDs []int  `json:"inboundIds"`
	}
	if json.Unmarshal(object, &payload) != nil || payload.Client.Email != email {
		return Record{}, errors.New("invalid panel client response")
	}
	payload.Client.InboundIDs = payload.InboundIDs
	return payload.Client, nil
}

func (c *Client) Add(ctx context.Context, email string, inboundIDs []int) error {
	if err := validateEmail(email); err != nil {
		return err
	}
	if len(inboundIDs) == 0 || len(inboundIDs) > 8 {
		return errors.New("invalid inbound selection")
	}
	seen := map[int]bool{}
	for _, id := range inboundIDs {
		if id < 1 || seen[id] {
			return errors.New("invalid inbound selection")
		}
		seen[id] = true
	}
	_, err := c.call(ctx, http.MethodPost, "add", map[string]any{
		"client":     map[string]any{"email": email, "enable": true},
		"inboundIds": inboundIDs,
	})
	return err
}

func (c *Client) Delete(ctx context.Context, email string) error {
	if err := validateEmail(email); err != nil {
		return err
	}
	_, err := c.call(ctx, http.MethodPost, "del/"+email, nil)
	return err
}

func validateEmail(value string) error {
	if !nonaClientID.MatchString(value) {
		return errors.New("invalid panel client identifier")
	}
	return nil
}
