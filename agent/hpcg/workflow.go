package hpcg

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// ModuleLoader defines interface for loading environment modules.
type ModuleLoader interface {
	Load(ctx context.Context, modules []string) error
}

// WorkflowOrchestrator manages the HPCG benchmark workflow.
type WorkflowOrchestrator struct {
	Runner       ports.CommandRunner
	ModuleLoader ModuleLoader
	WorkDir      string
}

// RunParams defines parameters for the workflow.

type RunParams struct {
	RunID string

	BuildCmd string // e.g. "make"

	RunCmd string // e.g. "srun ./xhpcg" or "./xhpcg"

	Modules []string

	Config ConfigParams
}

// Run executes the HPCG workflow.

func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
	// Ensure workdir exists
	if err := os.MkdirAll(w.WorkDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create workdir: %w", err)
	}

	// 1. Environment Setup
	if w.ModuleLoader != nil && len(params.Modules) > 0 {
		if err := w.ModuleLoader.Load(ctx, params.Modules); err != nil {
			return nil, fmt.Errorf("failed to load modules: %w", err)
		}
	}

	// 2. Build
	if params.BuildCmd != "" {
		// Use "bash -c" to allow shell features in build command
		if _, err := w.Runner.Run(ctx, w.WorkDir, "bash", "-c", params.BuildCmd); err != nil {
			return nil, fmt.Errorf("build failed: %w", err)
		}
	}

	// 3. Config
	hpcgDat := GenerateConfig(params.Config)
	if err := os.WriteFile(filepath.Join(w.WorkDir, "hpcg.dat"), []byte(hpcgDat), 0600); err != nil {
		return nil, fmt.Errorf("failed to write hpcg.dat: %w", err)
	}

	// 4. Run
	start := time.Now()
	// Use "bash -c" to allow shell features in run command
	output, err := w.Runner.Run(ctx, w.WorkDir, "bash", "-c", params.RunCmd)
	end := time.Now()

	status := model.BenchmarkStatusPass
	if err != nil {
		// Execution failed (exit code != 0)
		status = model.BenchmarkStatusFail
	}

	// 5. Parse
	// We parse the output to get metrics and confirm status
	metrics, parsedStatus, parseErr := ParseHPCGLog(strings.NewReader(string(output)))

	if parseErr == nil {
		status = parsedStatus
	} else if status == model.BenchmarkStatusPass {
		// If execution was successful but parsing failed, it's an error (e.g. unknown output format)
		// But if execution failed, we stick to Fail.
		status = model.BenchmarkStatusError
	}

	result := &model.BenchmarkRun{
		RunID:     params.RunID,
		RecipeID:  "hpcg",
		StartTime: start,
		EndTime:   end,
		Status:    status,
	}

	if metrics != nil {
		metricsBytes, err := json.Marshal(metrics)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal hpcg metrics: %w", err)
		}
		result.Metrics = metricsBytes
	}

	return result, nil
}
