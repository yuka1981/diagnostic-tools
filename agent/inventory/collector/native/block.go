//go:build linux

package native

import (
	"context"
	"fmt"

	"github.com/jaypipes/ghw/pkg/block"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// BlockProvider abstracts ghw block and gopsutil disk functions for testability.
type BlockProvider interface {
	Block(opts ...*option.Option) (*block.Info, error)
	Partitions(all bool) ([]disk.PartitionStat, error)
	Usage(path string) (*disk.UsageStat, error)
}

// RealBlockProvider is the production implementation.
type RealBlockProvider struct{}

func (r *RealBlockProvider) Block(opts ...*option.Option) (*block.Info, error) {
	return block.New(opts...)
}

func (r *RealBlockProvider) Partitions(all bool) ([]disk.PartitionStat, error) {
	return disk.Partitions(all)
}

func (r *RealBlockProvider) Usage(path string) (*disk.UsageStat, error) {
	return disk.Usage(path)
}

// PhysicalDisk represents a physical storage device.
type PhysicalDisk struct {
	Name         string `json:"name"`
	SizeBytes    uint64 `json:"size_bytes"`
	Vendor       string `json:"vendor"`
	Model        string `json:"model"`
	SerialNumber string `json:"serial_number"`
	BusType      string `json:"bus_type"`
	DriveType    string `json:"drive_type"`
	WWN          string `json:"wwn,omitempty"`
}

// NativeBlockCollector collects block device information using ghw and gopsutil.
type NativeBlockCollector struct {
	provider BlockProvider
	opts     []*option.Option
}

// NewNativeBlockCollector creates a new NativeBlockCollector.
// If provider is nil, a default RealBlockProvider is used.
func NewNativeBlockCollector(provider BlockProvider) *NativeBlockCollector {
	if provider == nil {
		provider = &RealBlockProvider{}
	}
	return &NativeBlockCollector{
		provider: provider,
	}
}

// CollectPhysicalDisks gathers physical disk information using ghw.
// This replaces lsblk and smartctl for getting disk model/serial/bus info.
func (c *NativeBlockCollector) CollectPhysicalDisks(_ context.Context) ([]PhysicalDisk, error) {
	blockInfo, err := c.provider.Block(c.opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to get block info: %w", err)
	}

	disks := make([]PhysicalDisk, 0, len(blockInfo.Disks))
	for _, d := range blockInfo.Disks {
		disk := PhysicalDisk{
			Name:         d.Name,
			SizeBytes:    d.SizeBytes,
			Vendor:       d.Vendor,
			Model:        d.Model,
			SerialNumber: d.SerialNumber,
			BusType:      storageControllerToString(d.StorageController),
			DriveType:    driveTypeToString(d.DriveType),
			WWN:          d.WWN,
		}
		disks = append(disks, disk)
	}

	return disks, nil
}

// CollectPartitions gathers partition/mountpoint information using gopsutil.
// This provides filesystem usage stats (total/used/free).
func (c *NativeBlockCollector) CollectPartitions(_ context.Context) ([]model.DiskInfo, error) {
	partitions, err := c.provider.Partitions(false)
	if err != nil {
		return nil, fmt.Errorf("failed to get partitions: %w", err)
	}

	disks := make([]model.DiskInfo, 0, len(partitions))
	for _, p := range partitions {
		// Filter out virtual filesystems
		if shouldSkipFilesystem(p.Fstype) {
			continue
		}

		usage, err := c.provider.Usage(p.Mountpoint)
		if err != nil {
			// Skip partitions we can't get usage for
			continue
		}

		disk := model.DiskInfo{
			Device:     p.Device,
			Mountpoint: p.Mountpoint,
			Fstype:     p.Fstype,
			Total:      usage.Total,
			Used:       usage.Used,
			Free:       usage.Free,
		}
		disks = append(disks, disk)
	}

	return disks, nil
}

// shouldSkipFilesystem returns true for virtual/special filesystems.
func shouldSkipFilesystem(fstype string) bool {
	skipTypes := map[string]bool{
		"tmpfs":      true,
		"overlay":    true,
		"devtmpfs":   true,
		"proc":       true,
		"sysfs":      true,
		"devpts":     true,
		"cgroup":     true,
		"cgroup2":    true,
		"securityfs": true,
		"pstore":     true,
		"efivarfs":   true,
		"bpf":        true,
		"debugfs":    true,
		"tracefs":    true,
		"hugetlbfs":  true,
		"mqueue":     true,
		"fusectl":    true,
		"configfs":   true,
		"squashfs":   true,
	}
	return skipTypes[fstype]
}

// storageControllerToString converts a block.StorageController to a string.
func storageControllerToString(sc block.StorageController) string {
	switch sc {
	case block.StorageControllerIDE:
		return "IDE"
	case block.StorageControllerSCSI:
		return "SCSI"
	case block.StorageControllerNVMe:
		return "NVMe"
	case block.StorageControllerVirtIO:
		return "VirtIO"
	case block.StorageControllerMMC:
		return "MMC"
	case block.StorageControllerLoop:
		return "Loop"
	default:
		return "Unknown"
	}
}

// driveTypeToString converts a block.DriveType to a string.
func driveTypeToString(dt block.DriveType) string {
	switch dt {
	case block.DriveTypeHDD:
		return "HDD"
	case block.DriveTypeSSD:
		return "SSD"
	case block.DriveTypeFDD:
		return "FDD"
	case block.DriveTypeODD:
		return "ODD"
	default:
		return "Unknown"
	}
}
