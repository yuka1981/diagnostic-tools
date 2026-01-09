package inventory

import (
	"context"
	"time"

	"golang.org/x/sync/errgroup"

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
	var host *model.HostInfo
	var cpu *model.CPUInfo
	var mem *model.MemoryInfo
	var disk []model.DiskInfo
	var net []model.NetInfo
	var networkV2 *model.NetworkInventory
	var dmi *model.HostDMIInfo

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() (err error) {
		host, err = s.collector.GetHostInfo(gCtx)
		return err
	})

	g.Go(func() (err error) {
		cpu, err = s.collector.GetCPUInfo(gCtx)
		return err
	})

	g.Go(func() (err error) {
		mem, err = s.collector.GetMemInfo(gCtx)
		return err
	})

	g.Go(func() (err error) {
		disk, err = s.collector.GetDiskInfo(gCtx)
		return err
	})

	g.Go(func() (err error) {
		net, err = s.collector.GetNetInfo(gCtx)
		return err
	})

	g.Go(func() (err error) {
		networkV2, err = s.collector.GetNetworkInventory(gCtx)
		return err
	})

	g.Go(func() (err error) {
		dmi, err = s.collector.GetDMIInfo(gCtx)
		return err
	})

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return &model.NodeState{
		CapturedAt: time.Now().UTC(),
		Host:       host,
		CPU:        cpu,
		Memory:     mem,
		Disks:      disk,
		Network:    net,
		NetworkV2:  networkV2,
		DMI:        dmi,
	}, nil
}
