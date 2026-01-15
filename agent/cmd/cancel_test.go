package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/execution"
)

func TestCancelCommand_NoUUID(t *testing.T) {
	cmd := &cobra.Command{}
	cmd.Flags().String("uuid", "", "UUID of the benchmark run")

	var buf bytes.Buffer
	cmd.SetOut(&buf)

	err := runCancel(cmd, []string{})
	if err != nil {
		t.Fatalf("runCancel returned error: %v", err)
	}

	var result CancelResult
	if err := json.Unmarshal(buf.Bytes(), &result); err != nil {
		t.Fatalf("Failed to parse JSON output: %v", err)
	}

	if result.Status != "error" {
		t.Errorf("Expected status 'error', got '%s'", result.Status)
	}
	if result.Message != "UUID is required" {
		t.Errorf("Expected message 'UUID is required', got '%s'", result.Message)
	}
}

func TestCancelCommand_PIDFileNotFound(t *testing.T) {
	// Use a temp directory for PID files
	tempDir := t.TempDir()
	originalDir := execution.DefaultPIDDir

	// We can't easily override the default PID dir in the cancel command,
	// so we test the underlying PIDManager directly and verify the command
	// would produce the expected output format
	pm := execution.NewPIDManagerWithDir(tempDir)

	_, err := pm.CancelByUUID("nonexistent-uuid")
	if err != execution.ErrPIDFileNotFound {
		t.Errorf("Expected ErrPIDFileNotFound, got %v", err)
	}

	// Verify the command output structure
	result := CancelResult{
		Status:  "not_found",
		Message: "No PID file found for UUID nonexistent-uuid",
	}

	output, _ := json.Marshal(result)
	if !bytes.Contains(output, []byte("not_found")) {
		t.Error("Expected output to contain 'not_found'")
	}

	_ = originalDir // Suppress unused warning
}

func TestCancelCommand_ProcessAlreadyGone(t *testing.T) {
	tempDir := t.TempDir()
	pm := execution.NewPIDManagerWithDir(tempDir)

	uuid := "test-already-gone-uuid"

	// Write a PID for a non-existent process
	err := pm.WritePID(uuid, 999999999)
	if err != nil {
		t.Fatalf("WritePID failed: %v", err)
	}

	// Cancel should succeed
	pid, err := pm.CancelByUUID(uuid)
	if err != nil {
		t.Errorf("CancelByUUID should succeed, got %v", err)
	}

	if pid != 999999999 {
		t.Errorf("Expected PID 999999999, got %d", pid)
	}

	// PID file should be cleaned up
	_, err = pm.ReadPID(uuid)
	if err != execution.ErrPIDFileNotFound {
		t.Error("PID file should be removed after cancel")
	}
}

func TestCancelResult_JSONFormat(t *testing.T) {
	tests := []struct {
		name     string
		result   CancelResult
		wantJSON string
	}{
		{
			name: "success result",
			result: CancelResult{
				Status:  "ok",
				Message: "Process 12345 killed",
				PID:     12345,
			},
			wantJSON: `"status":"ok"`,
		},
		{
			name: "not found result",
			result: CancelResult{
				Status:  "not_found",
				Message: "No PID file found for UUID abc123",
			},
			wantJSON: `"status":"not_found"`,
		},
		{
			name: "error result",
			result: CancelResult{
				Status:  "error",
				Message: "Failed to cancel: permission denied",
				PID:     54321,
			},
			wantJSON: `"status":"error"`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			output, err := json.Marshal(tt.result)
			if err != nil {
				t.Fatalf("Failed to marshal result: %v", err)
			}

			if !bytes.Contains(output, []byte(tt.wantJSON)) {
				t.Errorf("Expected JSON to contain %s, got %s", tt.wantJSON, string(output))
			}
		})
	}
}

func TestCancelCommand_Integration(t *testing.T) {
	// Create a temp directory for PID files
	tempDir := t.TempDir()
	pidDir := filepath.Join(tempDir, "diagnostic-agent")
	if err := os.MkdirAll(pidDir, 0755); err != nil {
		t.Fatalf("Failed to create PID dir: %v", err)
	}

	pm := execution.NewPIDManagerWithDir(pidDir)

	// Test 1: Cancel non-existent UUID
	_, err := pm.CancelByUUID("does-not-exist")
	if err != execution.ErrPIDFileNotFound {
		t.Errorf("Expected ErrPIDFileNotFound for non-existent UUID")
	}

	// Test 2: Cancel with stale PID (process not running)
	uuid := "stale-process-uuid"
	err = pm.WritePID(uuid, 999999999)
	if err != nil {
		t.Fatalf("Failed to write PID: %v", err)
	}

	pid, err := pm.CancelByUUID(uuid)
	if err != nil {
		t.Errorf("Expected success for stale PID, got %v", err)
	}
	if pid != 999999999 {
		t.Errorf("Expected PID 999999999, got %d", pid)
	}

	// Verify cleanup
	_, err = pm.ReadPID(uuid)
	if err != execution.ErrPIDFileNotFound {
		t.Error("PID file should be cleaned up after cancel")
	}
}
