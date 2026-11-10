package node3xui

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const testID = "nona_0123456789abcdef0123456789abcdef"
const testToken = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func TestClientLifecycleUsesScopedPaths(t *testing.T) {
	var calls []string
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+testToken {
			t.Errorf("missing bearer token")
		}
		calls = append(calls, r.Method+" "+r.URL.Path)
		if r.URL.Path == "/base/panel/api/clients/add" {
			var payload struct {
				Client struct {
					Email  string `json:"email"`
					Enable bool   `json:"enable"`
				} `json:"client"`
				InboundIDs []int `json:"inboundIds"`
			}
			if json.NewDecoder(r.Body).Decode(&payload) != nil || payload.Client.Email != testID ||
				!payload.Client.Enable || len(payload.InboundIDs) != 2 || payload.InboundIDs[0] != 1 || payload.InboundIDs[1] != 2 {
				t.Error("wrong create request")
			}
		}
		if r.URL.Path == "/base/panel/api/clients/get/"+testID {
			w.Write([]byte(`{"success":true,"obj":{"client":{"email":"` + testID + `","uuid":"00000000-0000-4000-8000-000000000001","auth":"fictional-auth","enable":true},"inboundIds":[1,2]}}`))
			return
		}
		w.Write([]byte(`{"success":true,"obj":{}}`))
	}))
	defer server.Close()
	client, err := New(server.URL+"/base/", testToken, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Add(context.Background(), testID, []int{1, 2}); err != nil {
		t.Fatal(err)
	}
	record, err := client.Get(context.Background(), testID)
	if err != nil || record.UUID == "" || record.Auth == "" || len(record.InboundIDs) != 2 {
		t.Fatalf("bad client response: %v", err)
	}
	if err := client.Delete(context.Background(), testID); err != nil {
		t.Fatal(err)
	}
	if len(calls) != 3 {
		t.Fatalf("wrong call count: %v", calls)
	}
	if err := client.Delete(context.Background(), "someone-else"); err == nil {
		t.Fatal("deleted unmanaged client")
	}
}

func TestClientNeverForwardsTokenToRedirect(t *testing.T) {
	forwarded := false
	other := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		forwarded = true
	}))
	defer other.Close()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, other.URL, http.StatusTemporaryRedirect)
	}))
	defer server.Close()
	client, err := New(server.URL+"/base/", testToken, server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := client.Add(context.Background(), testID, []int{1}); err == nil {
		t.Fatal("accepted redirect")
	}
	if forwarded {
		t.Fatal("forwarded token to redirect")
	}
	if _, err := New("http://example.invalid/base/", testToken, nil); err == nil {
		t.Fatal("accepted plaintext API")
	}
	if _, err := New(server.URL+"/base/", strings.Repeat("x", 32)+"\n", nil); err == nil {
		t.Fatal("accepted header injection")
	}
}
