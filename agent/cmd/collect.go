package cmd

import (
	"encoding/json"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/inventory"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector"
)

var collectCmd = &cobra.Command{
	Use:   "collect",
	Short: "Collect system inventory and output JSON to stdout",
	RunE: func(cmd *cobra.Command, args []string) error {
		runner := infrastructure.NewRealCommandRunner()
		sysCollector := collector.NewSystemCollector(runner)
		service := inventory.NewInventoryService(sysCollector)

		state, err := service.Collect(cmd.Context())
		if err != nil {
			return err
		}

		output, err := json.MarshalIndent(state, "", "  ")
		if err != nil {
			return err
		}

		fmt.Println(string(output))
		return nil
	},
}

func init() {
	rootCmd.AddCommand(collectCmd)
}
