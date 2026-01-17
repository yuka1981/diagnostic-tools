package cmd

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/heartbeat"
)

var startCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the agent in daemon mode",
	RunE: func(cmd *cobra.Command, args []string) error {
		serverURL, _ := cmd.Flags().GetString("server")
		token, _ := cmd.Flags().GetString("token")
		interval, _ := cmd.Flags().GetDuration("heartbeat-interval")

		// Validate required flags
		if nodeUUID == "" {
			return fmt.Errorf("--node-uuid is required")
		}
		if token == "" {
			return fmt.Errorf("--token is required (use --token or AGENT_TOKEN env var)")
		}

		log.Printf("Starting agent daemon (NodeID: %s)...", nodeUUID)
		log.Printf("Server: %s", serverURL)
		log.Printf("Heartbeat interval: %s", interval)

		// Create heartbeat service
		hb := heartbeat.New(serverURL, token, nodeUUID, GetVersion())

		// Setup context and signal handling
		ctx := cmd.Context()
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

		// Send initial heartbeat immediately
		log.Println("Sending initial heartbeat...")
		if err := hb.Send(ctx); err != nil {
			log.Printf("Initial heartbeat failed: %v", err)
		} else {
			log.Println("Initial heartbeat sent successfully")
		}

		// Start heartbeat ticker
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		log.Println("Agent daemon running. Press Ctrl+C to stop.")

		for {
			select {
			case <-ticker.C:
				if err := hb.Send(ctx); err != nil {
					log.Printf("Heartbeat failed: %v", err)
				} else {
					log.Println("Heartbeat sent")
				}
			case sig := <-sigChan:
				log.Printf("Received signal %v, shutting down...", sig)
				return nil
			}
		}
	},
}

func init() {
	startCmd.Flags().String("server", "http://localhost:3000", "Server URL")
	startCmd.Flags().String("token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	startCmd.Flags().Duration("heartbeat-interval", 60*time.Second, "Interval between heartbeats")

	rootCmd.AddCommand(startCmd)
}
