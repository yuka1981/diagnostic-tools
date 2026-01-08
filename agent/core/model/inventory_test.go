package model

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func TestHostInfo_JSON(t *testing.T) {
	original := HostInfo{
		Hostname:        "test-host",
		OS:              "linux",
		Platform:        "ubuntu",
		PlatformFamily:  "debian",
		PlatformVersion: "22.04",
		Kernel:          "5.15.0-101-generic",
		Arch:            "x86_64",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal HostInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded HostInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal HostInfo: %v", err)
		}

		if decoded.Hostname != original.Hostname {
			t.Errorf("expected Hostname %q, got %q", original.Hostname, decoded.Hostname)
		}
		if decoded.OS != original.OS {
			t.Errorf("expected OS %q, got %q", original.OS, decoded.OS)
		}
		if decoded.Platform != original.Platform {
			t.Errorf("expected Platform %q, got %q", original.Platform, decoded.Platform)
		}
		if decoded.Kernel != original.Kernel {
			t.Errorf("expected Kernel %q, got %q", original.Kernel, decoded.Kernel)
		}
		if decoded.Arch != original.Arch {
			t.Errorf("expected Arch %q, got %q", original.Arch, decoded.Arch)
		}
	})
}

func TestCPUInfo_JSON(t *testing.T) {
	original := CPUInfo{
		ModelName: "Intel(R) Core(TM) i7-9700K",
		Flags:     []string{"fpu", "vme", "de", "pse", "tsc"},
		Cores:     8,
		Threads:   8,
		Sockets:   1,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal CPUInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded CPUInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal CPUInfo: %v", err)
		}

		if decoded.ModelName != original.ModelName {
			t.Errorf("expected ModelName %q, got %q", original.ModelName, decoded.ModelName)
		}
		if decoded.Cores != original.Cores {
			t.Errorf("expected Cores %d, got %d", original.Cores, decoded.Cores)
		}
		if decoded.Threads != original.Threads {
			t.Errorf("expected Threads %d, got %d", original.Threads, decoded.Threads)
		}
		if decoded.Sockets != original.Sockets {
			t.Errorf("expected Sockets %d, got %d", original.Sockets, decoded.Sockets)
		}
		if len(decoded.Flags) != len(original.Flags) {
			t.Errorf("expected %d flags, got %d", len(original.Flags), len(decoded.Flags))
		}
	})
}

func TestMemoryInfo_JSON(t *testing.T) {
	original := MemoryInfo{
		Total:     16000000000,
		Free:      8000000000,
		Available: 10000000000,
		Buffers:   500000000,
		Cached:    2000000000,
		SwapTotal: 4000000000,
		SwapFree:  3000000000,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal MemoryInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded MemoryInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal MemoryInfo: %v", err)
		}

		if decoded.Total != original.Total {
			t.Errorf("expected Total %d, got %d", original.Total, decoded.Total)
		}
		if decoded.Free != original.Free {
			t.Errorf("expected Free %d, got %d", original.Free, decoded.Free)
		}
		if decoded.Available != original.Available {
			t.Errorf("expected Available %d, got %d", original.Available, decoded.Available)
		}
		if decoded.Buffers != original.Buffers {
			t.Errorf("expected Buffers %d, got %d", original.Buffers, decoded.Buffers)
		}
		if decoded.Cached != original.Cached {
			t.Errorf("expected Cached %d, got %d", original.Cached, decoded.Cached)
		}
		if decoded.SwapTotal != original.SwapTotal {
			t.Errorf("expected SwapTotal %d, got %d", original.SwapTotal, decoded.SwapTotal)
		}
		if decoded.SwapFree != original.SwapFree {
			t.Errorf("expected SwapFree %d, got %d", original.SwapFree, decoded.SwapFree)
		}
	})
}

func TestDiskInfo_JSON(t *testing.T) {
	original := DiskInfo{
		Device:     "/dev/sda1",
		Mountpoint: "/",
		Fstype:     "ext4",
		Total:      500000000000,
		Used:       250000000000,
		Free:       250000000000,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal DiskInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded DiskInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal DiskInfo: %v", err)
		}

		if decoded.Device != original.Device {
			t.Errorf("expected Device %q, got %q", original.Device, decoded.Device)
		}
		if decoded.Mountpoint != original.Mountpoint {
			t.Errorf("expected Mountpoint %q, got %q", original.Mountpoint, decoded.Mountpoint)
		}
		if decoded.Fstype != original.Fstype {
			t.Errorf("expected Fstype %q, got %q", original.Fstype, decoded.Fstype)
		}
		if decoded.Total != original.Total {
			t.Errorf("expected Total %d, got %d", original.Total, decoded.Total)
		}
		if decoded.Used != original.Used {
			t.Errorf("expected Used %d, got %d", original.Used, decoded.Used)
		}
		if decoded.Free != original.Free {
			t.Errorf("expected Free %d, got %d", original.Free, decoded.Free)
		}
	})
}

func TestNetInfo_JSON(t *testing.T) {
	original := NetInfo{
		Name:        "eth0",
		MacAddress:  "00:11:22:33:44:55",
		IPAddresses: []string{"192.168.1.100", "fe80::1"},
		Speed:       1000,
		Up:          true,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal NetInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded NetInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal NetInfo: %v", err)
		}

		if decoded.Name != original.Name {
			t.Errorf("expected Name %q, got %q", original.Name, decoded.Name)
		}
		if decoded.MacAddress != original.MacAddress {
			t.Errorf("expected MacAddress %q, got %q", original.MacAddress, decoded.MacAddress)
		}
		if decoded.Speed != original.Speed {
			t.Errorf("expected Speed %d, got %d", original.Speed, decoded.Speed)
		}
		if decoded.Up != original.Up {
			t.Errorf("expected Up %v, got %v", original.Up, decoded.Up)
		}
		if len(decoded.IPAddresses) != len(original.IPAddresses) {
			t.Errorf("expected %d IP addresses, got %d", len(original.IPAddresses), len(decoded.IPAddresses))
		}
	})
}

func TestNodeState_JSON(t *testing.T) {
	capturedAt := time.Now().UTC().Truncate(time.Second)
	original := NodeState{
		CapturedAt: capturedAt,
		Host: &HostInfo{
			Hostname: "test-host",
			OS:       "linux",
			Platform: "ubuntu",
			Arch:     "x86_64",
		},
		CPU: &CPUInfo{
			ModelName: "Intel Core i7",
			Cores:     8,
			Threads:   16,
			Sockets:   1,
			Flags:     []string{"fpu", "vme"},
		},
		Memory: &MemoryInfo{
			Total:     16000000000,
			Free:      8000000000,
			Available: 10000000000,
		},

		Disks: []DiskInfo{
			{
				Device:     "/dev/sda1",
				Mountpoint: "/",
				Fstype:     "ext4",
				Total:      500000000000,
			},
		},
		Network: []NetInfo{
			{
				Name:        "eth0",
				MacAddress:  "00:11:22:33:44:55",
				IPAddresses: []string{"192.168.1.100"},
				Up:          true,
			},
		},
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal NodeState: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded NodeState
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal NodeState: %v", err)
		}

		if !decoded.CapturedAt.Equal(original.CapturedAt) {
			t.Errorf("expected CapturedAt %v, got %v", original.CapturedAt, decoded.CapturedAt)
		}
		if decoded.Host.Hostname != original.Host.Hostname {
			t.Errorf("expected Host.Hostname %q, got %q", original.Host.Hostname, decoded.Host.Hostname)
		}
		if decoded.CPU.ModelName != original.CPU.ModelName {
			t.Errorf("expected CPU.ModelName %q, got %q", original.CPU.ModelName, decoded.CPU.ModelName)
		}
		if decoded.Memory.Total != original.Memory.Total {
			t.Errorf("expected Memory.Total %d, got %d", original.Memory.Total, decoded.Memory.Total)
		}
		if len(decoded.Disks) != len(original.Disks) {
			t.Errorf("expected %d disks, got %d", len(original.Disks), len(decoded.Disks))
		}
		if len(decoded.Network) != len(original.Network) {
			t.Errorf("expected %d network interfaces, got %d", len(original.Network), len(decoded.Network))
		}
	})

	t.Run("RoundTrip", func(t *testing.T) {
		// Marshal to JSON
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		// Unmarshal back
		var decoded NodeState
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}

		// Marshal again
		data2, err := json.Marshal(decoded)
		if err != nil {
			t.Fatalf("failed to marshal decoded: %v", err)
		}

		// Compare JSON strings
		if !bytes.Equal(data, data2) {
			t.Error("round-trip JSON does not match")
		}
	})
}
