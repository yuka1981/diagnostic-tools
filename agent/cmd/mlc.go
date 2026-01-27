package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/identity"
	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/mlc"
)

type mlcOptions struct {
	profile    string
	binaryPath string
	server     string
	token      string
	configDir  string
	runID      string
	tests      []string
	modules    []string
	dryRun     bool
}

func (o *mlcOptions) addFlags(cmd *cobra.Command) {
	cmd.Flags().StringVar(&o.profile, "profile", "quick", "Test profile (quick, standard, full, numa, latency)")
	cmd.Flags().StringSliceVar(&o.tests, "tests", nil, "Custom test list (overrides profile)")
	cmd.Flags().StringVar(&o.binaryPath, "binary", "mlc", "Path to mlc binary")
	cmd.Flags().StringSliceVar(&o.modules, "module", nil, "Lmod modules to load")
	cmd.Flags().StringVar(&o.server, "server", getEnvOrDefault("QIS_AGENT_SERVER", "http://localhost:3000"), "Server URL")
	cmd.Flags().StringVar(&o.token, "token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	cmd.Flags().StringVar(&o.configDir, "config", "/etc/qis-agent", "Configuration directory")
	cmd.Flags().BoolVar(&o.dryRun, "dry-run", false, "Print what would run without executing")
	cmd.Flags().StringVar(&o.runID, "id", "mlc-run", "Run ID")
}

// NewMLCCmd creates the mlc command.
func NewMLCCmd() *cobra.Command {
	opts := &mlcOptions{}
	cmd := &cobra.Command{
		Use:   "mlc",
		Short: "Run Intel MLC memory benchmark",
		Long: `Run Intel Memory Latency Checker (MLC) benchmark.

MLC measures memory latencies and bandwidth to characterize memory subsystem
performance. Available profiles:

  quick     - Fast health check (~4 min): idle_latency, peak_injection_bandwidth
  standard  - Regular characterization (~6 min): latency_matrix, bandwidth_matrix, peak_injection_bandwidth
  full      - Complete characterization (~15 min): all tests
  numa      - NUMA topology focus (~5 min): latency_matrix, bandwidth_matrix, c2c_latency
  latency   - Latency-sensitive tuning (~8 min): idle_latency, loaded_latency, c2c_latency

Examples:
  # Quick health check
  qis-agent mlc --profile quick

  # Full characterization with module loading
  qis-agent mlc --profile full --module intel-oneapi

  # Custom tests
  qis-agent mlc --tests idle_latency,bandwidth_matrix

  # Dry run to see what would execute
  qis-agent mlc --dry-run --profile full`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runMLC(cmd, opts)
		},
	}
	opts.addFlags(cmd)
	return cmd
}

func runMLC(cmd *cobra.Command, opts *mlcOptions) error {
	ctx := cmd.Context()

	nodeID := getMLCNodeID(opts.configDir)
	params := buildMLCRunParams(opts)

	// Dry run: print what would be executed and exit
	if opts.dryRun {
		return printMLCDryRun(cmd, opts, &params, nodeID)
	}

	orchestrator := createMLCOrchestrator(opts.binaryPath)

	fmt.Fprintln(cmd.OutOrStdout(), "Starting MLC workflow...")
	warnIfNoMLCToken(opts.token)
	sendMLCInitialStatus(ctx, cmd, opts, nodeID)

	result, err := orchestrator.Run(ctx, &params)
	if err != nil {
		notifyMLCFailure(ctx, opts, nodeID)
		return fmt.Errorf("MLC workflow failed: %w", err)
	}

	outputMLCResult(cmd, result)
	return uploadMLCFinalResult(ctx, cmd, opts, nodeID, result)
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getMLCNodeID(configDir string) string {
	nodeID, err := identity.GetOrGenerateNodeID(configDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to get node identity: %v\n", err)
	}
	return nodeID
}

func createMLCOrchestrator(binaryPath string) *mlc.WorkflowOrchestrator {
	runner := infrastructure.NewRealCommandRunner()
	loader := infrastructure.NewRealModuleLoader(runner)
	return &mlc.WorkflowOrchestrator{
		Runner:       runner,
		ModuleLoader: loader,
		BinaryPath:   binaryPath,
	}
}

func buildMLCRunParams(opts *mlcOptions) mlc.RunParams {
	return mlc.RunParams{
		RunID:      opts.runID,
		Profile:    opts.profile,
		BinaryPath: opts.binaryPath,
		LogDir:     "/tmp/qis-agent-log",
		Tests:      opts.tests,
		Modules:    opts.modules,
	}
}

func printMLCDryRun(cmd *cobra.Command, opts *mlcOptions, params *mlc.RunParams, nodeID string) error {
	fmt.Fprintln(cmd.OutOrStdout(), "=== MLC Dry Run ===")
	fmt.Fprintf(cmd.OutOrStdout(), "Node ID: %s\n", nodeID)
	fmt.Fprintf(cmd.OutOrStdout(), "Run ID: %s\n", params.RunID)
	fmt.Fprintf(cmd.OutOrStdout(), "Profile: %s\n", params.Profile)
	fmt.Fprintf(cmd.OutOrStdout(), "Binary Path: %s\n", valueOrDefault(params.BinaryPath, "(default: mlc)"))
	fmt.Fprintf(cmd.OutOrStdout(), "Server: %s\n", opts.server)
	fmt.Fprintf(cmd.OutOrStdout(), "Config Dir: %s\n", opts.configDir)

	if len(params.Modules) > 0 {
		fmt.Fprintf(cmd.OutOrStdout(), "Modules: %v\n", params.Modules)
	}

	// Resolve tests to show what would run
	tests := params.Tests
	if len(tests) == 0 {
		profile, err := mlc.GetProfile(params.Profile)
		if err != nil {
			return fmt.Errorf("invalid profile: %w", err)
		}
		tests = profile.Tests
		fmt.Fprintf(cmd.OutOrStdout(), "\nProfile '%s': %s\n", profile.Name, profile.Description)
	} else {
		fmt.Fprintln(cmd.OutOrStdout(), "\nCustom tests specified:")
	}

	fmt.Fprintln(cmd.OutOrStdout(), "\nTests to run:")
	for _, test := range tests {
		fmt.Fprintf(cmd.OutOrStdout(), "  - %s\n", test)
	}

	if opts.token == "" {
		fmt.Fprintln(cmd.OutOrStdout(), "\nNote: No token provided, results would NOT be uploaded")
	} else {
		fmt.Fprintf(cmd.OutOrStdout(), "\nResults would be uploaded to: %s\n", opts.server)
	}

	return nil
}

func valueOrDefault(value, defaultValue string) string {
	if value == "" {
		return defaultValue
	}
	return value
}

func warnIfNoMLCToken(token string) {
	if token == "" {
		fmt.Fprintln(os.Stderr, "Warning: No authentication token provided (--token or AGENT_TOKEN env var).")
		fmt.Fprintln(os.Stderr, "         Benchmark results will NOT be uploaded to the server.")
	}
}

func sendMLCInitialStatus(ctx context.Context, cmd *cobra.Command, opts *mlcOptions, nodeID string) {
	statusErr := uploadMLCBenchmarkStatus(
		ctx, opts.server, opts.token, nodeID, opts.runID, model.BenchmarkStatusRunning,
	)
	if statusErr != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to send initial status update: %v\n", statusErr)
		fmt.Fprintln(os.Stderr, "         The benchmark will continue, but the server may not show 'Running' status.")
	} else if opts.token != "" {
		fmt.Fprintln(cmd.OutOrStdout(), "Initial status update sent successfully.")
	}
}

func notifyMLCFailure(ctx context.Context, opts *mlcOptions, nodeID string) {
	failErr := uploadMLCBenchmarkStatus(
		ctx, opts.server, opts.token, nodeID, opts.runID, model.BenchmarkStatusFail,
	)
	if failErr != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to send failure status: %v\n", failErr)
	}
}

func outputMLCResult(cmd *cobra.Command, result *model.BenchmarkRun) {
	output, _ := json.MarshalIndent(result, "", "  ")
	fmt.Fprintln(cmd.OutOrStdout(), string(output))
}

func uploadMLCFinalResult(
	ctx context.Context,
	cmd *cobra.Command,
	opts *mlcOptions,
	nodeID string,
	result *model.BenchmarkRun,
) error {
	if opts.token == "" {
		return nil
	}
	fmt.Fprintln(cmd.OutOrStdout(), "Uploading result...")
	if err := uploadMLCBenchmarkResult(ctx, opts.server, opts.token, nodeID, result); err != nil {
		return fmt.Errorf("upload failed: %w", err)
	}
	fmt.Fprintln(cmd.OutOrStdout(), "Upload successful.")
	return nil
}

func uploadMLCBenchmarkStatus(ctx context.Context, server, token, nodeID, runID string, status model.BenchmarkStatus) error {
	if token == "" {
		// No token means no upload - this is handled by the caller with a warning
		return nil
	}
	up := uploader.NewHTTPUploader(server, token)
	if nodeID != "" {
		up.SetNodeID(nodeID)
	}
	run := &model.BenchmarkRun{
		RunID:     runID,
		RecipeID:  "mlc",
		Status:    status,
		StartTime: time.Now(),
	}
	if err := up.Upload(ctx, run); err != nil {
		return fmt.Errorf("upload to %s failed: %w", server, err)
	}
	return nil
}

func uploadMLCBenchmarkResult(ctx context.Context, server, token, nodeID string, result *model.BenchmarkRun) error {
	if token == "" {
		return nil
	}
	up := uploader.NewHTTPUploader(server, token)
	if nodeID != "" {
		up.SetNodeID(nodeID)
	}
	if err := up.Upload(ctx, result); err != nil {
		return fmt.Errorf("upload to %s failed (run_id=%s): %w", server, result.RunID, err)
	}
	return nil
}

func init() {
	rootCmd.AddCommand(NewMLCCmd())
}
