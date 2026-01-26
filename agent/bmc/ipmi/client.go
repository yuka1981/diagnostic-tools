// Package ipmi provides IPMI client implementation for BMC communication.
package ipmi

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// CommandExecutor defines the interface for executing external commands.
// This allows for mocking in tests.
type CommandExecutor interface {
	// LookPath searches for an executable in the system PATH.
	LookPath(file string) (string, error)
	// CommandContext creates and executes a command with context.
	CommandContext(ctx context.Context, name string, args ...string) (string, error)
}

// RealCommandExecutor implements CommandExecutor using os/exec.
type RealCommandExecutor struct{}

// LookPath searches for an executable in the system PATH.
func (r *RealCommandExecutor) LookPath(file string) (string, error) {
	return exec.LookPath(file)
}

// CommandContext creates and executes a command with context.
func (r *RealCommandExecutor) CommandContext(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		stderrStr := strings.TrimSpace(stderr.String())
		if stderrStr != "" {
			return "", fmt.Errorf("command error: %s: %w", stderrStr, err)
		}
		return "", err
	}

	return stdout.String(), nil
}

// Client implements ports.BMCClient using ipmitool CLI.
type Client struct {
	config   ports.BMCConfig
	ipmitool string          // path to ipmitool binary
	executor CommandExecutor // command executor (can be mocked for tests)
}

// NewClient creates a new IPMI client with the given configuration.
func NewClient(config ports.BMCConfig) *Client {
	return &Client{
		config:   config,
		ipmitool: "ipmitool",
		executor: &RealCommandExecutor{},
	}
}

// NewClientWithExecutor creates a new IPMI client with a custom command executor.
// This is primarily used for testing.
func NewClientWithExecutor(config ports.BMCConfig, executor CommandExecutor) *Client {
	return &Client{
		config:   config,
		ipmitool: "ipmitool",
		executor: executor,
	}
}

// SetIPMIToolPath allows overriding the ipmitool binary path.
func (c *Client) SetIPMIToolPath(path string) {
	c.ipmitool = path
}

// Connect verifies ipmitool is available and credentials work.
func (c *Client) Connect(ctx context.Context) error {
	// Check if ipmitool exists
	_, err := c.executor.LookPath(c.ipmitool)
	if err != nil {
		return fmt.Errorf("ipmitool not found in PATH: %w", err)
	}

	// Test connection with a simple command
	_, err = c.runCommand(ctx, "mc", "info")
	if err != nil {
		return fmt.Errorf("failed to connect to BMC at %s: %w", c.config.Address, err)
	}

	return nil
}

// Close is a no-op for IPMI (no persistent connection).
func (c *Client) Close() error {
	return nil
}

// runCommand executes an ipmitool command and returns output.
func (c *Client) runCommand(ctx context.Context, args ...string) (string, error) {
	baseArgs := c.buildBaseArgs()
	allArgs := append(baseArgs, args...)

	output, err := c.executor.CommandContext(ctx, c.ipmitool, allArgs...)
	if err != nil {
		return "", fmt.Errorf("ipmitool %s: %w", strings.Join(args, " "), err)
	}

	return output, nil
}

// buildBaseArgs constructs the common ipmitool arguments.
func (c *Client) buildBaseArgs() []string {
	args := []string{
		"-I", "lanplus",
		"-H", c.config.Address,
		"-U", c.config.Username,
		"-P", c.config.Password,
	}

	if c.config.Port > 0 {
		args = append(args, "-p", strconv.Itoa(c.config.Port))
	}

	return args
}

// GetInventory retrieves complete hardware inventory.
// Note: IPMI provides limited hardware inventory compared to Redfish.
func (c *Client) GetInventory(ctx context.Context) (*model.BMCInventory, error) {
	inventory := &model.BMCInventory{}

	// Get what we can from IPMI
	processors, err := c.GetProcessors(ctx)
	if err == nil {
		inventory.Processors = processors
	}

	memory, err := c.GetMemory(ctx)
	if err == nil {
		inventory.Memory = memory
	}

	storage, err := c.GetStorage(ctx)
	if err == nil {
		inventory.Storage = storage
	}

	network, err := c.GetNetwork(ctx)
	if err == nil {
		inventory.Network = network
	}

	infiniband, err := c.GetInfiniband(ctx)
	if err == nil {
		inventory.Infiniband = infiniband
	}

	bios, err := c.GetBIOS(ctx)
	if err == nil && bios != nil {
		inventory.BIOS = *bios
	}

	bmcInfo, err := c.GetBMCInfo(ctx)
	if err == nil && bmcInfo != nil {
		inventory.BMCInfo = *bmcInfo
	}

	return inventory, nil
}

// GetProcessors retrieves CPU information.
// Note: IPMI has very limited CPU information. Use FRU data where available.
func (c *Client) GetProcessors(ctx context.Context) ([]model.BMCProcessor, error) {
	// IPMI doesn't provide detailed CPU info like Redfish
	// We can try to get some info from FRU, but it's usually limited
	output, err := c.runCommand(ctx, "fru", "print")
	if err != nil {
		return []model.BMCProcessor{}, nil
	}

	fru := ParseFRU(output)

	// Look for CPU-related FRU entries (varies by vendor)
	var processors []model.BMCProcessor

	// Check for common CPU FRU fields
	if cpuModel, ok := fru["CPU Model"]; ok {
		processors = append(processors, model.BMCProcessor{
			Socket: "CPU0",
			Model:  cpuModel,
		})
	}

	// IPMI typically doesn't have detailed CPU info
	// Return empty slice if nothing found - this is expected
	return processors, nil
}

// GetMemory retrieves memory module information.
// Note: IPMI has limited memory information available.
func (c *Client) GetMemory(ctx context.Context) ([]model.BMCMemoryModule, error) {
	// Try to get FRU data which may contain some DIMM info
	output, err := c.runCommand(ctx, "fru", "print")
	if err != nil {
		return []model.BMCMemoryModule{}, nil
	}

	fru := ParseFRU(output)
	modules := ExtractMemoryFromFRU(fru)

	// IPMI typically has very limited memory info
	return modules, nil
}

// GetStorage retrieves storage device information.
// Note: IPMI provides very limited storage information.
func (c *Client) GetStorage(ctx context.Context) ([]model.BMCStorageDrive, error) {
	// IPMI doesn't provide storage inventory like Redfish
	// Some BMCs may expose disk sensors, but not detailed inventory
	return []model.BMCStorageDrive{}, nil
}

// GetNetwork retrieves network adapter information.
// Note: IPMI only knows about the BMC's own network interface.
func (c *Client) GetNetwork(ctx context.Context) ([]model.BMCNetworkAdapter, error) {
	// Get BMC LAN configuration
	output, err := c.runCommand(ctx, "lan", "print")
	if err != nil {
		return []model.BMCNetworkAdapter{}, nil
	}

	lan := ParseLANInfo(output)

	var adapters []model.BMCNetworkAdapter

	// BMC's own network interface
	if mac, ok := lan["MAC Address"]; ok {
		adapter := model.BMCNetworkAdapter{
			Name: "BMC LAN",
			MAC:  mac,
		}
		if ip, ok := lan["IP Address"]; ok {
			adapter.Model = fmt.Sprintf("BMC Management Interface (%s)", ip)
		} else {
			adapter.Model = "BMC Management Interface"
		}
		adapters = append(adapters, adapter)
	}

	// IPMI doesn't know about host NICs
	return adapters, nil
}

// GetInfiniband retrieves Infiniband adapter information.
// Note: IPMI does not provide Infiniband information.
func (c *Client) GetInfiniband(ctx context.Context) ([]model.BMCInfinibandAdapter, error) {
	// IPMI has no knowledge of Infiniband adapters
	return []model.BMCInfinibandAdapter{}, nil
}

// GetBIOS retrieves BIOS information.
// Note: IPMI may have limited BIOS info from FRU data.
func (c *Client) GetBIOS(ctx context.Context) (*model.BMCBIOSInfo, error) {
	output, err := c.runCommand(ctx, "fru", "print")
	if err != nil {
		return &model.BMCBIOSInfo{}, nil
	}

	fru := ParseFRU(output)
	bios := ExtractBIOSInfoFromFRU(fru)

	return bios, nil
}

// GetBMCInfo retrieves BMC controller information.
func (c *Client) GetBMCInfo(ctx context.Context) (*model.BMCControllerInfo, error) {
	output, err := c.runCommand(ctx, "mc", "info")
	if err != nil {
		return nil, fmt.Errorf("failed to get BMC info: %w", err)
	}

	info := ParseMCInfo(output)

	// Add BMC IP address from config
	info.IP = c.config.Address

	return info, nil
}

// GetSensors retrieves all sensor readings.
func (c *Client) GetSensors(ctx context.Context) ([]model.BMCSensorReading, error) {
	// Try full sensor list first
	output, err := c.runCommand(ctx, "sensor", "list")
	if err != nil {
		// Fall back to SDR if sensor list fails
		output, err = c.runCommand(ctx, "sdr")
		if err != nil {
			return nil, fmt.Errorf("failed to get sensor data: %w", err)
		}
		return ParseSDR(output), nil
	}

	return ParseSensorList(output), nil
}

// GetHealth retrieves system health summary.
func (c *Client) GetHealth(ctx context.Context) (*model.BMCHealthSummary, error) {
	health := &model.BMCHealthSummary{
		Overall:    "OK",
		Components: make(map[string]string),
	}

	// Get health from sensors
	sensors, err := c.GetSensors(ctx)
	if err == nil && len(sensors) > 0 {
		sensorHealth := DeriveHealthFromSensors(sensors)
		health.Overall = sensorHealth.Overall
		for k, v := range sensorHealth.Components {
			health.Components[k] = v
		}
	}

	// Supplement with chassis status
	output, err := c.runCommand(ctx, "chassis", "status")
	if err == nil {
		chassisStatus := ParseChassisStatus(output)
		chassisHealth := DeriveHealthFromChassisStatus(chassisStatus)

		for k, v := range chassisHealth {
			// Only update if we don't have sensor data for this component
			// or if chassis shows a worse status
			if existing, ok := health.Components[k]; !ok {
				health.Components[k] = v
			} else {
				health.Components[k] = worstStatus(existing, v)
			}
		}

		// Recalculate overall
		for _, status := range health.Components {
			health.Overall = worstStatus(health.Overall, status)
		}
	}

	return health, nil
}

// Ensure Client implements BMCClient interface.
var _ ports.BMCClient = (*Client)(nil)
