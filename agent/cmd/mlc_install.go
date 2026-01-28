package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

type mlcInstallOptions struct {
	tarball    string
	binaryPath string
	installDir string
	moduleDir  string
	server     string
	token      string
	installID  string
	dryRun     bool
}

func (o *mlcInstallOptions) addFlags(cmd *cobra.Command) {
	cmd.Flags().StringVar(&o.tarball, "tarball", "", "Path to MLC tarball (required)")
	cmd.Flags().StringVar(&o.binaryPath, "binary-path", "", "Path to binary within tarball (required)")
	cmd.Flags().StringVar(&o.installDir, "install-dir", "/opt/qct/utils/qis/software", "Installation directory")
	cmd.Flags().StringVar(&o.moduleDir, "module-dir", "/opt/qct/utils/qis/modulefiles", "Modulefiles directory")
	cmd.Flags().StringVar(&o.server, "server", "", "Server URL for progress updates")
	cmd.Flags().StringVar(&o.token, "token", "", "Authentication token")
	cmd.Flags().StringVar(&o.installID, "id", "", "Installation job ID")
	cmd.Flags().BoolVar(&o.dryRun, "dry-run", false, "Print what would be done without executing")

	cmd.MarkFlagRequired("tarball")
	cmd.MarkFlagRequired("binary-path")
}

// NewMLCInstallCmd creates the mlc-install command.
func NewMLCInstallCmd() *cobra.Command {
	opts := &mlcInstallOptions{}
	cmd := &cobra.Command{
		Use:   "mlc-install",
		Short: "Install Intel MLC binary and configure Lmod module",
		Long: `Install Intel Memory Latency Checker (MLC) from a tarball.

This command:
1. Extracts the specified tarball
2. Detects MLC version from the binary
3. Installs to /opt/qct/utils/qis/software/mlc-<version>/
4. Generates Lmod modulefile at /opt/qct/utils/qis/modulefiles/mlc/<version>

Examples:
  # Install MLC from tarball
  qis-agent mlc-install --tarball /tmp/mlc.tgz --binary-path Linux/mlc

  # Dry run to see what would be installed
  qis-agent mlc-install --tarball /tmp/mlc.tgz --binary-path Linux/mlc --dry-run`,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runMLCInstall(cmd, opts)
		},
	}
	opts.addFlags(cmd)
	return cmd
}

func runMLCInstall(cmd *cobra.Command, opts *mlcInstallOptions) error {
	if opts.dryRun {
		return printMLCInstallDryRun(cmd, opts)
	}

	// TODO: Implement actual installation in Task 8
	return fmt.Errorf("installation not yet implemented")
}

func printMLCInstallDryRun(cmd *cobra.Command, opts *mlcInstallOptions) error {
	fmt.Fprintln(cmd.OutOrStdout(), "=== MLC Install Dry Run ===")
	fmt.Fprintf(cmd.OutOrStdout(), "Tarball: %s\n", opts.tarball)
	fmt.Fprintf(cmd.OutOrStdout(), "Binary Path: %s\n", opts.binaryPath)
	fmt.Fprintf(cmd.OutOrStdout(), "Install Dir: %s\n", opts.installDir)
	fmt.Fprintf(cmd.OutOrStdout(), "Module Dir: %s\n", opts.moduleDir)

	if opts.server != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "Server: %s\n", opts.server)
	}
	if opts.installID != "" {
		fmt.Fprintf(cmd.OutOrStdout(), "Install ID: %s\n", opts.installID)
	}

	fmt.Fprintln(cmd.OutOrStdout(), "\nSteps that would be executed:")
	fmt.Fprintln(cmd.OutOrStdout(), "  1. Validate tarball exists")
	fmt.Fprintln(cmd.OutOrStdout(), "  2. Extract to temp directory")
	fmt.Fprintln(cmd.OutOrStdout(), "  3. Detect version from binary")
	fmt.Fprintln(cmd.OutOrStdout(), "  4. Install binary")
	fmt.Fprintln(cmd.OutOrStdout(), "  5. Generate modulefile")
	fmt.Fprintln(cmd.OutOrStdout(), "  6. Cleanup temp files")
	fmt.Fprintln(cmd.OutOrStdout(), "  7. Report success")

	return nil
}

func init() {
	rootCmd.AddCommand(NewMLCInstallCmd())
}
