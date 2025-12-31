package infrastructure

import (
	"context"
	"os/exec"
)

// RealCommandRunner implements ports.CommandRunner using os/exec.
type RealCommandRunner struct{}

// NewRealCommandRunner creates a new command runner.
func NewRealCommandRunner() *RealCommandRunner {
	return &RealCommandRunner{}
}

// Run executes a command.
func (r *RealCommandRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	return cmd.CombinedOutput() // CombinedOutput captures stderr too which is useful for debug, or just Output
}
