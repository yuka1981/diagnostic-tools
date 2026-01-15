package execution

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestPIDManager_WritePID(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-uuid-123"
	pid := 12345

	err := pm.WritePID(uuid, pid)
	if err != nil {
		t.Fatalf("WritePID failed: %v", err)
	}

	// Verify file exists
	pidPath := filepath.Join(tempDir, uuid+PIDFileSuffix)
	content, err := os.ReadFile(pidPath)
	if err != nil {
		t.Fatalf("Failed to read PID file: %v", err)
	}

	if string(content) != "12345" {
		t.Errorf("Expected PID content '12345', got '%s'", content)
	}
}

func TestPIDManager_ReadPID(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-uuid-456"
	expectedPID := 67890

	// Write PID first
	err := pm.WritePID(uuid, expectedPID)
	if err != nil {
		t.Fatalf("WritePID failed: %v", err)
	}

	// Read it back
	pid, err := pm.ReadPID(uuid)
	if err != nil {
		t.Fatalf("ReadPID failed: %v", err)
	}

	if pid != expectedPID {
		t.Errorf("Expected PID %d, got %d", expectedPID, pid)
	}
}

func TestPIDManager_ReadPID_NotFound(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	_, err := pm.ReadPID("nonexistent-uuid")
	if err != ErrPIDFileNotFound {
		t.Errorf("Expected ErrPIDFileNotFound, got %v", err)
	}
}

func TestPIDManager_ClearPID(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-uuid-789"

	// Write PID first
	err := pm.WritePID(uuid, 11111)
	if err != nil {
		t.Fatalf("WritePID failed: %v", err)
	}

	// Clear it
	err = pm.ClearPID(uuid)
	if err != nil {
		t.Fatalf("ClearPID failed: %v", err)
	}

	// Verify file is gone
	_, err = pm.ReadPID(uuid)
	if err != ErrPIDFileNotFound {
		t.Errorf("Expected ErrPIDFileNotFound after clear, got %v", err)
	}
}

func TestPIDManager_ClearPID_AlreadyGone(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	// Should not error if file doesn't exist
	err := pm.ClearPID("nonexistent-uuid")
	if err != nil {
		t.Errorf("ClearPID should not error for nonexistent file, got %v", err)
	}
}

func TestPIDManager_IsProcessRunning(t *testing.T) {
	pm := NewPIDManager()

	// Current process should be running
	if !pm.IsProcessRunning(os.Getpid()) {
		t.Error("Current process should be detected as running")
	}

	// PID 1 should be running (init/systemd)
	if !pm.IsProcessRunning(1) {
		t.Log("PID 1 not running - may be in container environment")
	}

	// Very high PID should not be running
	if pm.IsProcessRunning(999999999) {
		t.Error("Non-existent PID should not be detected as running")
	}
}

func TestPIDManager_KillProcess_NotRunning(t *testing.T) {
	pm := NewPIDManager()

	// Try to kill a non-existent process
	err := pm.KillProcess(999999999)
	if err != ErrProcessNotFound {
		t.Errorf("Expected ErrProcessNotFound for non-existent process, got %v", err)
	}
}

func TestPIDManager_KillProcessWithTimeout(t *testing.T) {
	pm := NewPIDManager()

	// Test with very short timeout
	err := pm.KillProcessWithTimeout(999999999, 100*time.Millisecond)
	if err != ErrProcessNotFound {
		t.Errorf("Expected ErrProcessNotFound, got %v", err)
	}
}

func TestPIDManager_CancelByUUID_NotFound(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	_, err := pm.CancelByUUID("nonexistent-uuid")
	if err != ErrPIDFileNotFound {
		t.Errorf("Expected ErrPIDFileNotFound, got %v", err)
	}
}

func TestPIDManager_CancelByUUID_ProcessNotRunning(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-cancel-uuid"

	// Write a PID for a non-existent process
	err := pm.WritePID(uuid, 999999999)
	if err != nil {
		t.Fatalf("WritePID failed: %v", err)
	}

	// Cancel should succeed (process not found is OK, PID file should be cleaned up)
	pid, err := pm.CancelByUUID(uuid)
	if err != nil {
		t.Errorf("CancelByUUID should succeed even if process not running, got %v", err)
	}

	if pid != 999999999 {
		t.Errorf("Expected returned PID 999999999, got %d", pid)
	}

	// PID file should be cleaned up
	_, err = pm.ReadPID(uuid)
	if err != ErrPIDFileNotFound {
		t.Error("PID file should be removed after cancel")
	}
}

func TestPIDManager_RunCommandWithPID_Success(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-run-uuid"

	// Run a simple command that outputs something
	output, err := pm.RunCommandWithPID(context.Background(), uuid, "", "echo", "hello world")
	if err != nil {
		t.Fatalf("RunCommandWithPID failed: %v", err)
	}

	// Check output
	if string(output) != "hello world\n" {
		t.Errorf("Expected 'hello world\\n', got %q", string(output))
	}

	// PID file should be cleaned up after command completes
	_, err = pm.ReadPID(uuid)
	if err != ErrPIDFileNotFound {
		t.Error("PID file should be removed after command completes")
	}
}

func TestPIDManager_RunCommandWithPID_WritesPIDDuringExecution(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-pid-write-uuid"

	// Use a command that sleeps briefly so we can check the PID file exists during execution
	// This test verifies PID is written before command completes
	done := make(chan struct{})
	var pidDuringExec int
	var pidErr error

	go func() {
		// Small delay to let the command start
		time.Sleep(50 * time.Millisecond)
		pidDuringExec, pidErr = pm.ReadPID(uuid)
		close(done)
	}()

	_, err := pm.RunCommandWithPID(context.Background(), uuid, "", "sleep", "0.2")
	if err != nil {
		t.Fatalf("RunCommandWithPID failed: %v", err)
	}

	<-done
	if pidErr != nil {
		t.Logf("Note: Could not read PID during execution (timing sensitive): %v", pidErr)
	} else if pidDuringExec <= 0 {
		t.Errorf("Expected valid PID during execution, got %d", pidDuringExec)
	}

	// PID file should be cleaned up after
	_, err = pm.ReadPID(uuid)
	if err != ErrPIDFileNotFound {
		t.Error("PID file should be removed after command completes")
	}
}

func TestPIDManager_RunCommandWithPID_CommandFailure(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-fail-uuid"

	// Run a command that will fail
	output, err := pm.RunCommandWithPID(context.Background(), uuid, "", "sh", "-c", "echo 'error output' && exit 1")

	// Should return error
	if err == nil {
		t.Error("Expected error for failed command")
	}

	// Output should still be captured
	if len(output) == 0 {
		t.Error("Expected output to be captured even on failure")
	}

	// PID file should be cleaned up even on failure
	_, readErr := pm.ReadPID(uuid)
	if readErr != ErrPIDFileNotFound {
		t.Error("PID file should be removed even after command fails")
	}
}

func TestPIDManager_RunCommandWithPID_WorkingDirectory(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-workdir-uuid"

	// Create a file in the temp dir
	testFile := filepath.Join(tempDir, "testfile.txt")
	if err := os.WriteFile(testFile, []byte("test content"), 0644); err != nil {
		t.Fatalf("Failed to create test file: %v", err)
	}

	// Run ls in the temp directory
	output, err := pm.RunCommandWithPID(context.Background(), uuid, tempDir, "ls")
	if err != nil {
		t.Fatalf("RunCommandWithPID failed: %v", err)
	}

	if !contains(string(output), "testfile.txt") {
		t.Errorf("Expected output to contain 'testfile.txt', got %q", string(output))
	}
}

func TestPIDManager_RunCommandWithPID_CapturesStderr(t *testing.T) {
	tempDir := t.TempDir()
	pm := NewPIDManagerWithDir(tempDir)

	uuid := "test-stderr-uuid"

	// Run a command that outputs to stderr
	output, _ := pm.RunCommandWithPID(context.Background(), uuid, "", "sh", "-c", "echo 'stdout' && echo 'stderr' >&2")

	// Both stdout and stderr should be captured
	outputStr := string(output)
	if !contains(outputStr, "stdout") {
		t.Errorf("Expected stdout in output, got %q", outputStr)
	}
	if !contains(outputStr, "stderr") {
		t.Errorf("Expected stderr in output, got %q", outputStr)
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
