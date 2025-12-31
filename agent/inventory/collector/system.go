package collector

import (
	"context"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
	"github.com/yuka1981/diagnostic-tools/agent/inventory/collector/linux"
)

// SystemCollector aggregates individual collectors to implement ports.SystemCollector.
type SystemCollector struct {
	host *linux.LinuxHostCollector
	cpu  *linux.LinuxCPUCollector
	mem  *linux.LinuxMemoryCollector
	disk *linux.LinuxDiskCollector
	net  *linux.LinuxNetCollector
}

// NewSystemCollector creates a new system collector with Linux implementations.
func NewSystemCollector(runner ports.CommandRunner) *SystemCollector {
	return &SystemCollector{
		host: linux.NewLinuxHostCollector(runner),
		cpu:  linux.NewLinuxCPUCollector(),
		mem:  linux.NewLinuxMemoryCollector(),
		disk: linux.NewLinuxDiskCollector(runner),
		net:  linux.NewLinuxNetCollector(),
	}
}

// GetHostInfo collects host information.
func (c *SystemCollector) GetHostInfo(ctx context.Context) (*model.HostInfo, error) {
	return c.host.Collect(ctx)
}

// GetCPUInfo collects CPU information.
func (c *SystemCollector) GetCPUInfo() (*model.CPUInfo, error) {
	return c.cpu.Collect()
}

// GetMemInfo collects memory information.
func (c *SystemCollector) GetMemInfo() (*model.MemoryInfo, error) {
	return c.mem.Collect()
}

// GetDiskInfo collects disk information.
func (c *SystemCollector) GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error) {
	return c.disk.Collect(ctx)
}

// GetNetInfo collects network information.
func (c *SystemCollector) GetNetInfo() ([]model.NetInfo, error) {
	return c.net.Collect()
}
