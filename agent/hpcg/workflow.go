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
	LogPath  string // Optional: custom path for the log file
	LogDir   string // Optional: directory to store logs if LogPath is not set
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
	targetLogPath := w.handleLogStorage(params, start)

	metrics, finalStatus := w.parseResults(output, start, execStatus, targetLogPath)

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

func (w *WorkflowOrchestrator) handleLogStorage(params *RunParams, startTime time.Time) string {
	var targetLogPath string
	if params.LogPath != "" {
		targetLogPath = params.LogPath
	} else if params.LogDir != "" {
		// Ensure log dir exists
		if err := os.MkdirAll(params.LogDir, 0755); err != nil {
			fmt.Fprintf(os.Stderr, "warning: failed to create log dir %s: %v\n", params.LogDir, err)
		} else {
			// Find latest log to get the name
			if latestLog, err := w.findLatestLog(startTime); err == nil {
				targetLogPath = filepath.Join(params.LogDir, filepath.Base(latestLog))
			}
		}
	}

	if targetLogPath != "" {
		if latestLog, err := w.findLatestLog(startTime); err == nil {
			// Ensure destination directory exists (for LogPath case)
			if err := os.MkdirAll(filepath.Dir(targetLogPath), 0755); err != nil {
				fmt.Fprintf(os.Stderr, "warning: failed to create directory for %s: %v\n", targetLogPath, err)
			} else {
				// If target is same as source, skip
				absSource, _ := filepath.Abs(latestLog)
				absTarget, _ := filepath.Abs(targetLogPath)
				if absSource != "" && absTarget != "" && absTarget != absSource {
					if err := os.Rename(latestLog, targetLogPath); err != nil {
						fmt.Fprintf(os.Stderr, "warning: failed to move log file to %s: %v\n", targetLogPath, err)
					}
				}
			}
		}
	}
	return targetLogPath
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
	customLogPath string,
) (*model.HPCGMetrics, model.BenchmarkStatus) {
	// First try to parse from stdout
	metrics, parsedStatus, parseErr := ParseHPCGLog(strings.NewReader(string(output)))

	// If stdout parsing failed or produced no metrics, look for generated log file
	if parseErr != nil || metrics.GFLOPS == 0 {
		var logToRead string
		if customLogPath != "" {
			// If custom log path provided, check if it was actually created/moved
			if _, err := os.Stat(customLogPath); err == nil {
				logToRead = customLogPath
			}
		}

		// Fallback to searching if custom path not found or not provided
		if logToRead == "" {
			if latestLog, err := w.findLatestLog(startTime); err == nil {
				logToRead = latestLog
			}
		}

		if logToRead != "" {
			if m, s, e := ParseHPCGLogFile(logToRead); e == nil {
				metrics = m
				parsedStatus = s
				parseErr = nil
			} else {
				// record error for easier debugging
				fmt.Fprintf(os.Stderr, "failed to parse log file %s: %v\n", logToRead, e)
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

	// Add 1 second grace period for start time to account for filesystem precision
	graceStartTime := startTime.Add(-1 * time.Second)

	for _, file := range files {
		if file.IsDir() || !strings.HasPrefix(file.Name(), "HPCG-Benchmark_") || !strings.HasSuffix(file.Name(), ".txt") {
			continue
		}

		info, err := file.Info()
		if err != nil {
			continue
		}

		if !info.ModTime().Before(graceStartTime) && !info.ModTime().Before(latestTime) {
			latestTime = info.ModTime()
			latestLog = filepath.Join(w.WorkDir, file.Name())
		}
	}

	if latestLog == "" {
		return "", fmt.Errorf("no log file found in %s", w.WorkDir)
	}
	return latestLog, nil
}
