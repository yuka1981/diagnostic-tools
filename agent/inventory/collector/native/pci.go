//go:build linux

package native

import (
	"context"
	"fmt"

	"github.com/jaypipes/ghw/pkg/gpu"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/jaypipes/ghw/pkg/pci"
)

// PCIProvider abstracts ghw PCI and GPU functions for testability.
type PCIProvider interface {
	PCI(opts ...*option.Option) (*pci.Info, error)
	GPU(opts ...*option.Option) (*gpu.Info, error)
}

// RealPCIProvider is the production implementation.
type RealPCIProvider struct{}

func (r *RealPCIProvider) PCI(opts ...*option.Option) (*pci.Info, error) {
	return pci.New(opts...)
}

func (r *RealPCIProvider) GPU(opts ...*option.Option) (*gpu.Info, error) {
	return gpu.New(opts...)
}

// GPUDevice represents a GPU/accelerator device.
type GPUDevice struct {
	PCIAddress string `json:"pci_address"`
	Vendor     string `json:"vendor"`
	VendorID   string `json:"vendor_id"`
	Product    string `json:"product"`
	ProductID  string `json:"product_id"`
	Driver     string `json:"driver"`
	NUMANode   int    `json:"numa_node"`
}

// NetworkCard represents a physical network interface card.
type NetworkCard struct {
	PCIAddress   string `json:"pci_address"`
	Vendor       string `json:"vendor"`
	VendorID     string `json:"vendor_id"`
	Product      string `json:"product"`
	ProductID    string `json:"product_id"`
	Driver       string `json:"driver"`
	IsInfiniBand bool   `json:"is_infiniband"`
	NUMANode     int    `json:"numa_node"`
}

// NativePCICollector collects PCI device information using ghw.
type NativePCICollector struct {
	provider PCIProvider
	opts     []*option.Option
}

// NewNativePCICollector creates a new NativePCICollector.
// If provider is nil, a default RealPCIProvider is used.
func NewNativePCICollector(provider PCIProvider) *NativePCICollector {
	if provider == nil {
		provider = &RealPCIProvider{}
	}
	return &NativePCICollector{
		provider: provider,
	}
}

// CollectGPUs gathers GPU/accelerator information using ghw.
// This identifies NVIDIA, AMD, and Intel GPUs via PCI class codes.
func (c *NativePCICollector) CollectGPUs(_ context.Context) ([]GPUDevice, error) {
	gpuInfo, err := c.provider.GPU(c.opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to get GPU info: %w", err)
	}

	gpus := make([]GPUDevice, 0, len(gpuInfo.GraphicsCards))
	for _, card := range gpuInfo.GraphicsCards {
		gpuDev := GPUDevice{
			PCIAddress: card.Address,
		}

		if card.DeviceInfo != nil {
			if card.DeviceInfo.Vendor != nil {
				gpuDev.Vendor = card.DeviceInfo.Vendor.Name
				gpuDev.VendorID = card.DeviceInfo.Vendor.ID
			}
			if card.DeviceInfo.Product != nil {
				gpuDev.Product = card.DeviceInfo.Product.Name
				gpuDev.ProductID = card.DeviceInfo.Product.ID
			}
			gpuDev.Driver = card.DeviceInfo.Driver
		}

		if card.Node != nil {
			gpuDev.NUMANode = card.Node.ID
		} else {
			gpuDev.NUMANode = -1
		}

		gpus = append(gpus, gpuDev)
	}

	return gpus, nil
}

// CollectNetworkCards gathers network interface card information using ghw.
// This identifies NICs including InfiniBand HCAs via PCI class codes.
func (c *NativePCICollector) CollectNetworkCards(_ context.Context) ([]NetworkCard, error) {
	pciInfo, err := c.provider.PCI(c.opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to get PCI info: %w", err)
	}

	nics := make([]NetworkCard, 0)
	for _, device := range pciInfo.Devices {
		// Filter for network controllers (class 02)
		if device.Class == nil || device.Class.ID != "02" {
			continue
		}

		nic := NetworkCard{
			PCIAddress: device.Address,
			Driver:     device.Driver,
		}

		if device.Vendor != nil {
			nic.Vendor = device.Vendor.Name
			nic.VendorID = device.Vendor.ID
		}

		if device.Product != nil {
			nic.Product = device.Product.Name
			nic.ProductID = device.Product.ID
		}

		// Check for InfiniBand (subclass 07)
		if device.Subclass != nil && device.Subclass.ID == "07" {
			nic.IsInfiniBand = true
		}

		if device.Node != nil {
			nic.NUMANode = device.Node.ID
		} else {
			nic.NUMANode = -1
		}

		nics = append(nics, nic)
	}

	return nics, nil
}
