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

	"nhooyr.io/websocket"        //nolint:staticcheck // legacy websocket library
	"nhooyr.io/websocket/wsjson" //nolint:staticcheck // legacy websocket library
)

const (
	commandMessage = "message"
)

type mockHandler struct {
	payloads []map[string]interface{}
	actions  []string
	mu       sync.Mutex
}

func (m *mockHandler) HandleCommand(ctx context.Context, action string, payload map[string]interface{}, responder Responder) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.actions = append(m.actions, action)
	m.payloads = append(m.payloads, payload)
	return nil
}

func TestClient_StartAndCommunication(t *testing.T) {
	handler := &mockHandler{}

	// Create a mock websocket server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil) //nolint:staticcheck // legacy websocket library
		if err != nil {
			return
		}
		defer conn.Close(websocket.StatusInternalError, "closed") //nolint:staticcheck // legacy websocket library

		// Read subscribe message
		var sub map[string]interface{}
		if err := wsjson.Read(r.Context(), conn, &sub); err != nil {
			return
		}

		// Send welcome and confirmation
		_ = wsjson.Write(r.Context(), conn, map[string]string{"type": "welcome"})
		_ = wsjson.Write(r.Context(), conn, map[string]string{"type": "confirm_subscription"})

		// Send a command
		cmd := map[string]interface{}{
			"message": map[string]interface{}{
				"action": "test_action",
				"data":   "test_data",
			},
		}
		_ = wsjson.Write(r.Context(), conn, cmd)

		// Wait for a response if needed or just stay open
		time.Sleep(100 * time.Millisecond)
	}))
	defer server.Close()

	// Convert http URL to ws URL
	url := strings.Replace(server.URL, "http", "ws", 1)
	client := NewClient(url, "test-token", "test-node", handler)

	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	// Start client in background
	go func() {
		_ = client.Start(ctx)
	}()

	// Wait for handler to be called
	time.Sleep(200 * time.Millisecond)

	handler.mu.Lock()
	if len(handler.actions) == 0 {
		t.Error("expected at least one command to be handled")
	} else if handler.actions[0] != "test_action" {
		t.Errorf("expected test_action, got %s", handler.actions[0])
	}
	handler.mu.Unlock()
}

func TestClient_Send(t *testing.T) {
	var receivedMsg map[string]interface{}
	wg := sync.WaitGroup{}
	wg.Add(1)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := websocket.Accept(w, r, nil) //nolint:staticcheck // legacy websocket library
		if err != nil {
			return
		}

		// Read message
		for {
			var msg map[string]interface{}
			err := wsjson.Read(r.Context(), conn, &msg)
			if err != nil {
				break
			}
			if msg["command"] == commandMessage {
				receivedMsg = msg
				wg.Done()
				break
			}
		}
		conn.Close(websocket.StatusNormalClosure, "") //nolint:staticcheck // legacy websocket library
	}))
	defer server.Close()

	url := strings.Replace(server.URL, "http", "ws", 1)
	client := NewClient(url, "token", "node", nil)

	ctx := context.Background()
	conn, resp, err := websocket.Dial(ctx, url+"/cable", nil) //nolint:staticcheck // legacy websocket library
	if err != nil {
		t.Fatalf("failed to dial: %v", err)
	}
	if resp != nil && resp.Body != nil {
		resp.Body.Close()
	}
	client.conn = conn

	payload := map[string]string{"result": "ok"}
	err = client.Send(ctx, payload)
	if err != nil {
		t.Fatalf("Send failed: %v", err)
	}

	wg.Wait()

	if receivedMsg["command"] != commandMessage {
		t.Errorf("expected command %s, got %v", commandMessage, receivedMsg["command"])
	}

	var data map[string]string
	err = json.Unmarshal([]byte(receivedMsg["data"].(string)), &data)
	if err != nil {
		t.Fatalf("failed to unmarshal data: %v", err)
	}
	if data["result"] != "ok" {
		t.Errorf("expected result ok, got %s", data["result"])
	}
}

func TestClient_Start_Error(t *testing.T) {
	// Provide an invalid URL to trigger dial error
	client := NewClient("ws://invalid-host", "token", "node", nil)

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	err := client.Start(ctx)
	// Should return nil when context is done
	if err != nil {
		t.Errorf("expected nil error on ctx done, got %v", err)
	}
}

func TestClient_Subscribe_Error(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, _ := websocket.Accept(w, r, nil) //nolint:staticcheck // legacy websocket library
		// Close immediately to trigger error on client side when writing subscription
		conn.Close(websocket.StatusNormalClosure, "") //nolint:staticcheck // legacy websocket library
	}))
	defer server.Close()

	url := strings.Replace(server.URL, "http", "ws", 1)
	client := NewClient(url, "token", "node", nil)

	err := client.connectAndListen(context.Background())
	if err == nil {
		t.Error("expected error from connectAndListen, got nil")
	}
}

func TestClient_HandleMessage_SpecialCases(t *testing.T) {
	client := &Client{}
	ctx := context.Background()

	t.Run("Ping", func(t *testing.T) {
		client.handleMessage(ctx, map[string]interface{}{"type": "ping"})
	})

	t.Run("Welcome", func(t *testing.T) {
		client.handleMessage(ctx, map[string]interface{}{"type": "welcome"})
	})

	t.Run("ConfirmSubscription", func(t *testing.T) {
		client.handleMessage(ctx, map[string]interface{}{"type": "confirm_subscription"})
	})
}

func TestClient_PrepareURL(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"http://localhost:3000", "ws://localhost:3000/cable"},
		{"https://example.com", "wss://example.com/cable"},
		{"localhost:3000", "ws://localhost:3000/cable"},
	}

	for _, tt := range tests {
		c := &Client{serverURL: tt.input}
		got := c.prepareURL()
		if got != tt.expected {
			t.Errorf("prepareURL(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}
