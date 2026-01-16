package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/identity"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/inventory"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector"
)

// NewPushCmd creates the push command.
// It accepts optional dependencies for testing purposes.
func NewPushCmd(col ports.InventoryCollector, upFactory func(url, token string) ports.Uploader) *cobra.Command {
	var pushServer string
	var pushToken string
	var configDir string

	cmd := &cobra.Command{
		Use:   "push",
		Short: "Collect and push system inventory to the server",
		RunE: func(cmd *cobra.Command, args []string) error {
			if pushToken == "" {
				return fmt.Errorf("token is required (use --token or AGENT_TOKEN env var)")
			}

			// 0. Identity
			nodeID, err := identity.GetOrGenerateNodeID(configDir)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Warning: failed to get node identity: %v\n", err)
			}

			// 1. Collect Inventory
			service := col
			if service == nil {
				runner := infrastructure.NewRealCommandRunner()
				sysCollector := collector.NewSystemCollector(runner)
				service = inventory.NewInventoryService(sysCollector)
			}

			fmt.Fprintln(cmd.OutOrStdout(), "Collecting system inventory...")
			state, err := service.Collect(cmd.Context())
			if err != nil {
				return fmt.Errorf("failed to collect inventory: %w", err)
			}

			// 2. Upload Inventory
			var up ports.Uploader
			if upFactory != nil {
				up = upFactory(pushServer, pushToken)
			} else {
				httpUp := uploader.NewHTTPUploader(pushServer, pushToken)
				if nodeID != "" {
					httpUp.SetNodeID(nodeID)
				}
				httpUp.SetVersion(GetVersion())
				up = httpUp
			}

			fmt.Fprintf(cmd.OutOrStdout(), "Pushing inventory to %s...\n", pushServer)
			if err := up.Upload(cmd.Context(), state); err != nil {
				return fmt.Errorf("failed to push inventory: %w", err)
			}

			fmt.Fprintln(cmd.OutOrStdout(), "Inventory pushed successfully.")
			return nil
		},
	}

	cmd.Flags().StringVar(&pushServer, "server", "http://localhost:3000", "Server URL")
	cmd.Flags().StringVar(&pushToken, "token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	cmd.Flags().StringVar(&configDir, "config", "/etc/hpc-agent", "Configuration directory")

	return cmd
}

func init() {
	inventoryCmd.AddCommand(NewPushCmd(nil, nil))
}
