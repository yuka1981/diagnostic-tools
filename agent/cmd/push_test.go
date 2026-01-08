package cmd

import (
	"bytes"
	"context"
	"errors"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

type mockPushCollector struct {
	err error
}

func (m *mockPushCollector) Collect(ctx context.Context) (*model.NodeState, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &model.NodeState{Host: &model.HostInfo{Hostname: "test-host"}}, nil
}

type mockPushUploader struct {
	uploadErr error
}

func (m *mockPushUploader) Upload(ctx context.Context, payload interface{}) error {
	return m.uploadErr
}
func (m *mockPushUploader) CheckAuth(ctx context.Context) error {
	return nil
}

func TestPushCmd(t *testing.T) {
	t.Run("Success", func(t *testing.T) {
		collector := &mockPushCollector{}
		upFactory := func(url, token string) ports.Uploader {
			return &mockPushUploader{}
		}

		pushCmd := NewPushCmd(collector, upFactory)
		buf := new(bytes.Buffer)
		pushCmd.SetOut(buf)
		pushCmd.Flags().Set("token", "test-token")

		if err := pushCmd.RunE(pushCmd, nil); err != nil {
			t.Fatalf("RunE failed: %v", err)
		}

		if !bytes.Contains(buf.Bytes(), []byte("Inventory pushed successfully")) {
			t.Errorf("expected success message, got %q", buf.String())
		}
	})

	t.Run("Success_NoNodeID", func(t *testing.T) {
		collector := &mockPushCollector{}
		upFactory := func(url, token string) ports.Uploader {
			return &mockPushUploader{}
		}

		pushCmd := NewPushCmd(collector, upFactory)
		buf := new(bytes.Buffer)
		pushCmd.SetOut(buf)
		pushCmd.Flags().Set("token", "test-token")
		// configDir points to non-existent so GetOrGenerateNodeID returns error or empty
		pushCmd.Flags().Set("config", "/non-existent-path-that-should-fail")

		if err := pushCmd.RunE(pushCmd, nil); err != nil {
			t.Fatalf("RunE failed: %v", err)
		}
	})

	t.Run("MissingToken", func(t *testing.T) {
		pushCmd := NewPushCmd(nil, nil)
		pushCmd.Flags().Set("token", "")
		if err := pushCmd.RunE(pushCmd, nil); err == nil {
			t.Error("expected error for missing token, got nil")
		}
	})

	t.Run("CollectError", func(t *testing.T) {
		collector := &mockPushCollector{err: errors.New("collect failed")}
		pushCmd := NewPushCmd(collector, nil)
		pushCmd.Flags().Set("token", "test-token")
		if err := pushCmd.RunE(pushCmd, nil); err == nil {
			t.Error("expected error for collect failure, got nil")
		}
	})

	t.Run("UploadError", func(t *testing.T) {
		collector := &mockPushCollector{}
		upFactory := func(url, token string) ports.Uploader {
			return &mockPushUploader{uploadErr: errors.New("upload failed")}
		}
		pushCmd := NewPushCmd(collector, upFactory)
		pushCmd.Flags().Set("token", "test-token")
		if err := pushCmd.RunE(pushCmd, nil); err == nil {
			t.Error("expected error for upload failure, got nil")
		}
	})
}
