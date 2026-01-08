package uploader

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

const testToken = "test-token"

func TestHTTPUploader_Upload_NodeState(t *testing.T) {
	expectedNodeState := model.NodeState{
		Host: &model.HostInfo{
			Hostname: "test-host",
		},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Verify Header
		if r.Header.Get("Authorization") != "Bearer "+testToken {
			t.Errorf("expected Authorization header Bearer %s, got %s", testToken, r.Header.Get("Authorization"))
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

	uploader := NewHTTPUploader(server.URL, testToken)
	// Override defaults for test if needed, e.g. timeouts

	err := uploader.Upload(context.Background(), &expectedNodeState)
	if err != nil {
		t.Fatalf("Upload failed: %v", err)
	}
}

func TestHTTPUploader_Upload_BenchmarkRun(t *testing.T) {
	expectedRun := model.BenchmarkRun{
		RunID: "run-123",
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/benchmark_runs" {
			t.Errorf("expected path /api/v1/benchmark_runs, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	uploader := NewHTTPUploader(server.URL, testToken)
	err := uploader.Upload(context.Background(), &expectedRun)
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

func TestHTTPUploader_CheckAuth(t *testing.T) {
	t.Run("Success", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "valid-token")
		err := uploader.CheckAuth(context.Background())
		if err != nil {
			t.Errorf("expected nil error, got %v", err)
		}
	})

	t.Run("Unauthorized", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "invalid-token")
		err := uploader.CheckAuth(context.Background())
		if err == nil {
			t.Fatal("expected error, got nil")
		}
		if !strings.Contains(err.Error(), "401") {
			t.Errorf("expected error to mention 401, got %v", err)
		}
	})
}

func TestHTTPUploader_DetermineEndpoint_Error(t *testing.T) {
	uploader := NewHTTPUploader("http://localhost", "token")
	err := uploader.Upload(context.Background(), "invalid-payload-type")
	if err == nil {
		t.Error("expected error for invalid payload type, got nil")
	}
}

func TestHTTPUploader_Errors(t *testing.T) {
	t.Run("ServerError500", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusInternalServerError)
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "token")
		uploader.MaxRetries = 0
		err := uploader.Upload(context.Background(), &model.NodeState{})
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("TooManyRequests429", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusTooManyRequests)
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "token")
		uploader.MaxRetries = 0
		err := uploader.Upload(context.Background(), &model.NodeState{})
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("BadRequestWithBody", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusBadRequest)
			w.Write([]byte("bad request reason"))
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "token")
		uploader.MaxRetries = 0
		err := uploader.Upload(context.Background(), &model.NodeState{})
		if err == nil {
			t.Fatal("expected error, got nil")
		}
		if !strings.Contains(err.Error(), "bad request reason") {
			t.Errorf("expected error to contain body, got %v", err)
		}
	})

	t.Run("ReadBodyError", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Length", "100")
			w.WriteHeader(http.StatusBadRequest)
			// Close connection without writing body to cause Read error
		}))
		defer server.Close()

		uploader := NewHTTPUploader(server.URL, "token")
		uploader.MaxRetries = 0
		err := uploader.Upload(context.Background(), &model.NodeState{})
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

func TestHTTPUploader_SetNodeID(t *testing.T) {
	uploader := NewHTTPUploader("http://localhost", "token")
	uploader.SetNodeID("test-node")
	if uploader.NodeID != "test-node" {
		t.Errorf("expected test-node, got %s", uploader.NodeID)
	}
}

func TestHTTPUploader_Backoff_ContextCanceled(t *testing.T) {
	uploader := NewHTTPUploader("http://localhost", "token")
	uploader.RetryWaitMin = 1 * time.Hour // Long wait to ensure context cancellation triggers

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	start := time.Now()
	uploader.backoff(ctx, 0)
	duration := time.Since(start)

	if duration > 1*time.Second {
		t.Errorf("backoff took too long (%v), context should have canceled it", duration)
	}
}

func TestInterfaceCompliance(t *testing.T) {
	var _ ports.Uploader = &HTTPUploader{}
}
