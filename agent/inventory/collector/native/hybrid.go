//go:build linux

package native

import (
	"context"
	"log"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// CPUCollectorInterface defines the interface for CPU collectors.
type CPUCollectorInterface interface {
	Collect(ctx context.Context) (*model.CPUInfo, error)
}

// MemoryCollectorInterface defines the interface for memory collectors.
type MemoryCollectorInterface interface {
	Collect(ctx context.Context) (*model.MemoryInfo, error)
}

// DiskCollectorInterface defines the interface for disk collectors.
type DiskCollectorInterface interface {
	Collect(ctx context.Context) ([]model.DiskInfo, error)
}

// NetCollectorInterface defines the interface for network collectors.
type NetCollectorInterface interface {
	Collect(ctx context.Context) ([]model.NetInfo, error)
}

// HybridCPUCollector tries native collection first, then falls back to legacy.
type HybridCPUCollector struct {
	native CPUCollectorInterface
	legacy CPUCollectorInterface
	logger *log.Logger
}

// NewHybridCPUCollector creates a new HybridCPUCollector.
func NewHybridCPUCollector(native, legacy CPUCollectorInterface, logger *log.Logger) *HybridCPUCollector {
	return &HybridCPUCollector{
		native: native,
		legacy: legacy,
		logger: logger,
	}
}

// Collect tries native CPU collection first, then falls back to legacy.
func (h *HybridCPUCollector) Collect(ctx context.Context) (*model.CPUInfo, error) {
	result, err := h.native.Collect(ctx)
	if err == nil {
		return result, nil
	}

	// Native failed, try legacy
	if h.logger != nil {
		h.logger.Printf("WARNING: native CPU collector failed (%v), falling back to legacy collector", err)
	}

	result, err = h.legacy.Collect(ctx)
	if err != nil {
		return nil, err
	}

	return result, nil
}

// HybridMemoryCollector tries native collection first, then falls back to legacy.
type HybridMemoryCollector struct {
	native MemoryCollectorInterface
	legacy MemoryCollectorInterface
	logger *log.Logger
}

// NewHybridMemoryCollector creates a new HybridMemoryCollector.
func NewHybridMemoryCollector(native, legacy MemoryCollectorInterface, logger *log.Logger) *HybridMemoryCollector {
	return &HybridMemoryCollector{
		native: native,
		legacy: legacy,
		logger: logger,
	}
}

// Collect tries native memory collection first, then falls back to legacy.
func (h *HybridMemoryCollector) Collect(ctx context.Context) (*model.MemoryInfo, error) {
	result, err := h.native.Collect(ctx)
	if err == nil {
		return result, nil
	}

	// Native failed, try legacy
	if h.logger != nil {
		h.logger.Printf("WARNING: native memory collector failed (%v), falling back to legacy collector", err)
	}

	result, err = h.legacy.Collect(ctx)
	if err != nil {
		return nil, err
	}

	return result, nil
}

// HybridDiskCollector tries native collection first, then falls back to legacy.
type HybridDiskCollector struct {
	native DiskCollectorInterface
	legacy DiskCollectorInterface
	logger *log.Logger
}

// NewHybridDiskCollector creates a new HybridDiskCollector.
func NewHybridDiskCollector(native, legacy DiskCollectorInterface, logger *log.Logger) *HybridDiskCollector {
	return &HybridDiskCollector{
		native: native,
		legacy: legacy,
		logger: logger,
	}
}

// Collect tries native disk collection first, then falls back to legacy.
func (h *HybridDiskCollector) Collect(ctx context.Context) ([]model.DiskInfo, error) {
	result, err := h.native.Collect(ctx)
	if err == nil {
		return result, nil
	}

	// Native failed, try legacy
	if h.logger != nil {
		h.logger.Printf("WARNING: native disk collector failed (%v), falling back to legacy collector", err)
	}

	result, err = h.legacy.Collect(ctx)
	if err != nil {
		return nil, err
	}

	return result, nil
}

// HybridNetCollector tries native collection first, then falls back to legacy.
type HybridNetCollector struct {
	native NetCollectorInterface
	legacy NetCollectorInterface
	logger *log.Logger
}

// NewHybridNetCollector creates a new HybridNetCollector.
func NewHybridNetCollector(native, legacy NetCollectorInterface, logger *log.Logger) *HybridNetCollector {
	return &HybridNetCollector{
		native: native,
		legacy: legacy,
		logger: logger,
	}
}

// Collect tries native network collection first, then falls back to legacy.
func (h *HybridNetCollector) Collect(ctx context.Context) ([]model.NetInfo, error) {
	result, err := h.native.Collect(ctx)
	if err == nil {
		return result, nil
	}

	// Native failed, try legacy
	if h.logger != nil {
		h.logger.Printf("WARNING: native network collector failed (%v), falling back to legacy collector", err)
	}

	result, err = h.legacy.Collect(ctx)
	if err != nil {
		return nil, err
	}

	return result, nil
}
