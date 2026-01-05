package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
)

var checkKeyCmd = &cobra.Command{
	Use:   "check-key",
	Short: "Check if the API key is valid",
	RunE: func(cmd *cobra.Command, args []string) error {
		server, _ := cmd.Flags().GetString("server")
		token, _ := cmd.Flags().GetString("token")

		if token == "" {
			token = os.Getenv("AGENT_TOKEN")
		}

		if token == "" {
			return fmt.Errorf("token is required (use --token or AGENT_TOKEN env var)")
		}

		up := uploader.NewHTTPUploader(server, token)
		fmt.Fprintf(cmd.OutOrStdout(), "Checking API key against %s...\n", server)

		if err := up.CheckAuth(cmd.Context()); err != nil {
			return fmt.Errorf("API key check failed: %w", err)
		}

		fmt.Fprintln(cmd.OutOrStdout(), "API key is valid.")
		return nil
	},
}

func init() {
	checkKeyCmd.Flags().String("server", "http://localhost:3000", "Server URL")
	checkKeyCmd.Flags().String("token", "", "Authentication token")
	rootCmd.AddCommand(checkKeyCmd)
}
