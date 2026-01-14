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
	"github.com/yuka1981/diagnostic-tools/agent/hpcg"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
)

type hpcgOptions struct {
	runID      string
	buildCmd   string
	runCmd     string
	pushServer string
	pushToken  string
	configDir  string
	logPath    string
	modules    []string
	nx, ny, nz int
	rt         int
}

func (o *hpcgOptions) addFlags(cmd *cobra.Command) {
	cmd.Flags().StringVar(&o.runID, "id", "manual-run", "Run ID")
	cmd.Flags().StringSliceVar(&o.modules, "module", nil, "Modules to load")
	cmd.Flags().StringVar(&o.buildCmd, "build", "", "Build command (e.g. 'make')")
	cmd.Flags().StringVar(&o.runCmd, "run", "./xhpcg", "Run command")
	cmd.Flags().StringVar(&o.logPath, "log-path", "", "Custom path for the log file")
	cmd.Flags().IntVar(&o.nx, "nx", 104, "NX")
	cmd.Flags().IntVar(&o.ny, "ny", 104, "NY")
	cmd.Flags().IntVar(&o.nz, "nz", 104, "NZ")
	cmd.Flags().IntVar(&o.rt, "rt", 60, "Runtime seconds")

	cmd.Flags().StringVar(&o.pushServer, "server", "http://localhost:3000", "Server URL")
	cmd.Flags().StringVar(&o.pushToken, "token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	cmd.Flags().StringVar(&o.configDir, "config", "/etc/hpc-agent", "Configuration directory")
}

// NewHPCGCmd creates the hpcg command.
func NewHPCGCmd() *cobra.Command {
	opts := &hpcgOptions{}
	cmd := &cobra.Command{
		Use:   "hpcg",
		Short: "Run HPCG benchmark",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runHPCG(cmd, opts)
		},
	}
	opts.addFlags(cmd)
	return cmd
}

func runHPCG(cmd *cobra.Command, opts *hpcgOptions) error {
	ctx := cmd.Context()
	wd, err := os.Getwd()
	if err != nil {
		return fmt.Errorf("failed to get current working directory: %w", err)
	}

	nodeID := getNodeID(opts.configDir)
	orchestrator := createOrchestrator(wd)
	params := buildRunParams(opts)

	fmt.Fprintln(cmd.OutOrStdout(), "Starting HPCG workflow...")
	warnIfNoToken(opts.pushToken)
	sendInitialStatus(ctx, cmd, opts, nodeID)

	result, err := orchestrator.Run(ctx, &params)
	if err != nil {
		notifyFailure(ctx, opts, nodeID)
		return fmt.Errorf("HPCG workflow failed: %w", err)
	}

	outputResult(cmd, result)
	return uploadFinalResult(ctx, cmd, opts, nodeID, result)
}

func getNodeID(configDir string) string {
	nodeID, err := identity.GetOrGenerateNodeID(configDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: failed to get node identity: %v\n", err)
	}
	return nodeID
}

func createOrchestrator(workDir string) *hpcg.WorkflowOrchestrator {
	runner := infrastructure.NewRealCommandRunner()
	loader := infrastructure.NewRealModuleLoader(runner)
	return &hpcg.WorkflowOrchestrator{
		Runner:       runner,
		ModuleLoader: loader,
		WorkDir:      workDir,
	}
}

func buildRunParams(opts *hpcgOptions) hpcg.RunParams {
	return hpcg.RunParams{
		RunID:    opts.runID,
		Modules:  opts.modules,
		BuildCmd: opts.buildCmd,
		RunCmd:   opts.runCmd,
		LogPath:  opts.logPath,
		LogDir:   "/tmp/hpc-diagnostics-log",
		Config: hpcg.ConfigParams{
			NX: opts.nx, NY: opts.ny, NZ: opts.nz, RunTimeSeconds: opts.rt,
		},
	}
}

func warnIfNoToken(token string) {
	if token == "" {
		fmt.Fprintln(os.Stderr, "Warning: No authentication token provided (--token or AGENT_TOKEN env var).")
		fmt.Fprintln(os.Stderr, "         Benchmark results will NOT be uploaded to the server.")
	}
}

func sendInitialStatus(ctx context.Context, cmd *cobra.Command, opts *hpcgOptions, nodeID string) {
	statusErr := uploadBenchmarkStatus(
		ctx, opts.pushServer, opts.pushToken, nodeID, opts.runID, model.BenchmarkStatusRunning,
	)
	if statusErr != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to send initial status update: %v\n", statusErr)
		fmt.Fprintln(os.Stderr, "         The benchmark will continue, but the server may not show 'Running' status.")
	} else if opts.pushToken != "" {
		fmt.Fprintln(cmd.OutOrStdout(), "Initial status update sent successfully.")
	}
}

func notifyFailure(ctx context.Context, opts *hpcgOptions, nodeID string) {
	failErr := uploadBenchmarkStatus(
		ctx, opts.pushServer, opts.pushToken, nodeID, opts.runID, model.BenchmarkStatusFail,
	)
	if failErr != nil {
		fmt.Fprintf(os.Stderr, "Warning: Failed to send failure status: %v\n", failErr)
	}
}

func outputResult(cmd *cobra.Command, result *model.BenchmarkRun) {
	output, _ := json.MarshalIndent(result, "", "  ")
	fmt.Fprintln(cmd.OutOrStdout(), string(output))
}

func uploadFinalResult(
	ctx context.Context,
	cmd *cobra.Command,
	opts *hpcgOptions,
	nodeID string,
	result *model.BenchmarkRun,
) error {
	if opts.pushToken == "" {
		return nil
	}
	fmt.Fprintln(cmd.OutOrStdout(), "Uploading result...")
	if err := uploadBenchmarkResult(ctx, opts.pushServer, opts.pushToken, nodeID, result); err != nil {
		return fmt.Errorf("upload failed: %w", err)
	}
	fmt.Fprintln(cmd.OutOrStdout(), "Upload successful.")
	return nil
}

func uploadBenchmarkStatus(ctx context.Context, server, token, nodeID, runID string, status model.BenchmarkStatus) error {
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
		RecipeID:  "hpcg",
		Status:    status,
		StartTime: time.Now(),
	}
	if err := up.Upload(ctx, run); err != nil {
		return fmt.Errorf("upload to %s failed: %w", server, err)
	}
	return nil
}

func uploadBenchmarkResult(ctx context.Context, server, token, nodeID string, result *model.BenchmarkRun) error {
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
	rootCmd.AddCommand(NewHPCGCmd())
}
