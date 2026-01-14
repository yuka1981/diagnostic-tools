//go:build linux

package native

import (
	"context"
	"errors"
	"testing"

	"github.com/jaypipes/ghw/pkg/cpu"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/jaypipes/ghw/pkg/topology"
)

// MockCPUProvider is a mock implementation for testing.
type MockCPUProvider struct {
	CPUInfo      *cpu.Info
	TopologyInfo *topology.Info
	CPUErr       error
	TopologyErr  error
}

func (m *MockCPUProvider) CPU(opts ...*option.Option) (*cpu.Info, error) {
	return m.CPUInfo, m.CPUErr
}

func (m *MockCPUProvider) Topology(opts ...*option.Option) (*topology.Info, error) {
	return m.TopologyInfo, m.TopologyErr
}

func TestNativeCPUCollector_Collect(t *testing.T) {
	t.Run("Success_BasicCPUInfo", func(t *testing.T) {
		mockProvider := &MockCPUProvider{
			CPUInfo: &cpu.Info{
				TotalCores:   16,
				TotalThreads: 32,
				Processors: []*cpu.Processor{
					{
						ID:         0,
						NumCores:   8,
						NumThreads: 16,
						Vendor:     "GenuineIntel",
						Model:      "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
						Capabilities: []string{
							"fpu", "vme", "de", "pse", "tsc", "msr", "pae",
							"avx", "avx2", "avx512f",
						},
					},
					{
						ID:         1,
						NumCores:   8,
						NumThreads: 16,
						Vendor:     "GenuineIntel",
						Model:      "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz",
					},
				},
			},
			TopologyInfo: &topology.Info{
				Nodes: []*topology.Node{
					{ID: 0},
					{ID: 1},
				},
			},
		}

		collector := NewNativeCPUCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if info == nil {
			t.Fatal("expected info to be non-nil")
		}

		if info.Cores != 16 {
			t.Errorf("expected Cores 16, got %d", info.Cores)
		}

		if info.Threads != 32 {
			t.Errorf("expected Threads 32, got %d", info.Threads)
		}

		if info.Sockets != 2 {
			t.Errorf("expected Sockets 2, got %d", info.Sockets)
		}

		if info.VendorID != "GenuineIntel" {
			t.Errorf("expected VendorID 'GenuineIntel', got %q", info.VendorID)
		}

		if info.ModelName != "Intel(R) Xeon(R) Gold 6248 CPU @ 2.50GHz" {
			t.Errorf("expected correct ModelName, got %q", info.ModelName)
		}

		if len(info.Flags) == 0 {
			t.Error("expected Flags to be non-empty")
		}

		// Check for specific flag
		hasAVX := false
		for _, f := range info.Flags {
			if f == "avx512f" {
				hasAVX = true
				break
			}
		}
		if !hasAVX {
			t.Error("expected 'avx512f' flag to be present")
		}

		if info.NUMANodes != 2 {
			t.Errorf("expected NUMANodes 2, got %d", info.NUMANodes)
		}
	})

	t.Run("Error_CPUInfoFails", func(t *testing.T) {
		mockProvider := &MockCPUProvider{
			CPUErr: errors.New("permission denied: cannot read /sys"),
		}

		collector := NewNativeCPUCollector(mockProvider)
		_, err := collector.Collect(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("Success_TopologyError_GracefulDegradation", func(t *testing.T) {
		// Topology info may fail but CPU info should still work
		mockProvider := &MockCPUProvider{
			CPUInfo: &cpu.Info{
				TotalCores:   4,
				TotalThreads: 8,
				Processors: []*cpu.Processor{
					{
						ID:         0,
						NumCores:   4,
						NumThreads: 8,
						Vendor:     "AuthenticAMD",
						Model:      "AMD Ryzen 5 3600",
					},
				},
			},
			TopologyErr: errors.New("topology not available"),
		}

		collector := NewNativeCPUCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (graceful degradation), got %v", err)
		}

		if info.NUMANodes != 0 {
			t.Errorf("expected NUMANodes 0 (fallback), got %d", info.NUMANodes)
		}
	})

	t.Run("Success_EmptyProcessors", func(t *testing.T) {
		mockProvider := &MockCPUProvider{
			CPUInfo: &cpu.Info{
				TotalCores:   4,
				TotalThreads: 4,
				Processors:   []*cpu.Processor{},
			},
		}

		collector := NewNativeCPUCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if info.Sockets != 0 {
			t.Errorf("expected Sockets 0, got %d", info.Sockets)
		}
	})

	t.Run("Success_CoresPerSocket", func(t *testing.T) {
		mockProvider := &MockCPUProvider{
			CPUInfo: &cpu.Info{
				TotalCores:   32,
				TotalThreads: 64,
				Processors: []*cpu.Processor{
					{ID: 0, NumCores: 16, NumThreads: 32},
					{ID: 1, NumCores: 16, NumThreads: 32},
				},
			},
		}

		collector := NewNativeCPUCollector(mockProvider)
		info, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if info.CoresPerSocket != 16 {
			t.Errorf("expected CoresPerSocket 16, got %d", info.CoresPerSocket)
		}

		if info.ThreadsPerCore != 2 {
			t.Errorf("expected ThreadsPerCore 2, got %d", info.ThreadsPerCore)
		}
	})
}

func TestNewNativeCPUCollector_DefaultProvider(t *testing.T) {
	// When nil is passed, it should create a default real provider
	collector := NewNativeCPUCollector(nil)

	if collector == nil {
		t.Fatal("expected non-nil collector")
	}

	if collector.provider == nil {
		t.Fatal("expected non-nil provider")
	}
}
