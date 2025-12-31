package inventory

import (
	"context"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// InventoryService implements ports.InventoryCollector.
type InventoryService struct {
	collector ports.SystemCollector
}

// NewInventoryService creates a new inventory service.
func NewInventoryService(collector ports.SystemCollector) *InventoryService {
	return &InventoryService{collector: collector}
}

// Collect gathers all system information and returns a NodeState.
func (s *InventoryService) Collect(ctx context.Context) (*model.NodeState, error) {
	host, err := s.collector.GetHostInfo(ctx)
	if err != nil {
		return nil, err
	}

	cpu, err := s.collector.GetCPUInfo()
	if err != nil {
		return nil, err
	}

	mem, err := s.collector.GetMemInfo()
	if err != nil {
		return nil, err
	}

	disk, err := s.collector.GetDiskInfo(ctx)
	if err != nil {
		return nil, err
	}

	net, err := s.collector.GetNetInfo()
	if err != nil {
		return nil, err
	}

	return &model.NodeState{
		CapturedAt: time.Now().UTC(),
		Host:       *host,
		CPU:        *cpu,
		Memory:     *mem,
		Disks:      disk,
		Network:    net,
	}, nil
}
