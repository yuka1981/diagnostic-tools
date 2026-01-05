package uploader

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

func TestHTTPUploader_Upload_NodeState(t *testing.T) {
	expectedToken := "test-token"
	expectedNodeState := model.NodeState{
		Host: model.HostInfo{
			Hostname: "test-host",
		},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify Header
		if r.Header.Get("Authorization") != "Bearer "+expectedToken {
			t.Errorf("expected Authorization header Bearer %s, got %s", expectedToken, r.Header.Get("Authorization"))
		}
		if r.Header.Get("Content-Type") != "application/json" {
			t.Errorf("expected Content-Type application/json, got %s", r.Header.Get("Content-Type"))
		}
		if r.Method != "POST" {
			t.Errorf("expected POST method, got %s", r.Method)
		}
		if r.URL.Path != "/api/v1/inventory/push" {
			t.Errorf("expected path /api/v1/inventory/push, got %s", r.URL.Path)
		}

		// Verify Body
		var receivedState model.NodeState
		if err := json.NewDecoder(r.Body).Decode(&receivedState); err != nil {
			t.Errorf("failed to decode body: %v", err)
		}
		if receivedState.Host.Hostname != expectedNodeState.Host.Hostname {
			t.Errorf("expected hostname %s, got %s", expectedNodeState.Host.Hostname, receivedState.Host.Hostname)
		}

		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	uploader := NewHTTPUploader(server.URL, expectedToken)
	// Override defaults for test if needed, e.g. timeouts

	err := uploader.Upload(context.Background(), &expectedNodeState)
	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}
}

func TestHTTPUploader_Retry(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	uploader := NewHTTPUploader(server.URL, "token")
	uploader.MaxRetries = 3
	uploader.RetryWaitMin = 1 * time.Millisecond // Fast retry for test
	uploader.RetryWaitMax = 10 * time.Millisecond

	err := uploader.Upload(context.Background(), &model.NodeState{})
	if err != nil {
		t.Fatalf("Upload failed after retries: %v", err)
	}

	if attempts != 3 {
		t.Errorf("expected 3 attempts, got %d", attempts)
	}
}

func TestHTTPUploader_Retry_Fail(t *testing.T) {
	attempts := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	uploader := NewHTTPUploader(server.URL, "token")
	uploader.MaxRetries = 2
	uploader.RetryWaitMin = 1 * time.Millisecond

	err := uploader.Upload(context.Background(), &model.NodeState{})
	if err == nil {
		t.Fatal("expected error after max retries, got nil")
	}

	if attempts != 3 { // Initial + 2 Retries = 3 attempts
		t.Errorf("expected 3 attempts, got %d", attempts)
	}
}

func TestInterfaceCompliance(t *testing.T) {
	var _ ports.Uploader = &HTTPUploader{}
}
