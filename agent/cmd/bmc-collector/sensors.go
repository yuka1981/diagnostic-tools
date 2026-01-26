package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/spf13/cobra"

	"github.com/yuka1981/diagnostic-tools/agent/bmc"
	"github.com/yuka1981/diagnostic-tools/agent/bmc/metrics"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

var sensorsCmd = &cobra.Command{
	Use:   "sensors",
	Short: "Collect and push sensor data",
	Long:  "Fetches sensor readings from all nodes and pushes to Prometheus Pushgateway",
	RunE:  runSensors,
}

func init() {
	rootCmd.AddCommand(sensorsCmd)
}

func runSensors(cmd *cobra.Command, _ []string) error {
	cfg, err := loadConfig(configFile)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	ctx, cancel := context.WithTimeout(cmd.Context(), 5*time.Minute)
	defer cancel()

	// Fetch node list from Rails API
	nodes, err := fetchNodes(ctx, cfg)
	if err != nil {
		return fmt.Errorf("failed to fetch nodes: %w", err)
	}

	// Create Pushgateway client
	pushClient := metrics.NewPushgatewayClient(cfg.PrometheusURL)

	// Collect sensors from each node
	for i := range nodes {
		if err := collectAndPushSensors(ctx, &nodes[i], pushClient); err != nil {
			log.Printf("Warning: failed to collect sensors from %s: %v", nodes[i].Name, err)
		}
	}

	return nil
}

// NodeInfo represents a node from the Rails API.
type NodeInfo struct {
	Name      string          `json:"name"`
	BMCConfig ports.BMCConfig `json:"bmc_config"`
}

// fetchNodes retrieves the list of nodes from the Rails API.
func fetchNodes(ctx context.Context, cfg *Config) ([]NodeInfo, error) {
	// GET /api/v1/bmc/nodes
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, cfg.ServerURL+"/api/v1/bmc/nodes", http.NoBody)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.APIToken)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned %d", resp.StatusCode)
	}

	var nodes []NodeInfo
	if err := json.NewDecoder(resp.Body).Decode(&nodes); err != nil {
		return nil, err
	}
	return nodes, nil
}

// collectAndPushSensors collects sensor data from a node and pushes to Pushgateway.
func collectAndPushSensors(ctx context.Context, node *NodeInfo, pushClient *metrics.PushgatewayClient) error {
	// Create BMC client
	client, err := bmc.NewClient(ctx, node.BMCConfig)
	if err != nil {
		return fmt.Errorf("failed to connect: %w", err)
	}
	defer client.Close()

	// Get sensors
	sensors, err := client.GetSensors(ctx)
	if err != nil {
		return fmt.Errorf("failed to get sensors: %w", err)
	}

	// Push to Prometheus
	return pushClient.PushSensors(ctx, node.Name, sensors)
}
