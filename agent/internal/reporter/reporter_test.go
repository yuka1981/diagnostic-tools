package reporter

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestReportStateSendsPatchRequest(t *testing.T) {
	var (
		capturedMethod string
		capturedPath   string
		capturedAuth   string
		capturedBody   map[string]string
	)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedMethod = r.Method
		capturedPath = r.URL.Path
		capturedAuth = r.Header.Get("Authorization")
		defer r.Body.Close()

		if err := json.NewDecoder(r.Body).Decode(&capturedBody); err != nil {
			t.Fatalf("failed to decode body: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	rep := NewReporter("run-123", server.URL, "secret-token")

	if err := rep.ReportState("building", "Compiling Source"); err != nil {
		t.Fatalf("ReportState returned error: %v", err)
	}

	if capturedMethod != http.MethodPatch {
		t.Fatalf("expected PATCH method, got %s", capturedMethod)
	}
	if capturedPath != "/api/v1/runs/run-123/progress" {
		t.Fatalf("unexpected path: %s", capturedPath)
	}
	if capturedAuth != "Bearer secret-token" {
		t.Fatalf("unexpected auth header: %s", capturedAuth)
	}
	if capturedBody["status"] != "building" || capturedBody["phase"] != "Compiling Source" {
		t.Fatalf("unexpected body: %#v", capturedBody)
	}
}

func TestStartHeartbeatUsesLatestStatus(t *testing.T) {
	var (
		mu       sync.Mutex
		statuses []string
	)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer r.Body.Close()
		var body map[string]string
		if err := json.NewDecoder(r.Body).Decode(&body); err == nil {
			mu.Lock()
			statuses = append(statuses, body["status"])
			mu.Unlock()
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	rep := NewReporter("run-123", server.URL, "secret-token")
	rep.heartbeatInterval = 10 * time.Millisecond

	// Seed the initial state without relying on the heartbeat
	if err := rep.ReportState("running", "Executing Benchmark"); err != nil {
		t.Fatalf("failed to seed state: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	rep.StartHeartbeat(ctx)

	// Allow a couple of heartbeats to fire
	time.Sleep(25 * time.Millisecond)
	cancel()

	mu.Lock()
	defer mu.Unlock()
	if len(statuses) < 2 {
		t.Fatalf("expected at least 2 progress calls, got %d", len(statuses))
	}
	lastStatus := statuses[len(statuses)-1]
	if lastStatus != "running" {
		t.Fatalf("expected heartbeat to use latest status 'running', got %s", lastStatus)
	}
}
