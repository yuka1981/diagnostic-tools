//go:build linux

package native

import (
	"context"
	"log"
	"os"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// NativeSystemCollector implements ports.SystemCollector using native Go libraries.
// It wraps individual native collectors and provides fallback to legacy collectors.
type NativeSystemCollector struct {
	cpuCollector  CPUCollectorInterface
	memCollector  MemoryCollectorInterface
	diskCollector DiskCollectorInterface
	netCollector  NetCollectorInterface
	pciCollector  *NativePCICollector
	logger        *log.Logger
}

// NativeSystemCollectorConfig holds configuration options.
type NativeSystemCollectorConfig struct {
	// LegacyCPUCollector is the fallback CPU collector (optional).
	LegacyCPUCollector CPUCollectorInterface
	// LegacyMemoryCollector is the fallback memory collector (optional).
	LegacyMemoryCollector MemoryCollectorInterface
	// LegacyDiskCollector is the fallback disk collector (optional).
	LegacyDiskCollector DiskCollectorInterface
	// LegacyNetCollector is the fallback network collector (optional).
	LegacyNetCollector NetCollectorInterface
	// Logger for fallback warnings (optional).
	Logger *log.Logger
}

// NewNativeSystemCollector creates a new NativeSystemCollector.
// If config is nil, uses default native-only collectors without fallback.
func NewNativeSystemCollector(config *NativeSystemCollectorConfig) *NativeSystemCollector {
	logger := log.New(os.Stderr, "[native] ", log.LstdFlags)
	if config != nil && config.Logger != nil {
		logger = config.Logger
	}

	// Create native collectors
	nativeCPU := NewNativeCPUCollector(nil)
	nativeMemory := NewNativeMemoryCollector(nil)
	nativeBlock := NewNativeBlockCollector(nil)
	nativeNet := NewNativeNetworkCollector(nil)
	nativePCI := NewNativePCICollector(nil)

	var cpuCollector CPUCollectorInterface = nativeCPU
	var memCollector MemoryCollectorInterface = nativeMemory
	var diskCollector DiskCollectorInterface = &nativeBlockAdapter{nativeBlock}
	var netCollector NetCollectorInterface = &nativeNetAdapter{nativeNet}

	// Wrap with hybrid if legacy collectors are provided
	if config != nil {
		if config.LegacyCPUCollector != nil {
			cpuCollector = NewHybridCPUCollector(nativeCPU, config.LegacyCPUCollector, logger)
		}
		if config.LegacyMemoryCollector != nil {
			memCollector = NewHybridMemoryCollector(nativeMemory, config.LegacyMemoryCollector, logger)
		}
		if config.LegacyDiskCollector != nil {
			diskCollector = NewHybridDiskCollector(&nativeBlockAdapter{nativeBlock}, config.LegacyDiskCollector, logger)
		}
		if config.LegacyNetCollector != nil {
			netCollector = NewHybridNetCollector(&nativeNetAdapter{nativeNet}, config.LegacyNetCollector, logger)
		}
	}

	return &NativeSystemCollector{
		cpuCollector:  cpuCollector,
		memCollector:  memCollector,
		diskCollector: diskCollector,
		netCollector:  netCollector,
		pciCollector:  nativePCI,
		logger:        logger,
	}
}

// GetHostInfo returns host information.
// Note: Host info is still collected via the legacy method as ghw doesn't provide equivalent data.
func (c *NativeSystemCollector) GetHostInfo(ctx context.Context) (*model.HostInfo, error) {
	// ghw doesn't provide OS-level info, so we return nil here.
	// The SystemCollector should still use LinuxHostCollector for this.
	return nil, nil
}

// GetCPUInfo collects CPU information using native libraries.
func (c *NativeSystemCollector) GetCPUInfo(ctx context.Context) (*model.CPUInfo, error) {
	return c.cpuCollector.Collect(ctx)
}

// GetMemInfo collects memory information using native libraries.
func (c *NativeSystemCollector) GetMemInfo(ctx context.Context) (*model.MemoryInfo, error) {
	return c.memCollector.Collect(ctx)
}

// GetDiskInfo collects disk information using native libraries.
func (c *NativeSystemCollector) GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error) {
	return c.diskCollector.Collect(ctx)
}

// GetNetInfo collects network information using native libraries.
func (c *NativeSystemCollector) GetNetInfo(ctx context.Context) ([]model.NetInfo, error) {
	return c.netCollector.Collect(ctx)
}

// GetNetworkInventory collects detailed network inventory.
// Note: This returns nil as the native collector doesn't provide NetworkInventory format.
func (c *NativeSystemCollector) GetNetworkInventory(ctx context.Context) (*model.NetworkInventory, error) {
	return nil, nil
}

// GetDMIInfo collects DMI information using ghw memory module data.
func (c *NativeSystemCollector) GetDMIInfo(ctx context.Context) (*model.HostDMIInfo, error) {
	// Native collector doesn't provide full DMI info (BIOS/System)
	// Only DIMM info is available through ghw memory
	return nil, nil
}

// GetGPUs collects GPU information using native libraries.
func (c *NativeSystemCollector) GetGPUs(ctx context.Context) ([]GPUDevice, error) {
	return c.pciCollector.CollectGPUs(ctx)
}

// GetNetworkCards collects network card hardware information.
func (c *NativeSystemCollector) GetNetworkCards(ctx context.Context) ([]NetworkCard, error) {
	return c.pciCollector.CollectNetworkCards(ctx)
}

// nativeBlockAdapter adapts NativeBlockCollector to DiskCollectorInterface.
type nativeBlockAdapter struct {
	collector *NativeBlockCollector
}

func (a *nativeBlockAdapter) Collect(ctx context.Context) ([]model.DiskInfo, error) {
	return a.collector.CollectPartitions(ctx)
}

// nativeNetAdapter adapts NativeNetworkCollector to NetCollectorInterface.
type nativeNetAdapter struct {
	collector *NativeNetworkCollector
}

func (a *nativeNetAdapter) Collect(ctx context.Context) ([]model.NetInfo, error) {
	return a.collector.CollectSimple(ctx)
}
