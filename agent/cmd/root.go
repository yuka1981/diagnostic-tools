package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/identity"
)

// Global flags
var nodeUUID string

// version holds the agent version, set via SetVersion from main.go
var version = "dev"

// SetVersion sets the agent version (called from main.go with ldflags value)
func SetVersion(v string) {
	version = v
}

// GetVersion returns the current agent version
func GetVersion() string {
	return version
}

var rootCmd = &cobra.Command{
	Use:   "qis-agent",
	Short: "QIS Agent",
	Long:  `QIS System Detection & Benchmark Agent`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		// If node-uuid is provided via CLI, set it as the forced identity
		// This ensures the agent uses the server-known UUID instead of generating a new one
		if nodeUUID != "" {
			identity.SetForcedNodeID(nodeUUID)
		}
	},
}

func init() {
	// Add global persistent flag for node UUID injection
	// This allows the server to pass the known node UUID to ensure identity consistency
	rootCmd.PersistentFlags().StringVar(&nodeUUID, "node-uuid", "", "Override node UUID (injected by server for identity consistency)")
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
