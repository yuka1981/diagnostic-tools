//go:build linux

package native

import (
	"context"
	"errors"
	"testing"

	"github.com/jaypipes/ghw/pkg/memory"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/shirou/gopsutil/v3/mem"
)

// MockMemoryProvider is a mock implementation for testing.
type MockMemoryProvider struct {
	MemoryInfo        *memory.Info
	VirtualMemoryStat *mem.VirtualMemoryStat
	MemoryErr         error
	VirtualMemErr     error
}

func (m *MockMemoryProvider) Memory(opts ...*option.Option) (*memory.Info, error) {
	return m.MemoryInfo, m.MemoryErr
}

func (m *MockMemoryProvider) VirtualMemory() (*mem.VirtualMemoryStat, error) {
	return m.VirtualMemoryStat, m.VirtualMemErr
}

func TestNativeMemoryCollector_Collect(t *testing.T) {
	t.Run("Success_FullMemoryInfo", func(t *testing.T) {
		mockProvider := &MockMemoryProvider{
			MemoryInfo: &memory.Info{
				Area: memory.Area{
					TotalPhysicalBytes: 137438953472, // 128GB
					TotalUsableBytes:   134217728000, // ~125GB usable
					Modules: []*memory.Module{
						{
							Label:        "DIMM_A0",
							SizeBytes:    34359738368, // 32GB
							Vendor:       "Samsung",
							SerialNumber: "1234ABCD",
						},
						{
							Label:        "DIMM_B0",
							SizeBytes:    34359738368, // 32GB
							Vendor:       "Samsung",
							SerialNumber: "5678EFGH",
						},
					},
				},
			},
			VirtualMemoryStat: &mem.VirtualMemoryStat{
				Total:     137438953472,
				Available: 100000000000,
				Used:      37438953472,
				Free:      50000000000,
				Buffers:   1073741824,
				Cached:    10737418240,
				SwapTotal: 8589934592,
				SwapFree:  8589934592,
			},
		}

		collector := NewNativeMemoryCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if info == nil {
			t.Fatal("expected info to be non-nil")
		}

		if info.Total != 137438953472 {
			t.Errorf("expected Total 137438953472, got %d", info.Total)
		}

		if info.Available != 100000000000 {
			t.Errorf("expected Available 100000000000, got %d", info.Available)
		}

		if info.Free != 50000000000 {
			t.Errorf("expected Free 50000000000, got %d", info.Free)
		}

		if info.Buffers != 1073741824 {
			t.Errorf("expected Buffers 1073741824, got %d", info.Buffers)
		}

		if info.Cached != 10737418240 {
			t.Errorf("expected Cached 10737418240, got %d", info.Cached)
		}

		if info.SwapTotal != 8589934592 {
			t.Errorf("expected SwapTotal 8589934592, got %d", info.SwapTotal)
		}

		if info.SwapFree != 8589934592 {
			t.Errorf("expected SwapFree 8589934592, got %d", info.SwapFree)
		}
	})

	t.Run("Error_VirtualMemoryFails", func(t *testing.T) {
		mockProvider := &MockMemoryProvider{
			VirtualMemErr: errors.New("permission denied"),
		}

		collector := NewNativeMemoryCollector(mockProvider)
		_, err := collector.Collect(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("Success_GhwMemoryFails_GracefulDegradation", func(t *testing.T) {
		// ghw memory info may fail but gopsutil should still work
		mockProvider := &MockMemoryProvider{
			MemoryErr: errors.New("cannot read DMI"),
			VirtualMemoryStat: &mem.VirtualMemoryStat{
				Total:     32000000000,
				Available: 16000000000,
				Free:      8000000000,
			},
		}

		collector := NewNativeMemoryCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (graceful degradation), got %v", err)
		}

		if info.Total != 32000000000 {
			t.Errorf("expected Total 32000000000, got %d", info.Total)
		}
	})

	t.Run("Success_ZeroValues", func(t *testing.T) {
		mockProvider := &MockMemoryProvider{
			VirtualMemoryStat: &mem.VirtualMemoryStat{},
		}

		collector := NewNativeMemoryCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if info.Total != 0 {
			t.Errorf("expected Total 0, got %d", info.Total)
		}
	})
}

func TestNativeMemoryCollector_CollectDIMMs(t *testing.T) {
	t.Run("Success_DIMMInfo", func(t *testing.T) {
		mockProvider := &MockMemoryProvider{
			MemoryInfo: &memory.Info{
				Area: memory.Area{
					TotalPhysicalBytes: 64000000000,
					Modules: []*memory.Module{
						{
							Label:        "DIMM_A0",
							SizeBytes:    16000000000,
							Vendor:       "Micron",
							SerialNumber: "SERIAL1",
						},
						{
							Label:        "DIMM_B0",
							SizeBytes:    16000000000,
							Vendor:       "Micron",
							SerialNumber: "SERIAL2",
						},
					},
				},
			},
			VirtualMemoryStat: &mem.VirtualMemoryStat{
				Total: 64000000000,
			},
		}

		collector := NewNativeMemoryCollector(mockProvider)
		dimms, err := collector.CollectDIMMs(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(dimms) != 2 {
			t.Fatalf("expected 2 DIMMs, got %d", len(dimms))
		}

		if dimms[0].Locator != "DIMM_A0" {
			t.Errorf("expected Locator 'DIMM_A0', got %q", dimms[0].Locator)
		}

		if dimms[0].Manufacturer != "Micron" {
			t.Errorf("expected Manufacturer 'Micron', got %q", dimms[0].Manufacturer)
		}

		if dimms[0].SerialNumber != "SERIAL1" {
			t.Errorf("expected SerialNumber 'SERIAL1', got %q", dimms[0].SerialNumber)
		}
	})

	t.Run("Error_MemoryInfoFails", func(t *testing.T) {
		mockProvider := &MockMemoryProvider{
			MemoryErr: errors.New("cannot access DMI tables"),
		}

		collector := NewNativeMemoryCollector(mockProvider)
		_, err := collector.CollectDIMMs(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

func TestNewNativeMemoryCollector_DefaultProvider(t *testing.T) {
	collector := NewNativeMemoryCollector(nil)

	if collector == nil {
		t.Fatal("expected non-nil collector")
	}

	if collector.provider == nil {
		t.Fatal("expected non-nil provider")
	}
}
