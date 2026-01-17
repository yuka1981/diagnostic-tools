package heartbeat

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

// Payload represents the heartbeat data sent to the server.
type Payload struct {
	UUID      string `json:"uuid"`
	Timestamp string `json:"timestamp"`
	Version   string `json:"version"`
}

// Service handles sending heartbeat requests to the server.
type Service struct {
	baseURL  string
	token    string
	nodeID   string
	version  string
	hostname string
	client   *http.Client
}

// New creates a new heartbeat service.
func New(baseURL, token, nodeID, version string) *Service {
	hostname, _ := os.Hostname()
	return &Service{
		baseURL:  baseURL,
		token:    token,
		nodeID:   nodeID,
		version:  version,
		hostname: hostname,
		client:   &http.Client{Timeout: 30 * time.Second},
	}
}

// Send sends a heartbeat to the server.
func (s *Service) Send(ctx context.Context) error {
	endpoint := fmt.Sprintf("%s/api/v1/nodes/%s/heartbeat", s.baseURL, s.nodeID)

	payload := Payload{
		UUID:      s.nodeID,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Version:   s.version,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to marshal heartbeat payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewBuffer(body))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if s.token != "" {
		req.Header.Set("Authorization", "Bearer "+s.token)
	}
	req.Header.Set("X-Node-ID", s.nodeID)
	if s.hostname != "" {
		req.Header.Set("X-Hostname", s.hostname)
	}
	if s.version != "" {
		req.Header.Set("X-Agent-Version", s.version)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send heartbeat: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}

	respBody, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("heartbeat failed with status %d: %s", resp.StatusCode, string(respBody))
}
