package cmd

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/core/heartbeat"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/infrastructure"
	"github.com/yuka1981/diagnostic-tools/agent/inventory"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector"
)

// inventoryPusher handles scheduled inventory collection and push
type inventoryPusher struct {
	collector ports.InventoryCollector
	uploader  *uploader.HTTPUploader
}

func newInventoryPusher(serverURL, token, nodeID, version string) *inventoryPusher {
	runner := infrastructure.NewRealCommandRunner()
	sysCollector := collector.NewSystemCollector(runner)
	invService := inventory.NewInventoryService(sysCollector)

	httpUp := uploader.NewHTTPUploader(serverURL, token)
	httpUp.SetNodeID(nodeID)
	httpUp.SetVersion(version)
	httpUp.SetVerbose(false) // Reduce log noise in daemon mode

	return &inventoryPusher{
		collector: invService,
		uploader:  httpUp,
	}
}

func (p *inventoryPusher) Push(ctx context.Context) error {
	state, err := p.collector.Collect(ctx)
	if err != nil {
		return fmt.Errorf("failed to collect inventory: %w", err)
	}

	if err := p.uploader.Upload(ctx, state); err != nil {
		return fmt.Errorf("failed to push inventory: %w", err)
	}

	return nil
}

var startCmd = &cobra.Command{
	Use:   "start",
	Short: "Start the agent in daemon mode",
	RunE: func(cmd *cobra.Command, args []string) error {
		serverURL, _ := cmd.Flags().GetString("server")
		token, _ := cmd.Flags().GetString("token")
		heartbeatInterval, _ := cmd.Flags().GetDuration("heartbeat-interval")
		inventoryInterval, _ := cmd.Flags().GetDuration("inventory-interval")

		// Validate required flags
		if nodeUUID == "" {
			return fmt.Errorf("--node-uuid is required")
		}
		if token == "" {
			return fmt.Errorf("--token is required (use --token or AGENT_TOKEN env var)")
		}

		log.Printf("Starting agent daemon (NodeID: %s)...", nodeUUID)
		log.Printf("Server: %s", serverURL)
		log.Printf("Heartbeat interval: %s", heartbeatInterval)
		if inventoryInterval > 0 {
			log.Printf("Inventory interval: %s", inventoryInterval)
		} else {
			log.Println("Inventory interval: disabled")
		}

		// Create heartbeat service
		hb := heartbeat.New(serverURL, token, nodeUUID, GetVersion())

		// Create inventory pusher (if interval is set)
		var invPusher *inventoryPusher
		if inventoryInterval > 0 {
			invPusher = newInventoryPusher(serverURL, token, nodeUUID, GetVersion())
		}

		// Setup context and signal handling
		ctx, cancel := context.WithCancel(cmd.Context())
		defer cancel()

		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

		// Send initial heartbeat immediately
		log.Println("Sending initial heartbeat...")
		if err := hb.Send(ctx); err != nil {
			log.Printf("Initial heartbeat failed: %v", err)
		} else {
			log.Println("Initial heartbeat sent successfully")
		}

		// Send initial inventory push if enabled
		if invPusher != nil {
			log.Println("Pushing initial inventory...")
			hb.SetStatus(heartbeat.StatusBusy)
			if err := invPusher.Push(ctx); err != nil {
				log.Printf("Initial inventory push failed: %v", err)
			} else {
				log.Println("Initial inventory pushed successfully")
			}
			hb.SetStatus(heartbeat.StatusIdle)
		}

		// Start heartbeat ticker
		heartbeatTicker := time.NewTicker(heartbeatInterval)
		defer heartbeatTicker.Stop()

		// Start inventory ticker (if enabled)
		var inventoryTicker *time.Ticker
		var inventoryChan <-chan time.Time
		if inventoryInterval > 0 {
			inventoryTicker = time.NewTicker(inventoryInterval)
			inventoryChan = inventoryTicker.C
			defer inventoryTicker.Stop()
		}

		log.Println("Agent daemon running. Press Ctrl+C to stop.")

		for {
			select {
			case <-heartbeatTicker.C:
				if err := hb.Send(ctx); err != nil {
					log.Printf("Heartbeat failed: %v", err)
				} else {
					log.Println("Heartbeat sent")
				}

			case <-inventoryChan:
				log.Println("Scheduled inventory push starting...")
				hb.SetStatus(heartbeat.StatusBusy)
				if err := invPusher.Push(ctx); err != nil {
					log.Printf("Inventory push failed: %v", err)
				} else {
					log.Println("Inventory pushed successfully")
				}
				hb.SetStatus(heartbeat.StatusIdle)

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
	startCmd.Flags().Duration("inventory-interval", 0, "Interval between inventory pushes (0 to disable)")

	rootCmd.AddCommand(startCmd)
}
