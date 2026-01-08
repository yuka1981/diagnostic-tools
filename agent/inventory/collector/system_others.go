//go:build !linux

package collector

import (
	"context"
	"fmt"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// SystemCollector stub for non-Linux systems.
type SystemCollector struct{}

// NewSystemCollector creates a new system collector (stub).
func NewSystemCollector(runner ports.CommandRunner) *SystemCollector {
	return &SystemCollector{}
}

func (c *SystemCollector) GetHostInfo(ctx context.Context) (*model.HostInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}

func (c *SystemCollector) GetCPUInfo(ctx context.Context) (*model.CPUInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}

func (c *SystemCollector) GetMemInfo(ctx context.Context) (*model.MemoryInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}

func (c *SystemCollector) GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}

func (c *SystemCollector) GetNetInfo(ctx context.Context) ([]model.NetInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}

func (c *SystemCollector) GetDMIInfo(ctx context.Context) (*model.HostDMIInfo, error) {
	return nil, fmt.Errorf("not implemented on this OS")
}
