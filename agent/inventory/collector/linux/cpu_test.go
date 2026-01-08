package linux

import (
	"context"
	"os"
	"strings"
	"testing"
)

const testdataNonExistent = "testdata/nonexistent"

func TestParseCPUInfo(t *testing.T) {
	file, err := os.Open("testdata/cpuinfo")
	if err != nil {
		t.Fatalf("failed to open test data: %v", err)
	}
	defer file.Close()

	info, err := ParseCPUInfo(file)
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("ModelName", func(t *testing.T) {
		expectedModel := "12th Gen Intel(R) Core(TM) i5-1235U"
		if info.ModelName != expectedModel {
			t.Errorf("expected ModelName %q, got %q", expectedModel, info.ModelName)
		}
	})

	t.Run("Sockets", func(t *testing.T) {
		if info.Sockets != 1 {
			t.Errorf("expected Sockets 1, got %d", info.Sockets)
		}
	})

	t.Run("Cores", func(t *testing.T) {
		if info.Cores != 6 {
			t.Errorf("expected Cores 6, got %d", info.Cores)
		}
	})

	t.Run("Threads", func(t *testing.T) {
		if info.Threads != 2 {
			t.Errorf("expected Threads 2, got %d", info.Threads)
		}
	})

	t.Run("Flags", func(t *testing.T) {
		if len(info.Flags) == 0 {
			t.Fatal("expected Flags to be non-empty")
		}

		expectedFlag := "fpu"
		found := false
		for _, f := range info.Flags {
			if f == expectedFlag {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("expected flag %q not found", expectedFlag)
		}
	})
}

func TestLinuxCPUCollector_Collect(t *testing.T) {
	collector := NewLinuxCPUCollector()
	collector.Path = "testdata/cpuinfo"

	info, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if info.ModelName == "" {
		t.Error("expected ModelName to be set")
	}
}

func TestParseCPUInfo_NoPhysicalID(t *testing.T) {
	file, err := os.Open("testdata/cpuinfo_minimal")
	if err != nil {
		t.Fatalf("failed to open test data: %v", err)
	}
	defer file.Close()

	info, err := ParseCPUInfo(file)
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("Sockets_DefaultsToOne", func(t *testing.T) {
		if info.Sockets != 1 {
			t.Errorf("expected Sockets 1 (default), got %d", info.Sockets)
		}
	})

	t.Run("Threads", func(t *testing.T) {
		if info.Threads != 1 {
			t.Errorf("expected Threads 1, got %d", info.Threads)
		}
	})

	t.Run("Cores_FallbackToThreads", func(t *testing.T) {
		// Since 'cpu cores' is missing, it should default to threads count (1)
		if info.Cores != 1 {
			t.Errorf("expected Cores 1 (default), got %d", info.Cores)
		}
	})
}

func TestParseCPUInfo_EmptyInput(t *testing.T) {
	info, err := ParseCPUInfo(strings.NewReader(""))
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("EmptyInput_DefaultValues", func(t *testing.T) {
		if info.Sockets != 1 {
			t.Errorf("expected Sockets 1 (default), got %d", info.Sockets)
		}
		if info.Cores != 0 {
			t.Errorf("expected Cores 0, got %d", info.Cores)
		}
		if info.Threads != 0 {
			t.Errorf("expected Threads 0, got %d", info.Threads)
		}
		if info.ModelName != "" {
			t.Errorf("expected empty ModelName, got %q", info.ModelName)
		}
		if len(info.Flags) != 0 {
			t.Errorf("expected empty Flags, got %v", info.Flags)
		}
	})
}

func TestParseCPUInfo_MalformedInput(t *testing.T) {
	malformedInput := `processor: 0
model name: Test CPU
this line has no colon
flags: fpu vme
`
	info, err := ParseCPUInfo(strings.NewReader(malformedInput))
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("MalformedInput_PartialParsing", func(t *testing.T) {
		if info.ModelName != "Test CPU" {
			t.Errorf("expected ModelName 'Test CPU', got %q", info.ModelName)
		}
		if info.Threads != 1 {
			t.Errorf("expected Threads 1, got %d", info.Threads)
		}
		if len(info.Flags) != 2 {
			t.Errorf("expected 2 flags, got %d", len(info.Flags))
		}
	})
}

func TestParseCPUInfo_MultiplePhysicalIDs(t *testing.T) {
	multiSocketInput := `processor: 0
model name: Intel Xeon
physical id: 0
cpu cores: 4

processor: 1
model name: Intel Xeon
physical id: 1
cpu cores: 4
`
	info, err := ParseCPUInfo(strings.NewReader(multiSocketInput))
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("MultiSocket_SocketCount", func(t *testing.T) {
		if info.Sockets != 2 {
			t.Errorf("expected Sockets 2, got %d", info.Sockets)
		}
	})

	t.Run("MultiSocket_CoreCount", func(t *testing.T) {
		if info.Cores != 8 {
			t.Errorf("expected Cores 8 (4 per socket), got %d", info.Cores)
		}
	})

	t.Run("MultiSocket_ThreadCount", func(t *testing.T) {
		if info.Threads != 2 {
			t.Errorf("expected Threads 2, got %d", info.Threads)
		}
	})
}

func TestParseCPUInfo_AArch64(t *testing.T) {
	file, err := os.Open("testdata/cpuinfo_aarch64")
	if err != nil {
		t.Fatalf("failed to open test data: %v", err)
	}
	defer file.Close()

	info, err := ParseCPUInfo(file)
	if err != nil {
		t.Fatalf("ParseCPUInfo returned error: %v", err)
	}

	t.Run("Architecture", func(t *testing.T) {
		if info.Architecture != "8" {
			t.Errorf("expected Architecture '8', got %q", info.Architecture)
		}
	})

	t.Run("VendorID", func(t *testing.T) {
		if info.VendorID != "0x41" {
			t.Errorf("expected VendorID '0x41', got %q", info.VendorID)
		}
	})

	t.Run("Topology", func(t *testing.T) {
		if info.CPUs != 2 {
			t.Errorf("expected CPUs 2, got %d", info.CPUs)
		}
		if info.ThreadsPerCore != 1 {
			t.Errorf("expected ThreadsPerCore 1, got %d", info.ThreadsPerCore)
		}
		if info.CoresPerSocket != 2 {
			t.Errorf("expected CoresPerSocket 2, got %d", info.CoresPerSocket)
		}
	})

	t.Run("ModelName_Fallback", func(t *testing.T) {
		if info.ModelName == "" {
			t.Error("expected ModelName to be set (even if fallback)")
		}
		if !strings.Contains(info.ModelName, "AArch64") && !strings.Contains(info.ModelName, "0x41") {
			t.Errorf("expected ModelName to contain 'AArch64' or implementer ID, got %q", info.ModelName)
		}
	})

	t.Run("Sockets_DefaultsToOne", func(t *testing.T) {
		if info.Sockets != 1 {
			t.Errorf("expected Sockets 1 (default), got %d", info.Sockets)
		}
	})

	t.Run("Threads", func(t *testing.T) {
		if info.Threads != 2 {
			t.Errorf("expected Threads 2, got %d", info.Threads)
		}
	})

	t.Run("Cores_FallbackToThreads", func(t *testing.T) {
		if info.Cores != 2 {
			t.Errorf("expected Cores 2 (default), got %d", info.Cores)
		}
	})

	t.Run("Flags_Features", func(t *testing.T) {
		if len(info.Flags) == 0 {
			t.Fatal("expected Flags to be non-empty (from Features)")
		}

		expectedFlag := "asimd"
		found := false
		for _, f := range info.Flags {
			if f == expectedFlag {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("expected flag %q not found in Features", expectedFlag)
		}
	})
}

func TestParseCacheSize(t *testing.T) {
	tests := []struct {
		input  string
		want   uint64
		wantOk bool
	}{
		{"1024", 1024, true},
		{"1K", 1024, true},
		{"1M", 1024 * 1024, true},
		{"1G", 1024 * 1024 * 1024, true},
		{"invalid", 0, false},
	}

	for _, tt := range tests {
		got, ok := parseCacheSize(tt.input)
		if ok != tt.wantOk {
			t.Errorf("parseCacheSize(%q) ok = %v, want %v", tt.input, ok, tt.wantOk)
		}
		if got != tt.want {
			t.Errorf("parseCacheSize(%q) = %d, want %d", tt.input, got, tt.want)
		}
	}
}

func TestFormatCacheString(t *testing.T) {
	tests := []struct {
		want  string
		bytes uint64
		count int
	}{
		{"", 0, 0},
		{"2.0 GiB (1 instance)", 1024 * 1024 * 1024 * 2, 1},
		{"2.0 MiB (2 instances)", 1024 * 1024 * 2, 2},
		{"2.0 KiB (1 instance)", 1024 * 2, 1},
		{"512 B (1 instance)", 512, 1},
	}

	for _, tt := range tests {
		got := formatCacheString(tt.bytes, tt.count)
		if got != tt.want {
			t.Errorf("formatCacheString(%d, %d) = %q, want %q", tt.bytes, tt.count, got, tt.want)
		}
	}
}

func TestNewLinuxCPUCollector(t *testing.T) {
	collector := NewLinuxCPUCollector()

	t.Run("DefaultPath", func(t *testing.T) {
		expectedPath := "/proc/cpuinfo"
		if collector.Path != expectedPath {
			t.Errorf("expected Path %q, got %q", expectedPath, collector.Path)
		}
	})
}

func TestLinuxCPUCollector_Collect_FileNotFound(t *testing.T) {
	collector := NewLinuxCPUCollector()
	collector.Path = testdataNonExistent

	_, err := collector.Collect(context.Background())
	if err == nil {
		t.Error("expected error when file not found, got nil")
	}
}