// Package main provides the qis-bmc-collector CLI application.
// This tool collects hardware inventory and sensor data from BMC (Redfish/IPMI).
package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	configFile string
	rootCmd    = &cobra.Command{
		Use:   "qis-bmc-collector",
		Short: "QIS BMC out-of-band data collector",
		Long:  "Collects hardware inventory and sensor data from BMC (Redfish/IPMI)",
	}
)

func init() {
	rootCmd.PersistentFlags().StringVarP(&configFile, "config", "c", "/etc/qis/bmc-collector.yml", "config file path")
}

func main() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
