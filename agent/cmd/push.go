package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/inventory"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector"
)

var (
	pushServer string
	pushToken  string
)

var pushCmd = &cobra.Command{
	Use:   "push",
	Short: "Collect and push system inventory to the server",
	RunE: func(cmd *cobra.Command, args []string) error {
		if pushToken == "" {
			return fmt.Errorf("token is required (use --token or AGENT_TOKEN env var)")
		}

		// 1. Collect Inventory
		runner := infrastructure.NewRealCommandRunner()
		sysCollector := collector.NewSystemCollector(runner)
		service := inventory.NewInventoryService(sysCollector)

		fmt.Println("Collecting system inventory...")
		state, err := service.Collect(cmd.Context())
		if err != nil {
			return fmt.Errorf("failed to collect inventory: %w", err)
		}

		// 2. Upload Inventory
		up := uploader.NewHTTPUploader(pushServer, pushToken)

		fmt.Printf("Pushing inventory to %s...\n", pushServer)
		if err := up.Upload(cmd.Context(), state); err != nil {
			return fmt.Errorf("failed to push inventory: %w", err)
		}

		fmt.Println("Inventory pushed successfully.")
		return nil
	},
}

func init() {
	pushCmd.Flags().StringVar(&pushServer, "server", "http://localhost:3000", "Server URL")
	pushCmd.Flags().StringVar(&pushToken, "token", os.Getenv("AGENT_TOKEN"), "Authentication token")

	inventoryCmd.AddCommand(pushCmd)
}
