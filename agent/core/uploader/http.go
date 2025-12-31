package uploader

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

const (
	endpointInventory     = "/api/v1/inventory"
	endpointBenchmarkRuns = "/api/v1/benchmark_runs"
)

// HTTPUploader implements ports.Uploader using HTTP.
type HTTPUploader struct {
	Client       *http.Client
	BaseURL      string
	Token        string
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

		resp, err := u.Client.Do(req)
		if err != nil {
			if i == u.MaxRetries {
				return fmt.Errorf("failed to send request after %d retries: %w", u.MaxRetries, err)
			}
			u.backoff(ctx, i)
			continue
		}

		// Ensure body is closed
		resp.Body.Close()

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return nil
		}

		// Retry on 5xx and 429
		if resp.StatusCode >= 500 || resp.StatusCode == 429 {
			if i == u.MaxRetries {
				return fmt.Errorf("server returned error %d after %d retries", resp.StatusCode, u.MaxRetries)
			}
			u.backoff(ctx, i)
			continue
		}

		// Do not retry on other errors (e.g., 400, 401, 403, 404)
		return fmt.Errorf("server returned error: %d", resp.StatusCode)
	}
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
