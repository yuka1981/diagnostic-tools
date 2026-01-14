//go:build linux

package native

import (
	"context"
	"errors"
	"testing"

	"github.com/jaypipes/ghw/pkg/gpu"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/jaypipes/ghw/pkg/pci"
	"github.com/jaypipes/pcidb"
)

// MockPCIProvider is a mock implementation for testing.
type MockPCIProvider struct {
	PCIInfo *pci.Info
	GPUInfo *gpu.Info
	PCIErr  error
	GPUErr  error
}

func (m *MockPCIProvider) PCI(opts ...*option.Option) (*pci.Info, error) {
	return m.PCIInfo, m.PCIErr
}

func (m *MockPCIProvider) GPU(opts ...*option.Option) (*gpu.Info, error) {
	return m.GPUInfo, m.GPUErr
}

func TestNativePCICollector_CollectGPUs(t *testing.T) {
	t.Run("Success_NVIDIAGPUs", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			GPUInfo: &gpu.Info{
				GraphicsCards: []*gpu.GraphicsCard{
					{
						Address: "0000:01:00.0",
						Index:   0,
						DeviceInfo: &pci.Device{
							Address: "0000:01:00.0",
							Vendor: &pcidb.Vendor{
								ID:   "10de",
								Name: "NVIDIA Corporation",
							},
							Product: &pcidb.Product{
								ID:   "2204",
								Name: "GeForce RTX 3090",
							},
							Class: &pcidb.Class{
								ID:   "03",
								Name: "Display controller",
							},
							Subclass: &pcidb.Subclass{
								ID:   "02",
								Name: "3D controller",
							},
							Driver: "nvidia",
						},
					},
				},
			},
		}

		collector := NewNativePCICollector(mockProvider)
		gpus, err := collector.CollectGPUs(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(gpus) != 1 {
			t.Fatalf("expected 1 GPU, got %d", len(gpus))
		}

		if gpus[0].PCIAddress != "0000:01:00.0" {
			t.Errorf("expected PCIAddress '0000:01:00.0', got %q", gpus[0].PCIAddress)
		}
		if gpus[0].Vendor != "NVIDIA Corporation" {
			t.Errorf("expected Vendor 'NVIDIA Corporation', got %q", gpus[0].Vendor)
		}
		if gpus[0].Product != "GeForce RTX 3090" {
			t.Errorf("expected Product 'GeForce RTX 3090', got %q", gpus[0].Product)
		}
		if gpus[0].Driver != "nvidia" {
			t.Errorf("expected Driver 'nvidia', got %q", gpus[0].Driver)
		}
	})

	t.Run("Error_GPUInfoFails", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			GPUErr: errors.New("permission denied"),
		}

		collector := NewNativePCICollector(mockProvider)
		_, err := collector.CollectGPUs(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("Success_NoGPUs", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			GPUInfo: &gpu.Info{
				GraphicsCards: []*gpu.GraphicsCard{},
			},
		}

		collector := NewNativePCICollector(mockProvider)
		gpus, err := collector.CollectGPUs(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(gpus) != 0 {
			t.Errorf("expected 0 GPUs, got %d", len(gpus))
		}
	})
}

func TestNativePCICollector_CollectNetworkCards(t *testing.T) {
	t.Run("Success_MellanoxAndIntel", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			PCIInfo: &pci.Info{
				Devices: []*pci.Device{
					{
						Address: "0000:03:00.0",
						Vendor: &pcidb.Vendor{
							ID:   "15b3",
							Name: "Mellanox Technologies",
						},
						Product: &pcidb.Product{
							ID:   "101b",
							Name: "ConnectX-6 VPI adapter card",
						},
						Class: &pcidb.Class{
							ID:   "02",
							Name: "Network controller",
						},
						Driver: "mlx5_core",
					},
					{
						Address: "0000:04:00.0",
						Vendor: &pcidb.Vendor{
							ID:   "8086",
							Name: "Intel Corporation",
						},
						Product: &pcidb.Product{
							ID:   "1572",
							Name: "Ethernet Controller X710 for 10GbE SFP+",
						},
						Class: &pcidb.Class{
							ID:   "02",
							Name: "Network controller",
						},
						Driver: "i40e",
					},
					// Non-network device (should be filtered)
					{
						Address: "0000:00:1f.0",
						Vendor: &pcidb.Vendor{
							ID:   "8086",
							Name: "Intel Corporation",
						},
						Class: &pcidb.Class{
							ID:   "06",
							Name: "Bridge",
						},
					},
				},
			},
		}

		collector := NewNativePCICollector(mockProvider)
		nics, err := collector.CollectNetworkCards(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(nics) != 2 {
			t.Fatalf("expected 2 NICs (filtered non-network devices), got %d", len(nics))
		}

		// Check Mellanox card
		if nics[0].PCIAddress != "0000:03:00.0" {
			t.Errorf("expected PCIAddress '0000:03:00.0', got %q", nics[0].PCIAddress)
		}
		if nics[0].Vendor != "Mellanox Technologies" {
			t.Errorf("expected Vendor 'Mellanox Technologies', got %q", nics[0].Vendor)
		}
		if nics[0].Product != "ConnectX-6 VPI adapter card" {
			t.Errorf("expected Product 'ConnectX-6 VPI adapter card', got %q", nics[0].Product)
		}
	})

	t.Run("Success_InfiniBandCards", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			PCIInfo: &pci.Info{
				Devices: []*pci.Device{
					{
						Address: "0000:81:00.0",
						Vendor: &pcidb.Vendor{
							ID:   "15b3",
							Name: "Mellanox Technologies",
						},
						Product: &pcidb.Product{
							ID:   "1017",
							Name: "MT27800 Family [ConnectX-5]",
						},
						Class: &pcidb.Class{
							ID:   "02",
							Name: "Network controller",
						},
						Subclass: &pcidb.Subclass{
							ID:   "07",
							Name: "InfiniBand controller",
						},
						Driver: "mlx5_core",
					},
				},
			},
		}

		collector := NewNativePCICollector(mockProvider)
		nics, err := collector.CollectNetworkCards(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(nics) != 1 {
			t.Fatalf("expected 1 NIC, got %d", len(nics))
		}

		if !nics[0].IsInfiniBand {
			t.Error("expected IsInfiniBand to be true for InfiniBand controller")
		}
	})

	t.Run("Error_PCIInfoFails", func(t *testing.T) {
		mockProvider := &MockPCIProvider{
			PCIErr: errors.New("cannot read /sys"),
		}

		collector := NewNativePCICollector(mockProvider)
		_, err := collector.CollectNetworkCards(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

func TestNewNativePCICollector_DefaultProvider(t *testing.T) {
	collector := NewNativePCICollector(nil)

	if collector == nil {
		t.Fatal("expected non-nil collector")
	}

	if collector.provider == nil {
		t.Fatal("expected non-nil provider")
	}
}
