package cmd

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/execution"
)

// CancelResult represents the JSON response from the cancel command.
type CancelResult struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	PID     int    `json:"pid,omitempty"`
}

var cancelCmd = &cobra.Command{
	Use:   "cancel",
	Short: "Cancel a running benchmark by UUID",
	Long: `Cancel a running benchmark process by its UUID.

This command reads the PID file for the given UUID, terminates the process
(SIGTERM followed by SIGKILL if needed), and cleans up the PID file.`,
	RunE: runCancel,
}

func runCancel(cmd *cobra.Command, args []string) error {
	uuid, _ := cmd.Flags().GetString("uuid")

	if uuid == "" {
		result := CancelResult{
			Status:  "error",
			Message: "UUID is required",
		}
		return outputCancelResult(cmd, result)
	}

	pm := execution.NewPIDManager()

	pid, err := pm.CancelByUUID(uuid)
	if err != nil {
		var result CancelResult
		if errors.Is(err, execution.ErrPIDFileNotFound) {
			result = CancelResult{
				Status:  "not_found",
				Message: fmt.Sprintf("No PID file found for UUID %s", uuid),
			}
		} else if errors.Is(err, execution.ErrProcessNotFound) {
			// Process wasn't running but PID file existed (and was cleaned up)
			result = CancelResult{
				Status:  "ok",
				Message: fmt.Sprintf("Process was not running (PID file cleaned up)"),
				PID:     pid,
			}
		} else {
			result = CancelResult{
				Status:  "error",
				Message: fmt.Sprintf("Failed to cancel: %v", err),
				PID:     pid,
			}
		}
		return outputCancelResult(cmd, result)
	}

	result := CancelResult{
		Status:  "ok",
		Message: fmt.Sprintf("Process %d killed", pid),
		PID:     pid,
	}
	return outputCancelResult(cmd, result)
}

func outputCancelResult(cmd *cobra.Command, result CancelResult) error {
	output, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("failed to marshal result: %w", err)
	}
	fmt.Fprintln(cmd.OutOrStdout(), string(output))
	return nil
}

func init() {
	cancelCmd.Flags().String("uuid", "", "UUID of the benchmark run to cancel (required)")
	rootCmd.AddCommand(cancelCmd)
}
