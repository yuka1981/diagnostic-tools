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
	RunID    string
	BuildCmd string // e.g. "make"
	RunCmd   string // e.g. "srun ./xhpcg" or "./xhpcg"
	Modules  []string
	Config   ConfigParams
}

// Run executes the HPCG workflow.
func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
	// Ensure workdir exists
	if err := os.MkdirAll(w.WorkDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create workdir: %w", err)
	}

	// 1. Environment Setup
	if err := w.setupEnvironment(ctx, params.Modules); err != nil {
		return nil, err
	}

	// 2. Build
	if err := w.build(ctx, params.BuildCmd); err != nil {
		return nil, err
	}

	// 3. Config
	if err := w.writeConfig(params.Config); err != nil {
		return nil, err
	}

	// 4. Run
	start := time.Now()
	output, execErr := w.Runner.Run(ctx, w.WorkDir, "bash", "-c", params.RunCmd)
	end := time.Now()

	execStatus := model.BenchmarkStatusPass
	if execErr != nil {
		execStatus = model.BenchmarkStatusFail
	}

	// 5. Parse
	metrics, finalStatus := w.parseResults(output, start, execStatus)

	result := &model.BenchmarkRun{
		RunID:     params.RunID,
		RecipeID:  "hpcg",
		StartTime: start,
		EndTime:   end,
		Status:    finalStatus,
	}

	if metrics != nil && metrics.GFLOPS > 0 {
		metricsBytes, err := json.Marshal(metrics)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal hpcg metrics: %w", err)
		}
		result.Metrics = metricsBytes
	}

	return result, nil
}

func (w *WorkflowOrchestrator) setupEnvironment(ctx context.Context, modules []string) error {
	if w.ModuleLoader != nil && len(modules) > 0 {
		if err := w.ModuleLoader.Load(ctx, modules); err != nil {
			return fmt.Errorf("failed to load modules: %w", err)
		}
	}
	return nil
}

func (w *WorkflowOrchestrator) build(ctx context.Context, buildCmd string) error {
	if buildCmd == "" {
		return nil
	}
	if output, err := w.Runner.Run(ctx, w.WorkDir, "bash", "-c", buildCmd); err != nil {
		return fmt.Errorf("build failed: %w\nOutput:\n%s", err, string(output))
	}
	return nil
}

func (w *WorkflowOrchestrator) writeConfig(params ConfigParams) error {
	hpcgDat := GenerateConfig(params)
	if err := os.WriteFile(filepath.Join(w.WorkDir, "hpcg.dat"), []byte(hpcgDat), 0600); err != nil {
		return fmt.Errorf("failed to write hpcg.dat: %w", err)
	}
	return nil
}

func (w *WorkflowOrchestrator) parseResults(
	output []byte,
	startTime time.Time,
	execStatus model.BenchmarkStatus,
) (*model.HPCGMetrics, model.BenchmarkStatus) {
	// First try to parse from stdout
	metrics, parsedStatus, parseErr := ParseHPCGLog(strings.NewReader(string(output)))

	// If stdout parsing failed or produced no metrics, look for generated log file
	if parseErr != nil || metrics.GFLOPS == 0 {
		if latestLog, err := w.findLatestLog(startTime); err == nil {
			if m, s, e := ParseHPCGLogFile(latestLog); e == nil {
				metrics = m
				parsedStatus = s
				parseErr = nil
			} else {
				// record error for easier debugging
				fmt.Fprintf(os.Stderr, "failed to parse log file %s: %v\n", latestLog, e)
			}
		}
	}

	finalStatus := execStatus
	if parseErr == nil {
		finalStatus = parsedStatus
	} else if execStatus == model.BenchmarkStatusPass {
		finalStatus = model.BenchmarkStatusError
	}

	return metrics, finalStatus
}

func (w *WorkflowOrchestrator) findLatestLog(startTime time.Time) (string, error) {
	files, err := os.ReadDir(w.WorkDir)
	if err != nil {
		return "", err
	}

	var latestLog string
	var latestTime time.Time

	for _, file := range files {
		if file.IsDir() || !strings.HasPrefix(file.Name(), "HPCG-Benchmark_") || !strings.HasSuffix(file.Name(), ".txt") {
			continue
		}

		info, err := file.Info()
		if err != nil {
			continue
		}

		if info.ModTime().After(startTime) && info.ModTime().After(latestTime) {
			latestTime = info.ModTime()
			latestLog = filepath.Join(w.WorkDir, file.Name())
		}
	}

	if latestLog == "" {
		return "", fmt.Errorf("no log file found")
	}
	return latestLog, nil
}
