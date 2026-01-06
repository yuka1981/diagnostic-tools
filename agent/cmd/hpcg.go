package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/hpcg"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/internal/reporter"
)

type hpcgOptions struct {
	runID      string
	buildCmd   string
	runCmd     string
	pushServer string
	pushToken  string
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

	orchestrator := &hpcg.WorkflowOrchestrator{
		Runner:       infrastructure.NewRealCommandRunner(),
		ModuleLoader: infrastructure.NewRealModuleLoader(infrastructure.NewRealCommandRunner()),
		WorkDir:      wd,
	}

	params, stopHeartbeat := setupRunParams(opts)
	defer stopHeartbeat()

	fmt.Fprintln(cmd.OutOrStdout(), "Starting HPCG workflow...")

	result, err := orchestrator.Run(ctx, params)
	if err != nil {
		_ = params.Reporter.ReportState("failed", err.Error())
		return fmt.Errorf("HPCG workflow failed: %w", err)
	}

	// Output result to stdout
	output, _ := json.MarshalIndent(result, "", "  ")
	fmt.Fprintln(cmd.OutOrStdout(), string(output))

	return handleBenchmarkResult(ctx, cmd, opts, params, result)
}

func setupRunParams(opts *hpcgOptions) (params *hpcg.RunParams, stopHeartbeat func()) {
	params = &hpcg.RunParams{
		RunID:    opts.runID,
		Modules:  opts.modules,
		BuildCmd: opts.buildCmd,
		RunCmd:   opts.runCmd,
		LogPath:  opts.logPath,
		LogDir:   "/tmp/hpc-diagnostics-log",
		Config: hpcg.ConfigParams{
			NX: opts.nx, NY: opts.ny, NZ: opts.nz, RunTimeSeconds: opts.rt,
		},
		Reporter: reporter.NewReporter(opts.runID, opts.pushServer, opts.pushToken),
	}

	var heartbeatCancel context.CancelFunc
	stopHeartbeat = func() {
		if heartbeatCancel != nil {
			heartbeatCancel()
			heartbeatCancel = nil
		}
	}

	params.OnHeartbeatStart = func(cancel context.CancelFunc) {
		heartbeatCancel = cancel
	}

	return params, stopHeartbeat
}

func handleBenchmarkResult(
	ctx context.Context,
	cmd *cobra.Command,
	opts *hpcgOptions,
	params *hpcg.RunParams,
	result *model.BenchmarkRun,
) error {
	// If benchmark execution failed, report and exit early
	if result.Status != model.BenchmarkStatusPass {
		_ = params.Reporter.ReportState("failed", fmt.Sprintf("Benchmark status: %s", result.Status))
		return fmt.Errorf("benchmark finished with status %s", result.Status)
	}

	// Upload final result if token is present
	if opts.pushToken != "" {
		_ = params.Reporter.ReportState("uploading", "Syncing Artifacts")
		fmt.Fprintln(cmd.OutOrStdout(), "Uploading result...")
		if err := uploadBenchmarkResult(ctx, opts.pushServer, opts.pushToken, result); err != nil {
			_ = params.Reporter.ReportState("failed", err.Error())
			return fmt.Errorf("upload failed: %w", err)
		}
		fmt.Fprintln(cmd.OutOrStdout(), "Upload successful.")
	}

	// Report final success
	_ = params.Reporter.ReportState("success", "")
	return nil
}

func uploadBenchmarkResult(ctx context.Context, server, token string, result *model.BenchmarkRun) error {
	if token == "" {
		return nil
	}
	up := uploader.NewHTTPUploader(server, token)
	return up.Upload(ctx, result)
}

func init() {
	rootCmd.AddCommand(NewHPCGCmd())
}
