package linux

import (
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

	info, err := collector.Collect()
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

	_, err := collector.Collect()
	if err == nil {
		t.Error("expected error when file not found, got nil")
	}
}

