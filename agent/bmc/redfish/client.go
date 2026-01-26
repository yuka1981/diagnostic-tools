// Package redfish provides a Redfish protocol implementation for BMC communication.
package redfish

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"
	"strings"

	"github.com/stmcginnis/gofish"
	"github.com/stmcginnis/gofish/common"
	"github.com/stmcginnis/gofish/redfish"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// Health status constants.
const (
	healthOK       = "OK"
	healthWarning  = "Warning"
	healthCritical = "Critical"
)

// Client implements ports.BMCClient for Redfish protocol.
type Client struct {
	client *gofish.APIClient
	config ports.BMCConfig
}

// NewClient creates a new Redfish client.
func NewClient(config ports.BMCConfig) *Client { //nolint:gocritic // config is small enough to pass by value
	return &Client{config: config}
}

// Connect establishes connection to Redfish service.
func (c *Client) Connect(ctx context.Context) error {
	// Build endpoint URL
	endpoint := fmt.Sprintf("https://%s", c.config.Address)
	if c.config.Port > 0 {
		endpoint = fmt.Sprintf("https://%s:%d", c.config.Address, c.config.Port)
	}

	// Configure HTTP client with optional SSL verification
	httpClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: !c.config.VerifySSL, //nolint:gosec // User controls SSL verification
			},
		},
	}

	// Connect to Redfish service
	config := gofish.ClientConfig{
		Endpoint:   endpoint,
		Username:   c.config.Username,
		Password:   c.config.Password,
		HTTPClient: httpClient,
	}

	client, err := gofish.Connect(config)
	if err != nil {
		return fmt.Errorf("failed to connect to Redfish service: %w", err)
	}

	c.client = client
	return nil
}

// Close closes the Redfish connection.
func (c *Client) Close() error {
	if c.client != nil {
		c.client.Logout()
	}
	return nil
}

// GetInventory retrieves complete hardware inventory from BMC.
func (c *Client) GetInventory(ctx context.Context) (*model.BMCInventory, error) {
	inventory := &model.BMCInventory{}

	// Collect all components, ignoring individual errors
	processors, _ := c.GetProcessors(ctx)
	inventory.Processors = processors

	memory, _ := c.GetMemory(ctx)
	inventory.Memory = memory

	storage, _ := c.GetStorage(ctx)
	inventory.Storage = storage

	network, _ := c.GetNetwork(ctx)
	inventory.Network = network

	infiniband, _ := c.GetInfiniband(ctx)
	inventory.Infiniband = infiniband

	bios, _ := c.GetBIOS(ctx)
	if bios != nil {
		inventory.BIOS = *bios
	}

	bmcInfo, _ := c.GetBMCInfo(ctx)
	if bmcInfo != nil {
		inventory.BMCInfo = *bmcInfo
	}

	return inventory, nil
}

// GetProcessors retrieves CPU information from BMC.
func (c *Client) GetProcessors(ctx context.Context) ([]model.BMCProcessor, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	processors := []model.BMCProcessor{}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return processors, nil // Return empty slice on error
	}

	for _, system := range systems {
		procs, err := system.Processors()
		if err != nil {
			continue
		}

		for _, proc := range procs {
			processor := model.BMCProcessor{
				Socket:   proc.Socket,
				Model:    proc.Model,
				Cores:    proc.TotalCores,
				FreqBase: int(proc.MaxSpeedMHz),
				FreqMax:  int(proc.MaxSpeedMHz),
				Serial:   proc.SerialNumber,
			}
			processors = append(processors, processor)
		}
	}

	return processors, nil
}

// GetMemory retrieves memory module information from BMC.
func (c *Client) GetMemory(ctx context.Context) ([]model.BMCMemoryModule, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	modules := []model.BMCMemoryModule{}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return modules, nil
	}

	for _, system := range systems {
		memory, err := system.Memory()
		if err != nil {
			continue
		}

		for _, mem := range memory {
			// Skip empty slots
			if mem.CapacityMiB == 0 {
				continue
			}

			module := model.BMCMemoryModule{
				Slot:         mem.DeviceLocator,
				SizeGB:       mem.CapacityMiB / 1024,
				SpeedMHz:     mem.OperatingSpeedMhz,
				Manufacturer: mem.Manufacturer,
				Serial:       mem.SerialNumber,
				Type:         string(mem.MemoryDeviceType),
			}
			modules = append(modules, module)
		}
	}

	return modules, nil
}

// GetStorage retrieves storage device information from BMC.
func (c *Client) GetStorage(ctx context.Context) ([]model.BMCStorageDrive, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	drives := []model.BMCStorageDrive{}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return drives, nil
	}

	for _, system := range systems {
		storage, err := system.Storage()
		if err != nil {
			continue
		}

		for _, controller := range storage {
			storDrives, err := controller.Drives()
			if err != nil {
				continue
			}

			for _, drive := range storDrives {
				d := model.BMCStorageDrive{
					Name:      drive.Name,
					Capacity:  drive.CapacityBytes,
					Model:     drive.Model,
					Serial:    drive.SerialNumber,
					Interface: string(drive.Protocol),
					Health:    string(drive.Status.Health),
				}
				drives = append(drives, d)
			}
		}
	}

	return drives, nil
}

// GetNetwork retrieves network adapter information from BMC.
func (c *Client) GetNetwork(ctx context.Context) ([]model.BMCNetworkAdapter, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	adapters := []model.BMCNetworkAdapter{}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return adapters, nil
	}

	for _, system := range systems {
		// Try EthernetInterfaces first (more common)
		ethInterfaces, err := system.EthernetInterfaces()
		if err == nil {
			for _, eth := range ethInterfaces {
				adapter := model.BMCNetworkAdapter{
					Name:     eth.Name,
					MAC:      eth.MACAddress,
					Speed:    formatSpeed(eth.SpeedMbps),
					Firmware: eth.UefiDevicePath, // Use UEFI path as firmware info if available
				}
				adapters = append(adapters, adapter)
			}
		}

		// Also try NetworkInterfaces for additional info
		netInterfaces, err := system.NetworkInterfaces()
		if err == nil {
			for _, netIf := range netInterfaces {
				// Get network adapters from this interface
				netAdapters, err := netIf.NetworkAdapter()
				if err != nil || netAdapters == nil {
					continue
				}

				adapter := model.BMCNetworkAdapter{
					Name:  netAdapters.Name,
					Model: netAdapters.Model,
				}
				adapters = append(adapters, adapter)
			}
		}
	}

	return adapters, nil
}

// GetInfiniband retrieves Infiniband adapter information from BMC.
func (c *Client) GetInfiniband(ctx context.Context) ([]model.BMCInfinibandAdapter, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	ibAdapters := []model.BMCInfinibandAdapter{}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return ibAdapters, nil
	}

	for _, system := range systems {
		// Look for NetworkInterfaces with Infiniband type
		netInterfaces, err := system.NetworkInterfaces()
		if err != nil {
			continue
		}

		for _, netIf := range netInterfaces {
			netAdapter, err := netIf.NetworkAdapter()
			if err != nil || netAdapter == nil {
				continue
			}

			// Check if this is an Infiniband adapter by looking at the name/model
			adapterName := netAdapter.Name
			adapterModel := netAdapter.Model
			if !isInfinibandAdapter(adapterName, adapterModel) {
				continue
			}

			ibAdapter := model.BMCInfinibandAdapter{
				HCA: adapterName,
			}

			// Try to get port state from network ports
			netPorts, err := netAdapter.NetworkPorts()
			if err == nil && len(netPorts) > 0 {
				ibAdapter.PortState = string(netPorts[0].LinkStatus)
			}

			ibAdapters = append(ibAdapters, ibAdapter)
		}
	}

	return ibAdapters, nil
}

// GetBIOS retrieves BIOS information from BMC.
func (c *Client) GetBIOS(ctx context.Context) (*model.BMCBIOSInfo, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil {
		return &model.BMCBIOSInfo{}, nil
	}

	if len(systems) == 0 {
		return &model.BMCBIOSInfo{}, nil
	}

	system := systems[0]
	biosInfo := &model.BMCBIOSInfo{
		Version: system.BIOSVersion,
	}

	// Try to get more BIOS details
	bios, err := system.Bios()
	if err == nil && bios != nil {
		// Try to get vendor from attributes
		if attrs := bios.Attributes; attrs != nil {
			if vendor, ok := attrs["SystemManufacturer"].(string); ok {
				biosInfo.Vendor = vendor
			}
		}
	}

	return biosInfo, nil
}

// GetBMCInfo retrieves BMC controller information.
func (c *Client) GetBMCInfo(ctx context.Context) (*model.BMCControllerInfo, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	service := c.client.GetService()
	managers, err := service.Managers()
	if err != nil {
		return &model.BMCControllerInfo{}, nil
	}

	if len(managers) == 0 {
		return &model.BMCControllerInfo{}, nil
	}

	manager := managers[0]
	bmcInfo := &model.BMCControllerInfo{
		Model:    manager.Model,
		Firmware: manager.FirmwareVersion,
	}

	// Try to get IP from ethernet interfaces
	ethInterfaces, err := manager.EthernetInterfaces()
	if err == nil && len(ethInterfaces) > 0 {
		for _, eth := range ethInterfaces {
			if len(eth.IPv4Addresses) > 0 {
				bmcInfo.IP = eth.IPv4Addresses[0].Address
				break
			}
		}
	}

	return bmcInfo, nil
}

// GetSensors retrieves all sensor readings from BMC.
func (c *Client) GetSensors(ctx context.Context) ([]model.BMCSensorReading, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	sensors := []model.BMCSensorReading{}

	service := c.client.GetService()
	chassis, err := service.Chassis()
	if err != nil {
		return sensors, nil
	}

	for _, ch := range chassis {
		// Get thermal sensors
		thermal, err := ch.Thermal()
		if err == nil && thermal != nil {
			sensors = append(sensors, extractThermalSensors(thermal)...)
		}

		// Get power sensors
		power, err := ch.Power()
		if err == nil && power != nil {
			sensors = append(sensors, extractPowerSensors(power)...)
		}
	}

	return sensors, nil
}

// GetHealth retrieves system health summary from BMC.
func (c *Client) GetHealth(ctx context.Context) (*model.BMCHealthSummary, error) {
	if c.client == nil {
		return nil, fmt.Errorf("client not connected")
	}

	health := &model.BMCHealthSummary{
		Overall:    "Unknown",
		Components: make(map[string]string),
	}

	service := c.client.GetService()
	systems, err := service.Systems()
	if err != nil || len(systems) == 0 {
		return health, nil
	}

	system := systems[0]
	health.Overall = string(system.Status.Health)

	c.collectSystemHealth(system, health)
	c.collectChassisHealth(service, health)

	return health, nil
}

// collectSystemHealth populates component health from ComputerSystem.
func (c *Client) collectSystemHealth(system *redfish.ComputerSystem, health *model.BMCHealthSummary) {
	// Check processor health
	if procs, err := system.Processors(); err == nil && len(procs) > 0 {
		health.Components["Processors"] = aggregateHealth(procs)
	}

	// Check memory health
	if memory, err := system.Memory(); err == nil && len(memory) > 0 {
		health.Components["Memory"] = aggregateMemoryHealth(memory)
	}

	// Check storage health
	if storage, err := system.Storage(); err == nil && len(storage) > 0 {
		health.Components["Storage"] = aggregateStorageHealth(storage)
	}
}

// collectChassisHealth populates component health from Chassis.
func (c *Client) collectChassisHealth(service *gofish.Service, health *model.BMCHealthSummary) {
	chassis, err := service.Chassis()
	if err != nil || len(chassis) == 0 {
		return
	}

	health.Components["Chassis"] = string(chassis[0].Status.Health)

	// Check thermal health
	if thermal, err := chassis[0].Thermal(); err == nil && thermal != nil {
		health.Components["Thermal"] = aggregateThermalHealth(thermal)
	}

	// Check power health
	if power, err := chassis[0].Power(); err == nil && power != nil {
		health.Components["Power"] = aggregatePowerHealth(power)
	}
}

// Helper functions

func extractThermalSensors(thermal *redfish.Thermal) []model.BMCSensorReading {
	sensors := []model.BMCSensorReading{}

	// Temperature sensors
	for i := range thermal.Temperatures {
		temp := &thermal.Temperatures[i]
		if temp.ReadingCelsius == 0 && temp.Status.State != common.EnabledState {
			continue
		}
		sensor := model.BMCSensorReading{
			Name:   temp.Name,
			Value:  float64(temp.ReadingCelsius),
			Unit:   "Celsius",
			Status: string(temp.Status.Health),
		}
		sensors = append(sensors, sensor)
	}

	// Fan sensors
	for i := range thermal.Fans {
		fan := &thermal.Fans[i]
		if fan.Reading == 0 && fan.Status.State != common.EnabledState {
			continue
		}
		sensor := model.BMCSensorReading{
			Name:   fan.Name,
			Value:  float64(fan.Reading),
			Unit:   string(fan.ReadingUnits),
			Status: string(fan.Status.Health),
		}
		sensors = append(sensors, sensor)
	}

	return sensors
}

func extractPowerSensors(power *redfish.Power) []model.BMCSensorReading {
	sensors := []model.BMCSensorReading{}

	// Power supplies
	for i := range power.PowerSupplies {
		psu := &power.PowerSupplies[i]
		if psu.PowerOutputWatts > 0 {
			sensor := model.BMCSensorReading{
				Name:   psu.Name,
				Value:  float64(psu.PowerOutputWatts),
				Unit:   "Watts",
				Status: string(psu.Status.Health),
			}
			sensors = append(sensors, sensor)
		}
	}

	// Voltages
	for i := range power.Voltages {
		volt := &power.Voltages[i]
		if volt.ReadingVolts == 0 && volt.Status.State != common.EnabledState {
			continue
		}
		sensor := model.BMCSensorReading{
			Name:   volt.Name,
			Value:  float64(volt.ReadingVolts),
			Unit:   "Volts",
			Status: string(volt.Status.Health),
		}
		sensors = append(sensors, sensor)
	}

	return sensors
}

func aggregateHealth(procs []*redfish.Processor) string {
	for _, proc := range procs {
		if proc.Status.Health == common.CriticalHealth {
			return healthCritical
		}
	}
	for _, proc := range procs {
		if proc.Status.Health == common.WarningHealth {
			return healthWarning
		}
	}
	return healthOK
}

func aggregateMemoryHealth(memory []*redfish.Memory) string {
	for _, mem := range memory {
		if mem.Status.Health == common.CriticalHealth {
			return healthCritical
		}
	}
	for _, mem := range memory {
		if mem.Status.Health == common.WarningHealth {
			return healthWarning
		}
	}
	return healthOK
}

func aggregateStorageHealth(storage []*redfish.Storage) string {
	for _, stor := range storage {
		if stor.Status.Health == common.CriticalHealth {
			return healthCritical
		}
	}
	for _, stor := range storage {
		if stor.Status.Health == common.WarningHealth {
			return healthWarning
		}
	}
	return healthOK
}

func aggregateThermalHealth(thermal *redfish.Thermal) string {
	for i := range thermal.Temperatures {
		if thermal.Temperatures[i].Status.Health == common.CriticalHealth {
			return healthCritical
		}
	}
	for i := range thermal.Temperatures {
		if thermal.Temperatures[i].Status.Health == common.WarningHealth {
			return healthWarning
		}
	}
	return healthOK
}

func aggregatePowerHealth(power *redfish.Power) string {
	for i := range power.PowerSupplies {
		if power.PowerSupplies[i].Status.Health == common.CriticalHealth {
			return healthCritical
		}
	}
	for i := range power.PowerSupplies {
		if power.PowerSupplies[i].Status.Health == common.WarningHealth {
			return healthWarning
		}
	}
	return healthOK
}

func formatSpeed(speedMbps int) string {
	if speedMbps == 0 {
		return ""
	}
	if speedMbps >= 1000 {
		return fmt.Sprintf("%dGbps", speedMbps/1000)
	}
	return fmt.Sprintf("%dMbps", speedMbps)
}

func isInfinibandAdapter(name, modelName string) bool {
	lower := strings.ToLower(name + " " + modelName)
	return strings.Contains(lower, "infiniband") ||
		strings.Contains(lower, "mellanox") ||
		strings.Contains(lower, "mlx") ||
		strings.Contains(lower, "hca") ||
		strings.Contains(lower, "ib ")
}

// Ensure Client implements ports.BMCClient interface.
var _ ports.BMCClient = (*Client)(nil)
