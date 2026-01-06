package reporter

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

// Reporter sends progress updates for a benchmark run.
type Reporter struct {
	client            *http.Client
	RunID             string
	APIUrl            string
	APIToken          string
	lastState         string
	heartbeatInterval time.Duration
	mu                sync.Mutex
}

// NewReporter constructs a reporter with sane defaults.
func NewReporter(runID, apiURL, token string) *Reporter {
	return &Reporter{
		RunID:             runID,
		APIUrl:            strings.TrimRight(apiURL, "/"),
		APIToken:          token,
		client:            &http.Client{Timeout: 10 * time.Second},
		heartbeatInterval: 30 * time.Second,
	}
}

// ReportState sends a progress update with the given status and phase.
// It also records the status to be reused by the heartbeat loop.
func (r *Reporter) ReportState(status, phase string) error {
	// No-op if reporting is not configured
	if r == nil || r.RunID == "" || r.APIUrl == "" || r.APIToken == "" {
		return nil
	}

	r.setLastState(status)

	payload := map[string]string{
		"status": status,
	}
	if phase != "" {
		payload["phase"] = phase
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal progress payload: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, r.progressEndpoint(), bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("failed to create progress request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+r.APIToken)

	resp, err := r.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send progress update: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("progress update failed with status %d (also failed to read response body: %w)", resp.StatusCode, err)
	}
	return fmt.Errorf("progress update failed with status %d: %s", resp.StatusCode, string(respBody))
}

// StartHeartbeat begins a ticker loop that refreshes the heartbeat using the latest status.
// It stops automatically when the provided context is canceled.
func (r *Reporter) StartHeartbeat(ctx context.Context) {
	if r == nil || r.RunID == "" || r.APIUrl == "" || r.APIToken == "" {
		return
	}

	ticker := time.NewTicker(r.heartbeatInterval)

	go func() {
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				status := r.getLastState()
				if status == "" {
					continue
				}
				if err := r.ReportState(status, ""); err != nil {
					fmt.Fprintf(os.Stderr, "heartbeat update failed: %v\n", err)
				}
			}
		}
	}()
}

func (r *Reporter) progressEndpoint() string {
	path := fmt.Sprintf("/api/v1/benchmark_runs/%s/progress", url.PathEscape(r.RunID))
	return r.APIUrl + path
}

func (r *Reporter) setLastState(status string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.lastState = status
}

func (r *Reporter) getLastState() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.lastState
}
