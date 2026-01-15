package uploader

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
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
	Hostname     string
	RetryWaitMin time.Duration
	RetryWaitMax time.Duration
	MaxRetries   int
	Verbose      bool
}

// NewHTTPUploader creates a new HTTP uploader.
func NewHTTPUploader(baseURL, token string) *HTTPUploader {
	hostname, _ := os.Hostname()
	return &HTTPUploader{
		BaseURL:      baseURL,
		Token:        token,
		Hostname:     hostname,
		Client:       &http.Client{Timeout: 30 * time.Second},
		MaxRetries:   3,
		RetryWaitMin: 1 * time.Second,
		RetryWaitMax: 30 * time.Second,
		Verbose:      true, // Enable verbose logging by default for debugging
	}
}

// SetVerbose enables or disables verbose logging.
func (u *HTTPUploader) SetVerbose(verbose bool) {
	u.Verbose = verbose
}

func (u *HTTPUploader) logf(format string, args ...interface{}) {
	if u.Verbose {
		fmt.Fprintf(os.Stderr, "[uploader] "+format+"\n", args...)
	}
}

// SetNodeID sets the unique identifier for the host.
func (u *HTTPUploader) SetNodeID(id string) {
	u.NodeID = id
}

// Upload sends the given payload to the configured endpoint.
func (u *HTTPUploader) Upload(ctx context.Context, payload interface{}) error {
	endpoint, err := u.determineEndpoint(payload)
	if err != nil {
		return err
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal payload: %w", err)
	}

	url := u.BaseURL + endpoint

	// Log upload details
	u.logf("Uploading to: %s", url)
	u.logf("Node ID: %s", u.NodeID)
	if br, ok := payload.(*model.BenchmarkRun); ok {
		u.logf("Benchmark run_id: %s, status: %s", br.RunID, br.Status)
	}

	err = u.doRequestWithRetry(ctx, url, body)
	if err != nil {
		u.logf("Upload failed: %v", err)
		// Log truncated request body for debugging
		bodyStr := string(body)
		if len(bodyStr) > 500 {
			bodyStr = bodyStr[:500] + "... (truncated)"
		}
		u.logf("Request body: %s", bodyStr)
	} else {
		u.logf("Upload successful")
	}
	return err
}

func (u *HTTPUploader) determineEndpoint(payload interface{}) (string, error) {
	switch payload.(type) {
	case *model.NodeState:
		return endpointInventory, nil
	case *model.BenchmarkRun:
		return endpointBenchmarkRuns, nil
	default:
		return "", fmt.Errorf("unsupported payload type: %T", payload)
	}
}

func (u *HTTPUploader) doRequestWithRetry(ctx context.Context, url string, body []byte) error {
	for i := 0; i <= u.MaxRetries; i++ {
		err := u.attemptRequest(ctx, url, body)
		if err == nil {
			return nil
		}

		if i == u.MaxRetries {
			return fmt.Errorf("failed to send request after %d retries: %w", u.MaxRetries, err)
		}

		if isRetryable(err) {
			u.backoff(ctx, i)
			continue
		}

		return err
	}
	return fmt.Errorf("upload failed after %d retries", u.MaxRetries)
}

func (u *HTTPUploader) attemptRequest(ctx context.Context, url string, body []byte) error {
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err) // Non-retryable
	}

	req.Header.Set("Content-Type", "application/json")
	if u.Token != "" {
		req.Header.Set("Authorization", "Bearer "+u.Token)
	}
	if u.NodeID != "" {
		req.Header.Set("X-Node-ID", u.NodeID)
	}
	if u.Hostname != "" {
		req.Header.Set("X-Hostname", u.Hostname)
	}

	resp, err := u.Client.Do(req)
	if err != nil {
		return &retryableError{err} // Network errors are retryable
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}

	if resp.StatusCode >= 500 || resp.StatusCode == http.StatusTooManyRequests {
		return &retryableError{fmt.Errorf("server returned error %d", resp.StatusCode)}
	}

	bodyBytes, readErr := io.ReadAll(resp.Body)
	if readErr != nil {
		return fmt.Errorf("server returned error: %d (failed to read response body: %w)", resp.StatusCode, readErr)
	}
	return fmt.Errorf("server returned error: %d, body: %s", resp.StatusCode, string(bodyBytes))
}

type retryableError struct {
	error
}

func isRetryable(err error) bool {
	_, ok := err.(*retryableError)
	return ok
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
