//go:build linux

package native

import (
	"context"
	"fmt"

	"github.com/jaypipes/ghw/pkg/memory"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/shirou/gopsutil/v3/mem"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// MemoryProvider abstracts ghw memory and gopsutil virtual memory functions for testability.
type MemoryProvider interface {
	Memory(opts ...*option.Option) (*memory.Info, error)
	VirtualMemory() (*mem.VirtualMemoryStat, error)
}

// RealMemoryProvider is the production implementation.
type RealMemoryProvider struct{}

func (r *RealMemoryProvider) Memory(opts ...*option.Option) (*memory.Info, error) {
	return memory.New(opts...)
}

func (r *RealMemoryProvider) VirtualMemory() (*mem.VirtualMemoryStat, error) {
	return mem.VirtualMemory()
}

// NativeMemoryCollector collects memory information using ghw and gopsutil libraries.
type NativeMemoryCollector struct {
	provider MemoryProvider
	opts     []*option.Option
}

// NewNativeMemoryCollector creates a new NativeMemoryCollector.
// If provider is nil, a default RealMemoryProvider is used.
func NewNativeMemoryCollector(provider MemoryProvider) *NativeMemoryCollector {
	if provider == nil {
		provider = &RealMemoryProvider{}
	}
	return &NativeMemoryCollector{
		provider: provider,
	}
}

// Collect gathers dynamic memory statistics using gopsutil.
// ghw provides static DIMM info, gopsutil provides real-time usage.
func (c *NativeMemoryCollector) Collect(_ context.Context) (*model.MemoryInfo, error) {
	// Get dynamic memory stats from gopsutil (this is the critical data)
	vmStat, err := c.provider.VirtualMemory()
	if err != nil {
		return nil, fmt.Errorf("failed to get virtual memory stats: %w", err)
	}

	info := &model.MemoryInfo{
		Total:     vmStat.Total,
		Free:      vmStat.Free,
		Available: vmStat.Available,
		Buffers:   vmStat.Buffers,
		Cached:    vmStat.Cached,
		SwapTotal: vmStat.SwapTotal,
		SwapFree:  vmStat.SwapFree,
	}

	return info, nil
}

// CollectDIMMs gathers static DIMM module information using ghw.
// This provides detailed info about physical memory modules (slots, vendors, serial numbers).
func (c *NativeMemoryCollector) CollectDIMMs(_ context.Context) ([]model.DIMMInfo, error) {
	memInfo, err := c.provider.Memory(c.opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to get memory info: %w", err)
	}

	dimms := make([]model.DIMMInfo, 0, len(memInfo.Modules))
	for _, module := range memInfo.Modules {
		dimm := model.DIMMInfo{
			Locator:      module.Label,
			BankLocator:  module.Location,
			Size:         formatBytes(module.SizeBytes),
			Manufacturer: module.Vendor,
			SerialNumber: module.SerialNumber,
		}
		dimms = append(dimms, dimm)
	}

	return dimms, nil
}

// formatBytes converts bytes to a human-readable string.
func formatBytes(bytes int64) string {
	const (
		GB = 1024 * 1024 * 1024
		MB = 1024 * 1024
	)

	if bytes >= GB {
		return fmt.Sprintf("%d GB", bytes/GB)
	}
	if bytes >= MB {
		return fmt.Sprintf("%d MB", bytes/MB)
	}
	return fmt.Sprintf("%d bytes", bytes)
}
