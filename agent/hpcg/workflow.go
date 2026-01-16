package hpcg

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// HPCGRepoURL is the official HPCG benchmark repository.
const HPCGRepoURL = "https://github.com/hpcg-benchmark/hpcg.git"

// ModuleLoader defines interface for loading environment modules.
type ModuleLoader interface {
	Load(ctx context.Context, modules []string) error
}

// PIDTracker provides PID-tracked command execution for cancellation support.
type PIDTracker interface {
	RunCommandWithPID(ctx context.Context, uuid, dir, name string, args ...string) ([]byte, error)
}

// WorkflowOrchestrator manages the HPCG benchmark workflow.
type WorkflowOrchestrator struct { //nolint:govet // fieldalignment: all fields are 16 bytes (string/interface)
	WorkDir      string
	Runner       ports.CommandRunner
	ModuleLoader ModuleLoader
	PIDTracker   PIDTracker // Optional: enables cancellation support when set
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

	// 0. Ensure HPCG source is available (auto-clone if needed)
	if err := w.ensureHPCGSource(ctx); err != nil {
		return nil, err
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

	// 4. Run (with PID tracking for cancellation support)
	start := time.Now()
	output, execErr := w.runBenchmark(ctx, params.RunID, params.RunCmd)
	end := time.Now()

	execStatus, execErrMsg := evaluateExecResult(execErr)

	// 5. Parse
	targetLogPath := w.handleLogStorage(params, start)

	metrics, finalStatus := w.parseResults(output, start, execStatus, targetLogPath)
	errorMessage := buildErrorMessage(finalStatus, execErrMsg)

	// 6. Capture log content for API reporting
	logContent := w.captureLogContent(output, targetLogPath, start)

	result := &model.BenchmarkRun{
		RunID:        params.RunID,
		RecipeID:     "hpcg",
		StartTime:    start,
		EndTime:      end,
		Status:       finalStatus,
		ErrorMessage: errorMessage,
		LogContent:   logContent,
	}

	// Collect artifacts
	w.collectArtifacts(result, targetLogPath)

	// Add metrics if available
	if metrics != nil && metrics.GFLOPS > 0 {
		metricsBytes, err := json.Marshal(metrics)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal hpcg metrics: %w", err)
		}
		result.Metrics = metricsBytes
	}

	return result, nil
}

// evaluateExecResult determines status and error message from execution error.
func evaluateExecResult(execErr error) (status model.BenchmarkStatus, errMsg string) {
	if execErr != nil {
		return model.BenchmarkStatusFail, fmt.Sprintf("Benchmark execution failed: %v", execErr)
	}
	return model.BenchmarkStatusPass, ""
}

// buildErrorMessage creates a human-readable error message based on final status.
func buildErrorMessage(finalStatus model.BenchmarkStatus, execErrMsg string) string {
	if execErrMsg != "" {
		return execErrMsg
	}
	switch finalStatus {
	case model.BenchmarkStatusFail:
		return "Benchmark completed but validation failed (check metrics)"
	case model.BenchmarkStatusError:
		return "Benchmark completed but results could not be parsed"
	default:
		return ""
	}
}

// collectArtifacts adds log file and config artifacts to the result.
func (w *WorkflowOrchestrator) collectArtifacts(result *model.BenchmarkRun, targetLogPath string) {
	// Upload log file if available
	if targetLogPath != "" {
		result.Artifacts = append(result.Artifacts, targetLogPath)
		if upload, err := w.createArtifactUpload(targetLogPath); err == nil {
			result.ArtifactUploads = append(result.ArtifactUploads, *upload)
		} else {
			fmt.Fprintf(os.Stderr, "warning: failed to prepare artifact upload for %s: %v\n", targetLogPath, err)
		}
	}

	// Upload hpcg.dat config file
	hpcgDatPath := filepath.Join(w.WorkDir, "hpcg.dat")
	if upload, err := w.createArtifactUpload(hpcgDatPath); err == nil {
		result.Artifacts = append(result.Artifacts, hpcgDatPath)
		result.ArtifactUploads = append(result.ArtifactUploads, *upload)
	} else {
		fmt.Fprintf(os.Stderr, "warning: failed to prepare artifact upload for hpcg.dat: %v\n", err)
	}
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
					if err := w.moveFile(latestLog, targetLogPath); err != nil {
						fmt.Fprintf(os.Stderr, "warning: failed to move log file to %s: %v\n", targetLogPath, err)
					}
				}
			}
		}
	}
	return targetLogPath
}

func (w *WorkflowOrchestrator) moveFile(sourcePath, destPath string) error {
	// Try rename first
	err := os.Rename(sourcePath, destPath)
	if err == nil {
		return nil
	}

	// If rename fails (e.g. cross-device link), fallback to copy + delete
	input, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer input.Close()

	output, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer output.Close()

	_, err = io.Copy(output, input)
	if err != nil {
		return err
	}

	// Close files before removing source
	input.Close()
	output.Close()

	return os.Remove(sourcePath)
}

// createArtifactUpload reads a file and creates an ArtifactUpload with base64-encoded content.
// This allows the server to store the file without needing shared filesystem access.
func (w *WorkflowOrchestrator) createArtifactUpload(filePath string) (*model.ArtifactUpload, error) {
	// Get file info for size
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to stat file: %w", err)
	}

	// Read file content
	content, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read file: %w", err)
	}

	// Extract file extension without the dot
	ext := filepath.Ext(filePath)
	if ext != "" {
		ext = ext[1:] // Remove the leading dot
	}

	return &model.ArtifactUpload{
		Filename: filepath.Base(filePath),
		Content:  base64.StdEncoding.EncodeToString(content),
		FileType: ext,
		Size:     fileInfo.Size(),
	}, nil
}

func (w *WorkflowOrchestrator) setupEnvironment(ctx context.Context, modules []string) error {
	if w.ModuleLoader != nil && len(modules) > 0 {
		if err := w.ModuleLoader.Load(ctx, modules); err != nil {
			return fmt.Errorf("failed to load modules: %w", err)
		}
	}
	return nil
}

// ensureHPCGSource checks if HPCG source is available and clones it if needed.
// It looks for the setup/ directory which indicates HPCG source is present.
func (w *WorkflowOrchestrator) ensureHPCGSource(ctx context.Context) error {
	setupDir := filepath.Join(w.WorkDir, "setup")

	// Check if setup directory exists (indicates HPCG source is present)
	if _, err := os.Stat(setupDir); err == nil {
		// HPCG source exists, ensure OpenMP config is available
		return w.ensureOpenMPConfig()
	}

	fmt.Fprintf(os.Stderr, "HPCG source not found, cloning from %s...\n", HPCGRepoURL)

	// Clone HPCG repository into a temporary directory, then move contents
	// We clone to a temp dir first because git clone needs an empty or non-existent target
	tempDir := w.WorkDir + ".tmp"
	defer os.RemoveAll(tempDir) // Clean up temp dir regardless of outcome

	// Clone the repository
	cloneCmd := fmt.Sprintf("git clone --depth 1 %s %s", HPCGRepoURL, tempDir)
	if output, err := w.Runner.Run(ctx, filepath.Dir(w.WorkDir), "bash", "-c", cloneCmd); err != nil {
		return fmt.Errorf("failed to clone HPCG repository: %w\nOutput:\n%s", err, string(output))
	}

	// Move contents from temp to work dir
	// First, list all files in temp dir
	entries, err := os.ReadDir(tempDir)
	if err != nil {
		return fmt.Errorf("failed to read cloned directory: %w", err)
	}

	for _, entry := range entries {
		src := filepath.Join(tempDir, entry.Name())
		dst := filepath.Join(w.WorkDir, entry.Name())

		// Skip if destination already exists
		if _, err := os.Stat(dst); err == nil {
			continue
		}

		if err := os.Rename(src, dst); err != nil {
			// If rename fails (cross-device), try copy
			if entry.IsDir() {
				copyCmd := fmt.Sprintf("cp -r %s %s", src, dst)
				if _, copyErr := w.Runner.Run(ctx, w.WorkDir, "bash", "-c", copyCmd); copyErr != nil {
					return fmt.Errorf("failed to copy %s: %w", entry.Name(), copyErr)
				}
			} else {
				return fmt.Errorf("failed to move %s: %w", entry.Name(), err)
			}
		}
	}

	fmt.Fprintln(os.Stderr, "HPCG source cloned successfully.")

	// Ensure OpenMP config is available after cloning
	return w.ensureOpenMPConfig()
}

// ensureOpenMPConfig creates Make.Linux_OpenMP if it doesn't exist.
// This enables multi-threaded HPCG builds using OpenMP.
func (w *WorkflowOrchestrator) ensureOpenMPConfig() error {
	openmpConfig := filepath.Join(w.WorkDir, "setup", "Make.Linux_OpenMP")

	// Check if OpenMP config already exists
	if _, err := os.Stat(openmpConfig); err == nil {
		return nil
	}

	// Create Make.Linux_OpenMP based on Linux_Serial but with OpenMP flags
	// This is a standard OpenMP configuration for GCC
	content := `# HPCG Build Configuration for Linux with OpenMP
# Auto-generated by hpc-agent

SHELL        = /bin/sh
CD           = cd
CP           = cp
LN_S         = ln -s -f
MKDIR        = mkdir -p
RM           = /bin/rm -f
TOUCH        = touch

TOPdir       = .
SRCdir       = $(TOPdir)/src
INCdir       = $(TOPdir)/src
BINdir       = $(TOPdir)/bin

HPCG_INCLUDES = -I$(INCdir) -I$(INCdir)/$(arch) $(MPinc)
HPCG_LIBS     =

# OpenMP-enabled compiler settings
CXX          = g++
CXXFLAGS     = $(HPCG_DEFS) -O3 -fopenmp -ffast-math -ftree-vectorize
LINKER       = $(CXX)
LINKFLAGS    = $(CXXFLAGS)

HPCG_DEFS    = -DHPCG_NO_MPI -DHPCG_NO_OPENMP=0
`

	fmt.Fprintln(os.Stderr, "Creating OpenMP build configuration...")
	if err := os.WriteFile(openmpConfig, []byte(content), 0600); err != nil {
		return fmt.Errorf("failed to create Make.Linux_OpenMP: %w", err)
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

// runBenchmark executes the benchmark command with PID tracking if available.
// If PIDTracker is not set or runID is empty, it falls back to regular execution.
func (w *WorkflowOrchestrator) runBenchmark(ctx context.Context, runID, runCmd string) ([]byte, error) {
	// Use PID tracking if available and we have a valid run ID
	if w.PIDTracker != nil && runID != "" && runID != "manual-run" {
		return w.PIDTracker.RunCommandWithPID(ctx, runID, w.WorkDir, "bash", "-c", runCmd)
	}

	// Fall back to regular execution
	return w.Runner.Run(ctx, w.WorkDir, "bash", "-c", runCmd)
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

// captureLogContent gathers log content from command output and log files.
// Returns combined content truncated to reasonable size for API transmission.
func (w *WorkflowOrchestrator) captureLogContent(output []byte, targetLogPath string, startTime time.Time) string {
	var sb strings.Builder
	const maxLogSize = 100000 // 100KB limit for log content

	// Include command output
	if len(output) > 0 {
		sb.WriteString("=== Command Output ===\n")
		sb.Write(output)
		sb.WriteString("\n")
	}

	// Try to read the log file content
	logToRead := targetLogPath
	if logToRead == "" {
		if latestLog, err := w.findLatestLog(startTime); err == nil {
			logToRead = latestLog
		}
	}

	if logToRead != "" {
		if content, err := os.ReadFile(logToRead); err == nil {
			sb.WriteString("\n=== HPCG Log File ===\n")
			sb.Write(content)
		}
	}

	result := sb.String()
	if len(result) > maxLogSize {
		result = result[:maxLogSize] + "\n... (truncated)"
	}

	return result
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
