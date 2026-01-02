package infrastructure

import (
	"context"
	"fmt"
	"os"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// RealModuleLoader implements hpcg.ModuleLoader using modulecmd.
type RealModuleLoader struct {
	Runner ports.CommandRunner
}

// NewRealModuleLoader creates a new module loader.
func NewRealModuleLoader(runner ports.CommandRunner) *RealModuleLoader {
	return &RealModuleLoader{Runner: runner}
}

// Load loads the specified modules into the current process environment.
func (m *RealModuleLoader) Load(ctx context.Context, modules []string) error {
	if len(modules) == 0 {
		return nil
	}

	// Determine module command. LMOD_CMD is standard for Lmod.
	// Fallback to "modulecmd" if not set.
	cmd := os.Getenv("LMOD_CMD")
	if cmd == "" {
		cmd = "modulecmd" // Try generic name (Tcl modules uses this too)
	}

	// Prepare arguments: bash load <modules...>
	args := append([]string{"bash", "load"}, modules...)

	outputBytes, err := m.Runner.Run(ctx, "", cmd, args...)
	if err != nil {
		return fmt.Errorf("failed to run module command: %w", err)
	}

	return m.parseAndApply(string(outputBytes))
}

// parseAndApply parses simple shell exports and applies them to os.Env.
// This is a heuristic parser and may not support complex shell features.
func (m *RealModuleLoader) parseAndApply(output string) error {
	lines := strings.Split(output, ";")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		if strings.HasPrefix(line, "export ") {
			// export KEY=VALUE
			kv := strings.TrimPrefix(line, "export ")
			parts := strings.SplitN(kv, "=", 2)
			if len(parts) == 2 {
				key := parts[0]
				val := parts[1]
				// Remove surrounding quotes if present (basic)
				if (strings.HasPrefix(val, "\"") && strings.HasSuffix(val, "\"")) ||
					(strings.HasPrefix(val, "'") && strings.HasSuffix(val, "'")) {
					val = val[1 : len(val)-1]
				}
				// Expand $PATH if needed? os.Setenv doesn't expand.
				// modulecmd usually outputs full paths like PATH=/new/path:/old/path
				// So usually we don't need to expand if modulecmd did its job.
				// But sometimes it outputs `PATH=/foo:$PATH`.
				// If it outputs $PATH, we need to expand it using current env.
				val = os.ExpandEnv(val)

				if err := os.Setenv(key, val); err != nil {
					return err
				}
			}
		} else if strings.HasPrefix(line, "unset ") {
			key := strings.TrimPrefix(line, "unset ")
			if err := os.Unsetenv(key); err != nil {
				return err
			}
		}
	}
	return nil
}
