package cmd

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
	"time"

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
		return h.handleCollectInventory(ctx, correlationID, responder)

	case "uninstall":
		return h.handleUninstall(ctx, correlationID, responder)

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

func (h *agentHandler) handleCollectInventory(ctx context.Context, correlationID interface{}, responder stream.Responder) error {
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
}

func (h *agentHandler) handleUninstall(ctx context.Context, correlationID interface{}, responder stream.Responder) error {
	log.Println("Received uninstall command. Initiating self-destruct...")
	// Acknowledge receipt
	if err := responder.Send(ctx, map[string]interface{}{
		"action":         "report_result",
		"status":         "success",
		"payload":        map[string]string{"message": "Uninstall initiated"},
		"correlation_id": correlationID,
	}); err != nil {
		log.Printf("Failed to send uninstall acknowledgement: %v", err)
	}

	go func() {
		// Allow time for the response to be flushed
		time.Sleep(1 * time.Second)

		// Execute cleanup in background.
		// 1. Disable service (so it doesn't restart)
		// 2. Remove service file
		// 3. Remove binary (self)
		// 4. Reload daemon
		// 5. Stop service (kills this process)
		cmdStr := "systemctl disable hpc-agent && " +
			"rm -f /etc/systemd/system/hpc-agent.service /usr/local/bin/hpc-agent && " +
			"systemctl daemon-reload && " +
			"systemctl stop hpc-agent"

		cmd := exec.Command("bash", "-c", cmdStr)
		cmd.SysProcAttr = &syscall.SysProcAttr{
			Setsid: true,
		}

		if err := cmd.Start(); err != nil {
			log.Printf("Failed to execute uninstall command: %v", err)
		}
		// If we are still here, exit manually
		time.Sleep(1 * time.Second)
		os.Exit(0)
	}()
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
