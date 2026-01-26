package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/bmc"
	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var inventoryCmd = &cobra.Command{
	Use:   "inventory",
	Short: "Collect and push inventory data",
	Long:  "Fetches hardware inventory from all nodes and pushes to Rails API",
	RunE:  runInventory,
}

var nodeID string

func init() {
	inventoryCmd.Flags().StringVar(&nodeID, "node", "", "collect from specific node ID only")
	rootCmd.AddCommand(inventoryCmd)
}

func runInventory(cmd *cobra.Command, _ []string) error {
	cfg, err := loadConfig(configFile)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	ctx, cancel := context.WithTimeout(cmd.Context(), 10*time.Minute)
	defer cancel()

	// Fetch node list from Rails API
	nodes, err := fetchNodes(ctx, cfg)
	if err != nil {
		return fmt.Errorf("failed to fetch nodes: %w", err)
	}

	// Filter to specific node if requested
	if nodeID != "" {
		filtered := make([]NodeInfo, 0, 1)
		for _, n := range nodes {
			if n.Name == nodeID {
				filtered = append(filtered, n)
				break
			}
		}
		nodes = filtered
	}

	// Collect inventory from each node
	for i := range nodes {
		if err := collectAndPushInventory(ctx, &nodes[i], cfg); err != nil {
			log.Printf("Warning: failed to collect inventory from %s: %v", nodes[i].Name, err)
		}
	}

	return nil
}

// collectAndPushInventory collects inventory from a node and pushes to the Rails API.
func collectAndPushInventory(ctx context.Context, node *NodeInfo, cfg *Config) error {
	// Create BMC client
	client, err := bmc.NewClient(ctx, node.BMCConfig)
	if err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}
	defer client.Close()

	// Get inventory
	inventory, err := client.GetInventory(ctx)
	if err != nil {
		return fmt.Errorf("failed to get inventory: %w", err)
	}

	// Determine collection method
	collectionMethod := bmc.DetectedProtocol(client)

	// Push to Rails API
	return pushInventory(ctx, node.Name, inventory, collectionMethod, cfg)
}

// inventoryPayload is the request body for the inventory API.
type inventoryPayload struct {
	NodeID           string              `json:"node_id"`
	Inventory        *model.BMCInventory `json:"inventory"`
	CollectionMethod string              `json:"collection_method"`
}

// pushInventory sends inventory data to the Rails API.
func pushInventory(ctx context.Context, nodeName string, inventory *model.BMCInventory, method string, cfg *Config) error {
	body := inventoryPayload{
		NodeID:           nodeName,
		Inventory:        inventory,
		CollectionMethod: method,
	}

	data, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, cfg.ServerURL+"/api/v1/bmc/inventory", bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return fmt.Errorf("API returned %d", resp.StatusCode)
	}

	log.Printf("Successfully pushed inventory for %s via %s", nodeName, method)
	return nil
}
