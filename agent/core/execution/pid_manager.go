// Package execution provides process execution and lifecycle management.
package execution

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

const (
	// DefaultPIDDir is the default directory for PID files.
	// Uses /tmp which is writable by all users. PID files are transient
	// and should be cleared on reboot anyway.
	DefaultPIDDir = "/tmp/diagnostic-agent"
	// PIDFileSuffix is the suffix for PID files.
	PIDFileSuffix = ".pid"
	// DefaultKillTimeout is the time to wait after SIGTERM before sending SIGKILL.
	DefaultKillTimeout = 5 * time.Second
	// PIDDirEnvVar is the environment variable to override the PID directory.
	PIDDirEnvVar = "DIAGNOSTIC_AGENT_PID_DIR"
)

// ErrPIDFileNotFound indicates the PID file does not exist.
var ErrPIDFileNotFound = errors.New("pid file not found")

// ErrProcessNotFound indicates the process is not running.
var ErrProcessNotFound = errors.New("process not found")

// PIDManager handles PID file lifecycle for benchmark processes.
type PIDManager struct {
	pidDir string
}

// NewPIDManager creates a new PID manager.
// Uses DIAGNOSTIC_AGENT_PID_DIR env var if set, otherwise defaults to /tmp/diagnostic-agent.
func NewPIDManager() *PIDManager {
	pidDir := os.Getenv(PIDDirEnvVar)
	if pidDir == "" {
		pidDir = DefaultPIDDir
	}
	return &PIDManager{
		pidDir: pidDir,
	}
}

// NewPIDManagerWithDir creates a new PID manager with a custom directory.
func NewPIDManagerWithDir(dir string) *PIDManager {
	return &PIDManager{
		pidDir: dir,
	}
}

// pidFilePath returns the full path to a PID file for a given UUID.
func (m *PIDManager) pidFilePath(uuid string) string {
	return filepath.Join(m.pidDir, uuid+PIDFileSuffix)
}

// EnsureDir creates the PID directory if it doesn't exist.
func (m *PIDManager) EnsureDir() error {
	return os.MkdirAll(m.pidDir, 0755)
}

// WritePID writes a PID to a file identified by UUID.
func (m *PIDManager) WritePID(uuid string, pid int) error {
	if err := m.EnsureDir(); err != nil {
		return fmt.Errorf("failed to create pid directory: %w", err)
	}

	pidPath := m.pidFilePath(uuid)
	content := strconv.Itoa(pid)

	if err := os.WriteFile(pidPath, []byte(content), 0600); err != nil {
		return fmt.Errorf("failed to write pid file: %w", err)
	}

	return nil
}

// ReadPID reads a PID from a file identified by UUID.
func (m *PIDManager) ReadPID(uuid string) (int, error) {
	pidPath := m.pidFilePath(uuid)

	content, err := os.ReadFile(pidPath)
	if err != nil {
		if os.IsNotExist(err) {
			return 0, ErrPIDFileNotFound
		}
		return 0, fmt.Errorf("failed to read pid file: %w", err)
	}

	pid, err := strconv.Atoi(string(content))
	if err != nil {
		return 0, fmt.Errorf("invalid pid in file: %w", err)
	}

	return pid, nil
}

// ClearPID removes the PID file for a given UUID.
func (m *PIDManager) ClearPID(uuid string) error {
	pidPath := m.pidFilePath(uuid)

	if err := os.Remove(pidPath); err != nil {
		if os.IsNotExist(err) {
			return nil // Already gone, that's fine
		}
		return fmt.Errorf("failed to remove pid file: %w", err)
	}

	return nil
}

// IsProcessRunning checks if a process with the given PID is running.
func (m *PIDManager) IsProcessRunning(pid int) bool {
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}

	// On Unix, FindProcess always succeeds. We need to send signal 0 to check.
	err = process.Signal(syscall.Signal(0))
	return err == nil
}

// KillProcess terminates a process gracefully (SIGTERM), then forcefully (SIGKILL) after timeout.
// Returns nil if the process was successfully terminated or was already not running.
func (m *PIDManager) KillProcess(pid int) error {
	return m.KillProcessWithTimeout(pid, DefaultKillTimeout)
}

// KillProcessWithTimeout terminates a process with a custom timeout.
func (m *PIDManager) KillProcessWithTimeout(pid int, timeout time.Duration) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return ErrProcessNotFound
	}

	// Check if process is actually running
	if err := process.Signal(syscall.Signal(0)); err != nil {
		return ErrProcessNotFound
	}

	// Send SIGTERM for graceful shutdown
	if termErr := process.Signal(syscall.SIGTERM); termErr != nil {
		// Process might have just exited
		if checkErr := process.Signal(syscall.Signal(0)); checkErr != nil {
			return nil // Process is gone
		}
		return fmt.Errorf("failed to send SIGTERM: %w", termErr)
	}

	// Wait for process to exit gracefully
	deadline := time.Now().Add(timeout)
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for time.Now().Before(deadline) {
		<-ticker.C
		if err := process.Signal(syscall.Signal(0)); err != nil {
			return nil // Process exited gracefully
		}
	}

	// Process didn't exit, send SIGKILL
	if killErr := process.Signal(syscall.SIGKILL); killErr != nil {
		// Check if process is already gone
		if checkErr := process.Signal(syscall.Signal(0)); checkErr != nil {
			return nil // Process is gone
		}
		return fmt.Errorf("failed to send SIGKILL: %w", killErr)
	}

	// Wait a bit more for SIGKILL to take effect
	time.Sleep(500 * time.Millisecond)

	// Final check
	if err := process.Signal(syscall.Signal(0)); err != nil {
		return nil // Process is gone
	}

	return fmt.Errorf("process %d did not terminate after SIGKILL", pid)
}

// CancelByUUID finds and kills a process by its UUID, then cleans up the PID file.
// Returns the PID that was killed, or an error.
func (m *PIDManager) CancelByUUID(uuid string) (int, error) {
	pid, err := m.ReadPID(uuid)
	if err != nil {
		return 0, err
	}

	// Try to kill the process
	killErr := m.KillProcess(pid)

	// Always try to clean up the PID file
	clearErr := m.ClearPID(uuid)

	// Return kill error if any (but still cleaned up)
	if killErr != nil && !errors.Is(killErr, ErrProcessNotFound) {
		return pid, killErr
	}

	if clearErr != nil {
		return pid, clearErr
	}

	return pid, nil
}

// RunCommandWithPID executes a command while tracking its PID.
// The PID is written immediately when the process starts and cleaned up when done.
// This allows the process to be canceled via CancelByUUID.
func (m *PIDManager) RunCommandWithPID(ctx context.Context, uuid, dir, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if dir != "" {
		cmd.Dir = dir
	}

	// Capture stdout and stderr together
	var combinedOutput bytes.Buffer
	cmd.Stdout = &combinedOutput
	cmd.Stderr = &combinedOutput

	// Start the command (non-blocking)
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("failed to start command: %w", err)
	}

	// Write PID immediately
	pid := cmd.Process.Pid
	if err := m.WritePID(uuid, pid); err != nil {
		// Kill the process if we can't track it
		_ = cmd.Process.Kill()
		return nil, fmt.Errorf("failed to write PID file: %w", err)
	}

	// Ensure PID cleanup on exit
	defer func() { _ = m.ClearPID(uuid) }()

	// Wait for command to complete
	err := cmd.Wait()
	output := combinedOutput.Bytes()

	return output, err
}
