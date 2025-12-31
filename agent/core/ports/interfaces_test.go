package ports

import (
	"context"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// Mock implementations for testing interface compliance

type mockInventoryCollector struct {
	collectFunc func(ctx context.Context) (*model.NodeState, error)
}

func (m *mockInventoryCollector) Collect(ctx context.Context) (*model.NodeState, error) {
	if m.collectFunc != nil {
		return m.collectFunc(ctx)
	}
	return &model.NodeState{}, nil
}

type mockUploader struct {
	uploadFunc func(ctx context.Context, payload interface{}) error
}

func (m *mockUploader) Upload(ctx context.Context, payload interface{}) error {
	if m.uploadFunc != nil {
		return m.uploadFunc(ctx, payload)
	}
	return nil
}

type mockCommandRunner struct {
	runFunc func(ctx context.Context, name string, args ...string) ([]byte, error)
}

func (m *mockCommandRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	if m.runFunc != nil {
		return m.runFunc(ctx, name, args...)
	}
	return []byte("mock output"), nil
}

// Test that mock implementations satisfy the interfaces
func TestInterfaceCompliance(t *testing.T) {
	t.Run("InventoryCollector", func(t *testing.T) {
		var _ InventoryCollector = &mockInventoryCollector{}
	})

	t.Run("Uploader", func(t *testing.T) {
		var _ Uploader = &mockUploader{}
	})

	t.Run("CommandRunner", func(t *testing.T) {
		var _ CommandRunner = &mockCommandRunner{}
	})
}

func TestMockInventoryCollector(t *testing.T) {
	ctx := context.Background()

	t.Run("DefaultBehavior", func(t *testing.T) {
		mock := &mockInventoryCollector{}
		state, err := mock.Collect(ctx)
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if state == nil {
			t.Error("expected non-nil state")
		}
	})

	t.Run("CustomBehavior", func(t *testing.T) {
		expectedState := &model.NodeState{
			Host: model.HostInfo{
				Hostname: "test-host",
			},
		}
		mock := &mockInventoryCollector{
			collectFunc: func(ctx context.Context) (*model.NodeState, error) {
				return expectedState, nil
			},
		}
		state, err := mock.Collect(ctx)
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if state.Host.Hostname != "test-host" {
			t.Errorf("expected hostname 'test-host', got %q", state.Host.Hostname)
		}
	})
}

func TestMockUploader(t *testing.T) {
	ctx := context.Background()

	t.Run("DefaultBehavior", func(t *testing.T) {
		mock := &mockUploader{}
		err := mock.Upload(ctx, &model.NodeState{})
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
	})

	t.Run("CustomBehavior", func(t *testing.T) {
		called := false
		mock := &mockUploader{
			uploadFunc: func(ctx context.Context, payload interface{}) error {
				called = true
				return nil
			},
		}
		err := mock.Upload(ctx, &model.NodeState{})
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if !called {
			t.Error("expected uploadFunc to be called")
		}
	})
}

func TestMockCommandRunner(t *testing.T) {
	ctx := context.Background()

	t.Run("DefaultBehavior", func(t *testing.T) {
		mock := &mockCommandRunner{}
		output, err := mock.Run(ctx, "echo", "test")
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if len(output) == 0 {
			t.Error("expected non-empty output")
		}
	})

	t.Run("CustomBehavior", func(t *testing.T) {
		expectedOutput := []byte("custom output")
		mock := &mockCommandRunner{
			runFunc: func(ctx context.Context, name string, args ...string) ([]byte, error) {
				if name != "test-cmd" {
					t.Errorf("expected command 'test-cmd', got %q", name)
				}
				return expectedOutput, nil
			},
		}
		output, err := mock.Run(ctx, "test-cmd", "arg1", "arg2")
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if string(output) != string(expectedOutput) {
			t.Errorf("expected output %q, got %q", expectedOutput, output)
		}
	})
}

