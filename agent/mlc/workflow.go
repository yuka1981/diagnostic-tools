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
func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
	start := time.Now()

	// Load environment modules if specified
	if err := w.setupEnvironment(ctx, params.Modules); err != nil {
		return nil, err
	}

	// Determine which tests to run
	tests, err := w.resolveTests(params)
	if err != nil {
		return nil, err
	}

	// Determine binary path
	binaryPath := w.BinaryPath
	if params.BinaryPath != "" {
		binaryPath = params.BinaryPath
	}

	// Run all tests and aggregate output
	var allOutput string
	for _, test := range tests {
		flag, ok := testToFlag[test]
		if !ok {
			return nil, fmt.Errorf("unknown test: %s", test)
		}

		output, runErr := w.Runner.Run(ctx, "", binaryPath, flag)
		if runErr != nil {
			return nil, fmt.Errorf("test %s failed: %w", test, runErr)
		}
		allOutput += string(output) + "\n"
	}

	end := time.Now()

	// Parse metrics from combined output
	metrics, parseErr := ParseMLCOutput(allOutput)
	if parseErr != nil {
		return nil, fmt.Errorf("failed to parse MLC output: %w", parseErr)
	}

	// Marshal metrics to JSON
	metricsJSON, marshalErr := json.Marshal(metrics)
	if marshalErr != nil {
		return nil, fmt.Errorf("failed to marshal metrics: %w", marshalErr)
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
