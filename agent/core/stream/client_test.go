package stream

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"nhooyr.io/websocket" //nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
)

// MockHandler implements CommandHandler for testing
type MockHandler struct {
	payloads []map[string]interface{}
	commands []string
	mu       sync.Mutex
}

func (m *MockHandler) HandleCommand(_ context.Context, action string, payload map[string]interface{}, _ Responder) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.commands = append(m.commands, action)
	m.payloads = append(m.payloads, payload)
	return nil
}

func (m *MockHandler) GetCommands() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]string{}, m.commands...)
}

// TestClient_HandleMessage_Ping tests that ping messages trigger pong responses
func TestClient_HandleMessage_Ping(t *testing.T) {
	// Create a mock WebSocket server that captures messages
	var receivedMessages []map[string]interface{}
	var mu sync.Mutex
	serverReady := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close(websocket.StatusNormalClosure, "") //nolint:staticcheck // Deprecated but required for Go 1.22 compatibility

		close(serverReady)

		// Read messages in a loop
		for {
			ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
			//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
			_, data, err := conn.Read(ctx)
			cancel()
			if err != nil {
				return
			}

			var msg map[string]interface{}
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}

			mu.Lock()
			receivedMessages = append(receivedMessages, msg)
			mu.Unlock()

			// After receiving subscribe, send a ping
			if msg["command"] == "subscribe" {
				pingMsg := map[string]interface{}{"type": "ping"}
				//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
				if err := conn.Write(r.Context(), websocket.MessageText, mustMarshal(pingMsg)); err != nil {
					return
				}
			}
		}
	}))
	defer server.Close()

	// Create client with mock handler
	wsURL := strings.Replace(server.URL, "http://", "ws://", 1)
	handler := &MockHandler{}
	client := NewClient(wsURL, "test-token", "test-node-id", handler)

	// Run client briefly
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// Start in goroutine since it blocks
	go func() {
		_ = client.Start(ctx)
	}()

	// Wait for server to be ready
	select {
	case <-serverReady:
	case <-time.After(1 * time.Second):
		t.Fatal("Server not ready in time")
	}

	// Wait for messages to be exchanged
	time.Sleep(500 * time.Millisecond)

	// Verify pong was sent
	mu.Lock()
	defer mu.Unlock()

	found := false
	for _, msg := range receivedMessages {
		if msg["type"] == "pong" {
			found = true
			break
		}
	}

	if !found {
		t.Errorf("Expected pong response to ping, but none received. Messages: %v", receivedMessages)
	}
}

// TestClient_HandleMessage_Welcome tests that welcome messages are handled without error
func TestClient_HandleMessage_Welcome(t *testing.T) {
	handler := &MockHandler{}
	client := &Client{handler: handler}

	// This should not panic or call the handler
	ctx := context.Background()
	client.handleMessage(ctx, map[string]interface{}{"type": "welcome"})

	commands := handler.GetCommands()
	if len(commands) > 0 {
		t.Errorf("Expected no commands to be handled for welcome message, got: %v", commands)
	}
}

// TestClient_HandleMessage_ConfirmSubscription tests subscription confirmation handling
func TestClient_HandleMessage_ConfirmSubscription(t *testing.T) {
	handler := &MockHandler{}
	client := &Client{handler: handler}

	ctx := context.Background()
	client.handleMessage(ctx, map[string]interface{}{"type": "confirm_subscription"})

	commands := handler.GetCommands()
	if len(commands) > 0 {
		t.Errorf("Expected no commands to be handled for confirm_subscription, got: %v", commands)
	}
}

// TestClient_HandleMessage_Command tests that channel messages are dispatched to handler
func TestClient_HandleMessage_Command(t *testing.T) {
	handler := &MockHandler{}
	client := &Client{handler: handler}

	ctx := context.Background()
	msg := map[string]interface{}{
		"message": map[string]interface{}{
			"action":         "test_action",
			"correlation_id": "123",
		},
	}

	client.handleMessage(ctx, msg)

	// Give goroutine time to execute
	time.Sleep(100 * time.Millisecond)

	commands := handler.GetCommands()
	if len(commands) != 1 {
		t.Fatalf("Expected 1 command, got %d", len(commands))
	}

	if commands[0] != "test_action" {
		t.Errorf("Expected action 'test_action', got '%s'", commands[0])
	}
}

// TestClient_SendHeartbeat tests that heartbeat messages are properly formatted
func TestClient_SendHeartbeat(t *testing.T) {
	var receivedData []byte
	var mu sync.Mutex

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
		conn, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close(websocket.StatusNormalClosure, "") //nolint:staticcheck // Deprecated but required for Go 1.22 compatibility

		// Read messages until timeout
		for {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
			_, data, err := conn.Read(ctx)
			cancel()
			if err != nil {
				return
			}

			mu.Lock()
			receivedData = data
			mu.Unlock()
		}
	}))
	defer server.Close()

	wsURL := strings.Replace(server.URL, "http://", "ws://", 1)
	client := NewClient(wsURL, "test-token", "test-node-id", nil)

	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	// Dial and set connection
	//nolint:staticcheck // Deprecated but required for Go 1.22 compatibility
	conn, resp, err := websocket.Dial(ctx, wsURL+"/cable", nil)
	if resp != nil && resp.Body != nil {
		resp.Body.Close()
	}
	if err != nil {
		t.Fatalf("Failed to dial: %v", err)
	}
	defer conn.Close(websocket.StatusNormalClosure, "") //nolint:staticcheck // Deprecated but required for Go 1.22 compatibility

	client.writeMu.Lock()
	client.conn = conn
	client.writeMu.Unlock()

	// Send heartbeat
	err = client.sendHeartbeat(context.Background())
	if err != nil {
		t.Fatalf("sendHeartbeat failed: %v", err)
	}

	// Wait for message to be received
	time.Sleep(200 * time.Millisecond)

	mu.Lock()
	defer mu.Unlock()

	if len(receivedData) == 0 {
		t.Fatal("No data received from heartbeat")
	}

	var msg map[string]interface{}
	if err := json.Unmarshal(receivedData, &msg); err != nil {
		t.Fatalf("Failed to unmarshal heartbeat: %v", err)
	}

	// Check it's an ActionCable message format
	if msg["command"] != "message" {
		t.Errorf("Expected command 'message', got '%v'", msg["command"])
	}

	// Check the data contains heartbeat action
	dataStr, ok := msg["data"].(string)
	if !ok {
		t.Fatal("Expected data to be a string")
	}

	var payload map[string]interface{}
	if err := json.Unmarshal([]byte(dataStr), &payload); err != nil {
		t.Fatalf("Failed to unmarshal payload: %v", err)
	}

	if payload["action"] != "heartbeat" {
		t.Errorf("Expected action 'heartbeat', got '%v'", payload["action"])
	}

	if payload["timestamp"] == nil {
		t.Error("Expected timestamp in heartbeat payload")
	}
}

// TestClient_HeartbeatLoop_Cancellation tests that heartbeat loop stops on context cancellation
func TestClient_HeartbeatLoop_Cancellation(t *testing.T) {
	client := &Client{}

	ctx, cancel := context.WithCancel(context.Background())

	done := make(chan struct{})
	go func() {
		client.heartbeatLoop(ctx)
		close(done)
	}()

	// Cancel immediately
	cancel()

	// Should exit quickly
	select {
	case <-done:
		// Success
	case <-time.After(1 * time.Second):
		t.Error("heartbeatLoop did not exit after context cancellation")
	}
}

// TestClient_RespondToPing_NoConnection tests pong handling when connection is nil
func TestClient_RespondToPing_NoConnection(t *testing.T) {
	client := &Client{} // No connection set

	// Should not panic
	client.respondToPing(context.Background())
}

// TestClient_PrepareURL tests URL preparation for various inputs
func TestClient_PrepareURL(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "http to ws",
			input:    "http://localhost:3000",
			expected: "ws://localhost:3000/cable",
		},
		{
			name:     "https to wss",
			input:    "https://example.com",
			expected: "wss://example.com/cable",
		},
		{
			name:     "simple hostname",
			input:    "localhost:3000",
			expected: "ws://localhost:3000/cable",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := &Client{serverURL: tt.input}
			result := client.prepareURL()
			if result != tt.expected {
				t.Errorf("prepareURL() = %q, want %q", result, tt.expected)
			}
		})
	}
}

// TestHeartbeatInterval tests that the heartbeat interval constant is set appropriately
func TestHeartbeatInterval(t *testing.T) {
	// Heartbeat should be less than the server's ONLINE_THRESHOLD (5 minutes)
	// to ensure the node stays online
	if HeartbeatInterval >= 5*time.Minute {
		t.Errorf("HeartbeatInterval (%v) should be less than 5 minutes", HeartbeatInterval)
	}

	// Heartbeat should be reasonable (not too frequent to avoid overhead)
	if HeartbeatInterval < 10*time.Second {
		t.Errorf("HeartbeatInterval (%v) should be at least 10 seconds", HeartbeatInterval)
	}
}

func mustMarshal(v interface{}) []byte {
	data, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return data
}
