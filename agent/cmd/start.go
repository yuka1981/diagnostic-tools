package cmd

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/identity"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
	"github.com/yuka1981/diagnostic-tools/agent/core/stream"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/inventory"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector"
)

// agentHandler implements stream.CommandHandler
type agentHandler struct {
	collector ports.InventoryCollector
}

func (h *agentHandler) HandleCommand(ctx context.Context, action string, payload map[string]interface{}, responder stream.Responder) error {
	log.Printf("Received command: %s", action)

	correlationID := payload["correlation_id"]

	switch action {
	case "collect_inventory":
		log.Println("Executing inventory collection...")
		state, err := h.collector.Collect(ctx)
		if err != nil {
			return responder.Send(ctx, map[string]interface{}{
				"action":         "report_result",
				"status":         "error",
				"error":          err.Error(),
				"correlation_id": correlationID,
			})
		}

		return responder.Send(ctx, map[string]interface{}{
			"action":         "report_result",
			"status":         "success",
			"payload":        state,
			"correlation_id": correlationID,
		})

	case "ping":
		return responder.Send(ctx, map[string]string{
			"status":   "pong",
			"received": action,
		})

	default:
		log.Printf("Unknown command: %s", action)
	}
	return nil
}

var startCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the agent in daemon mode",
	RunE: func(cmd *cobra.Command, args []string) error {
		serverURL, _ := cmd.Flags().GetString("server")
		token, _ := cmd.Flags().GetString("token")
		configDir, _ := cmd.Flags().GetString("config")

		if token == "" {
			return fmt.Errorf("token is required (use --token or AGENT_TOKEN env var)")
		}

		// 0. Identity
		nodeID, err := identity.GetOrGenerateNodeID(configDir)
		if err != nil {
			log.Printf("Warning: failed to get node identity: %v", err)
		}
		if nodeID == "" {
			return fmt.Errorf("node identity is required for daemon mode")
		}

		log.Printf("Starting agent daemon (NodeID: %s)...", nodeID)
		log.Printf("Server: %s", serverURL)

		// 1. Initialize Components
		runner := infrastructure.NewRealCommandRunner()
		sysCollector := collector.NewSystemCollector(runner)
		inventoryService := inventory.NewInventoryService(sysCollector)

		// 2. Initialize WS Client
		handler := &agentHandler{
			collector: inventoryService,
		}
		client := stream.NewClient(serverURL, token, nodeID, handler)

		// 2. Handle Shutdown Signals
		ctx, cancel := context.WithCancel(cmd.Context())
		defer cancel()

		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

		go func() {
			<-sigChan
			log.Println("Shutting down agent...")
			cancel()
		}()

		// 3. Start Client (Blocks)
		return client.Start(ctx)
	},
}

func init() {
	startCmd.Flags().String("server", "http://localhost:3000", "Server URL")
	startCmd.Flags().String("token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	startCmd.Flags().String("config", "/etc/hpc-agent", "Configuration directory")

	rootCmd.AddCommand(startCmd)
}
