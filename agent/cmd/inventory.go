package cmd

import (
	"github.com/spf13/cobra"
)

var inventoryCmd = &cobra.Command{
	Use:   "inventory",
	Short: "Manage system inventory",
}

func init() {
	rootCmd.AddCommand(inventoryCmd)
}
