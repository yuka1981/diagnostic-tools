package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/bmc"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

var healthCmd = &cobra.Command{
	Use:   "health",
	Short: "Check BMC health",
	Long:  "Connects to a BMC and displays health summary",
	RunE:  runHealth,
}

var (
	bmcAddress  string
	bmcUser     string
	bmcPassword string
	bmcProtocol string
)

func init() {
	healthCmd.Flags().StringVar(&bmcAddress, "address", "", "BMC IP address or hostname")
	healthCmd.Flags().StringVar(&bmcUser, "user", "", "BMC username")
	healthCmd.Flags().StringVar(&bmcPassword, "password", "", "BMC password")
	healthCmd.Flags().StringVar(&bmcProtocol, "protocol", "auto", "Protocol: auto, redfish, ipmi")
	_ = healthCmd.MarkFlagRequired("address")
	_ = healthCmd.MarkFlagRequired("user")
	_ = healthCmd.MarkFlagRequired("password")
	rootCmd.AddCommand(healthCmd)
}

func runHealth(cmd *cobra.Command, _ []string) error {
	ctx, cancel := context.WithTimeout(cmd.Context(), 30*time.Second)
	defer cancel()

	config := ports.BMCConfig{
		Address:  bmcAddress,
		Username: bmcUser,
		Password: bmcPassword,
		Protocol: bmcProtocol,
	}

	client, err := bmc.NewClient(ctx, config)
	if err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}
	defer client.Close()

	health, err := client.GetHealth(ctx)
	if err != nil {
		return fmt.Errorf("failed to get health: %w", err)
	}

	fmt.Fprintf(cmd.OutOrStdout(), "Protocol: %s\n", bmc.DetectedProtocol(client))

	// Output as JSON
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(health)
}
