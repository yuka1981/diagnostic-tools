package uploader

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

const (
	endpointInventory     = "/api/v1/inventory/push"
	endpointBenchmarkRuns = "/api/v1/benchmark_runs"
)

// HTTPUploader implements ports.Uploader using HTTP.
type HTTPUploader struct {
	Client       *http.Client
	BaseURL      string
	Token        string
	NodeID       string
	RetryWaitMin time.Duration
	RetryWaitMax time.Duration
	MaxRetries   int
}

// NewHTTPUploader creates a new HTTP uploader.
func NewHTTPUploader(baseURL, token string) *HTTPUploader {
	return &HTTPUploader{
		BaseURL:      baseURL,
		Token:        token,
		Client:       &http.Client{Timeout: 10 * time.Second},
		MaxRetries:   3,
		RetryWaitMin: 1 * time.Second,
		RetryWaitMax: 30 * time.Second,
	}
}

// SetNodeID sets the unique identifier for the host.
func (u *HTTPUploader) SetNodeID(id string) {
	u.NodeID = id
}

// Upload sends the given payload to the configured endpoint.
func (u *HTTPUploader) Upload(ctx context.Context, payload interface{}) error {
	var endpoint string
	switch payload.(type) {
	case *model.NodeState:
		endpoint = endpointInventory
	case *model.BenchmarkRun:
		endpoint = endpointBenchmarkRuns
	default:
		return fmt.Errorf("unsupported payload type: %T", payload)
	}

	url := u.BaseURL + endpoint
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	for i := 0; i <= u.MaxRetries; i++ {
		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(body))
		if err != nil {
			return fmt.Errorf("failed to create request: %w", err)
		}

		req.Header.Set("Content-Type", "application/json")
		if u.Token != "" {
			req.Header.Set("Authorization", "Bearer "+u.Token)
		}

		if u.NodeID != "" {
			req.Header.Set("X-Node-ID", u.NodeID)
		}

		resp, err := u.Client.Do(req)
		if err != nil {
			if i == u.MaxRetries {
				return fmt.Errorf("failed to send request after %d retries: %w", u.MaxRetries, err)
			}
			u.backoff(ctx, i)
			continue
		}

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			resp.Body.Close()
			return nil
		}

		// Retry on 5xx and 429
		if resp.StatusCode >= 500 || resp.StatusCode == http.StatusTooManyRequests {
			resp.Body.Close() // Not reading body for retryable errors
			if i == u.MaxRetries {
				return fmt.Errorf("server returned error %d after %d retries", resp.StatusCode, u.MaxRetries)
			}
			u.backoff(ctx, i)
			continue
		}

		// Do not retry on other errors (e.g., 400, 401, 403, 404), but include body in error.
		bodyBytes, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil {
			return fmt.Errorf("server returned error: %d (failed to read response body: %w)", resp.StatusCode, readErr)
		}
		return fmt.Errorf("server returned error: %d, body: %s", resp.StatusCode, string(bodyBytes))
	}
	return fmt.Errorf("upload failed after %d retries", u.MaxRetries)
}

// CheckAuth verifies if the configured credentials are valid.
func (u *HTTPUploader) CheckAuth(ctx context.Context) error {
	// We use the inventory endpoint with an empty body.
	// If the token is valid, we expect a 400 Bad Request (missing fields) or 200 OK (if empty body is allowed).
	// If the token is invalid, we expect 401 Unauthorized.
	url := u.BaseURL + endpointInventory
	emptyBody := []byte("{}")

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(emptyBody))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if u.Token != "" {
		req.Header.Set("Authorization", "Bearer "+u.Token)
	}

	resp, err := u.Client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusUnauthorized {
		return fmt.Errorf("invalid API key (401 Unauthorized)")
	}

	// Any other status code (even 400 or 404 or 500) implies that the auth middleware passed.
	// We only care about 401.
	return nil
}

func (u *HTTPUploader) backoff(ctx context.Context, attempt int) {
	wait := time.Duration(math.Pow(2, float64(attempt))) * u.RetryWaitMin
	if wait > u.RetryWaitMax {
		wait = u.RetryWaitMax
	}
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}
