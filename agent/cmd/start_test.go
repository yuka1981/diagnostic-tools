package cmd

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

type mockResponder struct {
	sent []interface{}
}

func (m *mockResponder) Send(ctx context.Context, payload interface{}) error {
	m.sent = append(m.sent, payload)
	return nil
}

type mockResponderErr struct {
	err error
}

func (m *mockResponderErr) Send(ctx context.Context, payload interface{}) error {
	return m.err
}

type mockInventoryCollector struct {
	state *model.NodeState
	err   error
}

func (m *mockInventoryCollector) Collect(ctx context.Context) (*model.NodeState, error) {
	return m.state, m.err
}

func TestAgentHandler_HandleCommand(t *testing.T) {
	collector := &mockInventoryCollector{
		state: &model.NodeState{Host: &model.HostInfo{Hostname: "test-node"}},
	}
	handler := &agentHandler{collector: collector}
	responder := &mockResponder{}
	ctx := context.Background()

	t.Run("CollectInventory", func(t *testing.T) {
		payload := map[string]interface{}{"correlation_id": "123"}
		err := handler.HandleCommand(ctx, "collect_inventory", payload, responder)
		if err != nil {
			t.Fatalf("HandleCommand failed: %v", err)
		}

		if len(responder.sent) != 1 {
			t.Fatalf("expected 1 response, got %d", len(responder.sent))
		}

		resp := responder.sent[0].(map[string]interface{})
		if resp["status"] != "success" {
			t.Errorf("expected success, got %v", resp["status"])
		}
		if resp["correlation_id"] != "123" {
			t.Errorf("expected correlation_id 123, got %v", resp["correlation_id"])
		}
	})

	t.Run("CollectInventoryError", func(t *testing.T) {
		collectorErr := &mockInventoryCollector{err: errors.New("collect error")}
		handlerErr := &agentHandler{collector: collectorErr}
		responderErr := &mockResponder{}
		payload := map[string]interface{}{"correlation_id": "err-123"}

		err := handlerErr.HandleCommand(ctx, "collect_inventory", payload, responderErr)
		if err != nil {
			t.Fatalf("HandleCommand failed: %v", err)
		}

		resp := responderErr.sent[0].(map[string]interface{})
		if resp["status"] != "error" {
			t.Errorf("expected error status, got %v", resp["status"])
		}
		if resp["error"] != "collect error" {
			t.Errorf("expected collect error, got %v", resp["error"])
		}
	})

	t.Run("CollectInventoryResponderError", func(t *testing.T) {
		collectorRespErr := &mockInventoryCollector{
			state: &model.NodeState{},
		}
		handlerRespErr := &agentHandler{collector: collectorRespErr}
		responderRespErr := &mockResponderErr{err: errors.New("send failed")}

		err := handlerRespErr.HandleCommand(ctx, "collect_inventory", nil, responderRespErr)
		if err == nil {
			t.Error("expected error from responder.Send, got nil")
		}
	})

	t.Run("Ping", func(t *testing.T) {
		responderPing := &mockResponder{}
		err := handler.HandleCommand(ctx, "ping", nil, responderPing)
		if err != nil {
			t.Fatalf("HandleCommand failed: %v", err)
		}

		if len(responderPing.sent) != 1 {
			t.Fatal("expected 1 response")
		}
		resp := responderPing.sent[0].(map[string]string)
		if resp["status"] != "pong" {
			t.Errorf("expected pong, got %v", resp["status"])
		}
	})

	t.Run("Uninstall", func(t *testing.T) {
		responderUn := &mockResponder{}
		payload := map[string]interface{}{"correlation_id": "uninstall-123"}
		err := handler.HandleCommand(ctx, "uninstall", payload, responderUn)
		if err != nil {
			t.Fatalf("HandleCommand failed: %v", err)
		}

		if len(responderUn.sent) != 1 {
			t.Fatal("expected 1 response")
		}
		resp := responderUn.sent[0].(map[string]interface{})
		if resp["status"] != "success" {
			t.Errorf("expected success, got %v", resp["status"])
		}
		// Note: we don't wait for the goroutine because it would exit the test process
	})

	t.Run("UninstallResponderError", func(t *testing.T) {
		handlerUnErr := &agentHandler{}
		responderUnErr := &mockResponderErr{err: errors.New("send failed")}

		err := handlerUnErr.HandleCommand(ctx, "uninstall", nil, responderUnErr)
		// handleUninstall returns nil even if responder fails (it logs the error)
		if err != nil {
			t.Errorf("expected nil error, got %v", err)
		}
	})

	t.Run("Unknown", func(t *testing.T) {
		responderUnknown := &mockResponder{}
		err := handler.HandleCommand(ctx, "unknown", nil, responderUnknown)
		if err != nil {
			t.Fatalf("HandleCommand failed: %v", err)
		}
		if len(responderUnknown.sent) != 0 {
			t.Error("expected no response for unknown command")
		}
	})
}

func TestStartCmd(t *testing.T) {
	// Testing Start command is hard because it blocks.
	// We'll just test the flag setup and a quick run with canceled context.

	t.Run("Flags", func(t *testing.T) {
		if startCmd.Use != "start" {
			t.Errorf("expected start, got %s", startCmd.Use)
		}
	})

	t.Run("RunE_MissingToken", func(t *testing.T) {
		oldToken := os.Getenv("AGENT_TOKEN")
		os.Unsetenv("AGENT_TOKEN")
		defer os.Setenv("AGENT_TOKEN", oldToken)

		cmdStart := startCmd
		cmdStart.Flags().Set("token", "")
		err := cmdStart.RunE(cmdStart, nil)
		if err == nil {
			t.Error("expected error for missing token, got nil")
		}
	})

	t.Run("RunE_ContextCanceled", func(t *testing.T) {
		cmdStart := startCmd
		cmdStart.Flags().Set("token", "test-token")
		cmdStart.Flags().Set("server", "http://localhost:3000")
		cmdStart.Flags().Set("config", t.TempDir())

		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		cmdStart.SetContext(ctx)
		err := cmdStart.RunE(cmdStart, nil)
		// It should return when context is canceled
		_ = err
	})
}
