//go:build linux

package native

import (
	"context"
	"errors"
	"testing"

	"github.com/jaypipes/ghw/pkg/block"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/shirou/gopsutil/v3/disk"
)

// MockBlockProvider is a mock implementation for testing.
type MockBlockProvider struct {
	BlockInfo      *block.Info
	PartitionStats []disk.PartitionStat
	UsageStats     map[string]*disk.UsageStat
	BlockErr       error
	PartErr        error
	UsageErrMap    map[string]error
}

func (m *MockBlockProvider) Block(opts ...*option.Option) (*block.Info, error) {
	return m.BlockInfo, m.BlockErr
}

func (m *MockBlockProvider) Partitions(all bool) ([]disk.PartitionStat, error) {
	return m.PartitionStats, m.PartErr
}

func (m *MockBlockProvider) Usage(path string) (*disk.UsageStat, error) {
	if m.UsageErrMap != nil {
		if err, ok := m.UsageErrMap[path]; ok {
			return nil, err
		}
	}
	if m.UsageStats != nil {
		if stat, ok := m.UsageStats[path]; ok {
			return stat, nil
		}
	}
	return nil, errors.New("not found")
}

func TestNativeBlockCollector_CollectPhysicalDisks(t *testing.T) {
	t.Run("Success_NVMeDisks", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			BlockInfo: &block.Info{
				TotalSizeBytes: 2000000000000, // 2TB
				Disks: []*block.Disk{
					{
						Name:              "nvme0n1",
						SizeBytes:         1000000000000,
						DriveType:         block.DriveTypeSSD,
						StorageController: block.StorageControllerNVMe,
						Vendor:            "Samsung",
						Model:             "970 EVO Plus",
						SerialNumber:      "S4EWNX0M123456",
					},
					{
						Name:              "sda",
						SizeBytes:         1000000000000,
						DriveType:         block.DriveTypeHDD,
						StorageController: block.StorageControllerSCSI,
						Vendor:            "Seagate",
						Model:             "ST1000DM003",
						SerialNumber:      "Z1234567",
					},
				},
			},
		}

		collector := NewNativeBlockCollector(mockProvider)
		disks, err := collector.CollectPhysicalDisks(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(disks) != 2 {
			t.Fatalf("expected 2 disks, got %d", len(disks))
		}

		// Check NVMe disk
		if disks[0].Name != "nvme0n1" {
			t.Errorf("expected Name 'nvme0n1', got %q", disks[0].Name)
		}
		if disks[0].Vendor != "Samsung" {
			t.Errorf("expected Vendor 'Samsung', got %q", disks[0].Vendor)
		}
		if disks[0].Model != "970 EVO Plus" {
			t.Errorf("expected Model '970 EVO Plus', got %q", disks[0].Model)
		}
		if disks[0].SerialNumber != "S4EWNX0M123456" {
			t.Errorf("expected SerialNumber 'S4EWNX0M123456', got %q", disks[0].SerialNumber)
		}
		if disks[0].BusType != "NVMe" {
			t.Errorf("expected BusType 'NVMe', got %q", disks[0].BusType)
		}
		if disks[0].DriveType != "SSD" {
			t.Errorf("expected DriveType 'SSD', got %q", disks[0].DriveType)
		}
	})

	t.Run("Error_BlockInfoFails", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			BlockErr: errors.New("permission denied"),
		}

		collector := NewNativeBlockCollector(mockProvider)
		_, err := collector.CollectPhysicalDisks(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("Success_EmptyDisks", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			BlockInfo: &block.Info{
				Disks: []*block.Disk{},
			},
		}

		collector := NewNativeBlockCollector(mockProvider)
		disks, err := collector.CollectPhysicalDisks(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(disks) != 0 {
			t.Errorf("expected 0 disks, got %d", len(disks))
		}
	})
}

func TestNativeBlockCollector_CollectPartitions(t *testing.T) {
	t.Run("Success_PartitionUsage", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			PartitionStats: []disk.PartitionStat{
				{
					Device:     "/dev/nvme0n1p1",
					Mountpoint: "/",
					Fstype:     "ext4",
				},
				{
					Device:     "/dev/nvme0n1p2",
					Mountpoint: "/home",
					Fstype:     "ext4",
				},
			},
			UsageStats: map[string]*disk.UsageStat{
				"/": {
					Total: 500000000000,
					Used:  100000000000,
					Free:  400000000000,
				},
				"/home": {
					Total: 500000000000,
					Used:  200000000000,
					Free:  300000000000,
				},
			},
		}

		collector := NewNativeBlockCollector(mockProvider)
		disks, err := collector.CollectPartitions(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(disks) != 2 {
			t.Fatalf("expected 2 partitions, got %d", len(disks))
		}

		if disks[0].Device != "/dev/nvme0n1p1" {
			t.Errorf("expected Device '/dev/nvme0n1p1', got %q", disks[0].Device)
		}
		if disks[0].Mountpoint != "/" {
			t.Errorf("expected Mountpoint '/', got %q", disks[0].Mountpoint)
		}
		if disks[0].Fstype != "ext4" {
			t.Errorf("expected Fstype 'ext4', got %q", disks[0].Fstype)
		}
		if disks[0].Total != 500000000000 {
			t.Errorf("expected Total 500000000000, got %d", disks[0].Total)
		}
		if disks[0].Used != 100000000000 {
			t.Errorf("expected Used 100000000000, got %d", disks[0].Used)
		}
		if disks[0].Free != 400000000000 {
			t.Errorf("expected Free 400000000000, got %d", disks[0].Free)
		}
	})

	t.Run("Success_FilteredPartitions", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			PartitionStats: []disk.PartitionStat{
				{Device: "/dev/sda1", Mountpoint: "/", Fstype: "ext4"},
				{Device: "tmpfs", Mountpoint: "/tmp", Fstype: "tmpfs"},
				{Device: "overlay", Mountpoint: "/var/lib/docker/overlay2", Fstype: "overlay"},
			},
			UsageStats: map[string]*disk.UsageStat{
				"/": {Total: 100000000000},
			},
		}

		collector := NewNativeBlockCollector(mockProvider)
		disks, err := collector.CollectPartitions(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		// Should only have the ext4 partition, not tmpfs or overlay
		if len(disks) != 1 {
			t.Errorf("expected 1 partition (filtered), got %d", len(disks))
		}
	})

	t.Run("Error_PartitionsFails", func(t *testing.T) {
		mockProvider := &MockBlockProvider{
			PartErr: errors.New("cannot read partitions"),
		}

		collector := NewNativeBlockCollector(mockProvider)
		_, err := collector.CollectPartitions(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})
}

func TestNewNativeBlockCollector_DefaultProvider(t *testing.T) {
	collector := NewNativeBlockCollector(nil)

	if collector == nil {
		t.Fatal("expected non-nil collector")
	}

	if collector.provider == nil {
		t.Fatal("expected non-nil provider")
	}
}
