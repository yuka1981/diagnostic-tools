package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"

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
	modules    []string
	nx, ny, nz int
	rt         int
}

func (o *hpcgOptions) addFlags(cmd *cobra.Command) {
	cmd.Flags().StringVar(&o.runID, "id", "manual-run", "Run ID")
	cmd.Flags().StringSliceVar(&o.modules, "module", nil, "Modules to load")
	cmd.Flags().StringVar(&o.buildCmd, "build", "", "Build command (e.g. 'make')")
	cmd.Flags().StringVar(&o.runCmd, "run", "./xhpcg", "Run command")
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

	runner := infrastructure.NewRealCommandRunner()
	loader := infrastructure.NewRealModuleLoader(runner)

	orchestrator := &hpcg.WorkflowOrchestrator{
		Runner:       runner,
		ModuleLoader: loader,
		WorkDir:      wd,
	}

	params := hpcg.RunParams{
		RunID:    opts.runID,
		Modules:  opts.modules,
		BuildCmd: opts.buildCmd,
		RunCmd:   opts.runCmd,
		Config: hpcg.ConfigParams{
			NX: opts.nx, NY: opts.ny, NZ: opts.nz, RunTimeSeconds: opts.rt,
		},
	}

	fmt.Fprintln(cmd.OutOrStdout(), "Starting HPCG workflow...")
	result, err := orchestrator.Run(ctx, &params)
	if err != nil {
		return fmt.Errorf("HPCG workflow failed: %w", err)
	}

	// Output result
	output, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Fprintf(cmd.ErrOrStderr(), "Warning: could not marshal result for printing: %v\n", err)
	} else {
		fmt.Fprintln(cmd.OutOrStdout(), string(output))
	}

	// Upload if token provided
	if opts.pushToken != "" {
		up := uploader.NewHTTPUploader(opts.pushServer, opts.pushToken)
		fmt.Fprintln(cmd.OutOrStdout(), "Uploading result...")
		if err := up.Upload(ctx, result); err != nil {
			return fmt.Errorf("upload failed: %w", err)
		}
		fmt.Fprintln(cmd.OutOrStdout(), "Upload successful.")
	}

	return nil
}

func init() {
	rootCmd.AddCommand(NewHPCGCmd())
}
