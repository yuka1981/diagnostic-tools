package mlc

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// defaultProfileName is the profile used when no profile is specified.
const defaultProfileName = "quick"

// ModuleLoader defines interface for loading environment modules.
type ModuleLoader interface {
	Load(ctx context.Context, modules []string) error
}

// RunParams defines parameters for the MLC workflow.
type RunParams struct {
	RunID      string
	Profile    string // Profile name (quick, standard, full, etc.)
	BinaryPath string // Explicit binary path (overrides workflow BinaryPath)
	LogDir     string
	Tests      []string // Custom test list (overrides profile)
	Modules    []string // lmod modules to load
}

// WorkflowOrchestrator manages the MLC benchmark workflow.
type WorkflowOrchestrator struct {
	Runner       ports.CommandRunner
	ModuleLoader ModuleLoader
	BinaryPath   string // Default binary path
}

// testToFlag maps test names to MLC command-line flags.
var testToFlag = map[string]string{
	"idle_latency":             "--idle_latency",
	"loaded_latency":           "--loaded_latency",
	"latency_matrix":           "--latency_matrix",
	"bandwidth_matrix":         "--bandwidth_matrix",
	"peak_injection_bandwidth": "--peak_injection_bandwidth",
	"c2c_latency":              "--c2c_latency",
}

// Run executes the MLC workflow.
// Unlike returning errors, this always returns a BenchmarkRun with appropriate status and error message.
// This ensures failure details are always sent to the server for debugging.
func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
	start := time.Now()

	// Pre-flight check: verify hugepages are configured
	if err := CheckHugepages(MinHugepages); err != nil {
		return w.buildFailedRun(params.RunID, start, "", err.Error()), nil
	}

	// Load environment modules if specified
	if err := w.setupEnvironment(ctx, params.Modules); err != nil {
		return w.buildFailedRun(params.RunID, start, "", fmt.Sprintf("Failed to load modules: %v", err)), nil
	}

	// Determine which tests to run
	tests, err := w.resolveTests(params)
	if err != nil {
		return w.buildFailedRun(params.RunID, start, "", fmt.Sprintf("Failed to resolve tests: %v", err)), nil
	}

	// Determine binary path
	binaryPath := w.BinaryPath
	if params.BinaryPath != "" {
		binaryPath = params.BinaryPath
	}

	// Run all tests and aggregate output
	var allOutput string
	var execError string
	for _, test := range tests {
		flag, ok := testToFlag[test]
		if !ok {
			return w.buildFailedRun(params.RunID, start, allOutput, fmt.Sprintf("Unknown test: %s", test)), nil
		}

		output, runErr := w.Runner.Run(ctx, "", binaryPath, flag)
		allOutput += string(output) + "\n"
		if runErr != nil {
			execError = fmt.Sprintf("Test '%s' failed: %v", test, runErr)
			// Continue to capture any partial output, but mark as failed
			break
		}
	}

	end := time.Now()

	// If execution failed, return result with error message
	if execError != "" {
		return w.buildFailedRun(params.RunID, start, allOutput, execError), nil
	}

	// Parse metrics from combined output
	metrics, parseErr := ParseMLCOutput(allOutput)
	if parseErr != nil {
		return w.buildFailedRun(params.RunID, start, allOutput, fmt.Sprintf("Failed to parse MLC output: %v", parseErr)), nil
	}

	// Marshal metrics to JSON
	metricsJSON, marshalErr := json.Marshal(metrics)
	if marshalErr != nil {
		return w.buildFailedRun(params.RunID, start, allOutput, fmt.Sprintf("Failed to marshal metrics: %v", marshalErr)), nil
	}

	return &model.BenchmarkRun{
		RunID:      params.RunID,
		RecipeID:   "mlc",
		StartTime:  start,
		EndTime:    end,
		Status:     model.BenchmarkStatusPass,
		Metrics:    metricsJSON,
		LogContent: allOutput,
	}, nil
}

// buildFailedRun creates a BenchmarkRun with FAIL status and error message.
func (w *WorkflowOrchestrator) buildFailedRun(runID string, start time.Time, logContent, errorMsg string) *model.BenchmarkRun {
	return &model.BenchmarkRun{
		RunID:        runID,
		RecipeID:     "mlc",
		StartTime:    start,
		EndTime:      time.Now(),
		Status:       model.BenchmarkStatusFail,
		ErrorMessage: errorMsg,
		LogContent:   logContent,
	}
}

// resolveTests determines which tests to run based on params.
func (w *WorkflowOrchestrator) resolveTests(params *RunParams) ([]string, error) {
	// Custom tests take precedence
	if len(params.Tests) > 0 {
		return params.Tests, nil
	}

	// Use profile
	profileName := params.Profile
	if profileName == "" {
		profileName = defaultProfileName
	}

	profile, err := GetProfile(profileName)
	if err != nil {
		return nil, err
	}

	return profile.Tests, nil
}

// setupEnvironment loads environment modules if a ModuleLoader is configured.
func (w *WorkflowOrchestrator) setupEnvironment(ctx context.Context, modules []string) error {
	if w.ModuleLoader != nil && len(modules) > 0 {
		if err := w.ModuleLoader.Load(ctx, modules); err != nil {
			return fmt.Errorf("failed to load modules: %w", err)
		}
	}
	return nil
}
