package linux

import (
	"os"
	"strings"
	"testing"
)

func TestParseMemInfo(t *testing.T) {
	file, err := os.Open("testdata/meminfo")
	if err != nil {
		t.Fatalf("failed to open test data: %v", err)
	}
	defer file.Close()

	info, err := ParseMemInfo(file)
	if err != nil {
		t.Fatalf("ParseMemInfo returned error: %v", err)
	}

	// Helper to convert kB to bytes (x1024)
	toByte := func(kb uint64) uint64 {
		return kb * 1024
	}

	t.Run("Total", func(t *testing.T) {
		expected := toByte(8000000)
		if info.Total != expected {
			t.Errorf("expected Total %d, got %d", expected, info.Total)
		}
	})

	t.Run("Free", func(t *testing.T) {
		expected := toByte(1000000)
		if info.Free != expected {
			t.Errorf("expected Free %d, got %d", expected, info.Free)
		}
	})

	t.Run("Available", func(t *testing.T) {
		expected := toByte(2000000)
		if info.Available != expected {
			t.Errorf("expected Available %d, got %d", expected, info.Available)
		}
	})

	t.Run("Buffers", func(t *testing.T) {
		expected := toByte(50000)
		if info.Buffers != expected {
			t.Errorf("expected Buffers %d, got %d", expected, info.Buffers)
		}
	})

	t.Run("Cached", func(t *testing.T) {
		expected := toByte(500000)
		if info.Cached != expected {
			t.Errorf("expected Cached %d, got %d", expected, info.Cached)
		}
	})

	t.Run("SwapTotal", func(t *testing.T) {
		expected := toByte(1000000)
		if info.SwapTotal != expected {
			t.Errorf("expected SwapTotal %d, got %d", expected, info.SwapTotal)
		}
	})

	t.Run("SwapFree", func(t *testing.T) {
		expected := toByte(500000)
		if info.SwapFree != expected {
			t.Errorf("expected SwapFree %d, got %d", expected, info.SwapFree)
		}
	})
}

func TestLinuxMemoryCollector_Collect(t *testing.T) {
	collector := NewLinuxMemoryCollector()
	collector.Path = "testdata/meminfo"

	info, err := collector.Collect()
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if info.Total == 0 {
		t.Error("expected Total memory to be non-zero")
	}
}

func TestParseMemInfo_EmptyInput(t *testing.T) {
	info, err := ParseMemInfo(strings.NewReader(""))
	if err != nil {
		t.Fatalf("ParseMemInfo returned error: %v", err)
	}

	t.Run("EmptyInput_AllZeros", func(t *testing.T) {
		if info.Total != 0 {
			t.Errorf("expected Total 0, got %d", info.Total)
		}
		if info.Free != 0 {
			t.Errorf("expected Free 0, got %d", info.Free)
		}
		if info.Available != 0 {
			t.Errorf("expected Available 0, got %d", info.Available)
		}
	})
}

func TestParseMemInfo_MalformedInput(t *testing.T) {
	malformedInput := `MemTotal: 8000000 kB
MemFree: invalid
this line has no colon
MemAvailable: 2000000 kB
Buffers: 50000 kB
`
	_, err := ParseMemInfo(strings.NewReader(malformedInput))
	
	t.Run("MalformedInput_ReturnsError", func(t *testing.T) {
		if err == nil {
			t.Error("expected error for invalid value, got nil")
		}
		// Verify the error message mentions the problematic key
		if err != nil && !strings.Contains(err.Error(), "MemFree") {
			t.Errorf("expected error to mention 'MemFree', got: %v", err)
		}
	})
}

func TestParseMemInfo_IgnoresUnknownKeys(t *testing.T) {
	inputWithUnknownKeys := `MemTotal: 8000000 kB
UnknownKey: 999999 kB
MemFree: 1000000 kB
AnotherUnknown: invalid
MemAvailable: 2000000 kB
`
	info, err := ParseMemInfo(strings.NewReader(inputWithUnknownKeys))
	if err != nil {
		t.Fatalf("ParseMemInfo returned error: %v", err)
	}

	toByte := func(kb uint64) uint64 {
		return kb * 1024
	}

	t.Run("IgnoresUnknownKeys_ParsesKnownKeys", func(t *testing.T) {
		if info.Total != toByte(8000000) {
			t.Errorf("expected Total %d, got %d", toByte(8000000), info.Total)
		}
		if info.Free != toByte(1000000) {
			t.Errorf("expected Free %d, got %d", toByte(1000000), info.Free)
		}
		if info.Available != toByte(2000000) {
			t.Errorf("expected Available %d, got %d", toByte(2000000), info.Available)
		}
	})
}

func TestParseMemInfo_PartialFields(t *testing.T) {
	partialInput := `MemTotal: 4000000 kB
MemFree: 500000 kB
`
	info, err := ParseMemInfo(strings.NewReader(partialInput))
	if err != nil {
		t.Fatalf("ParseMemInfo returned error: %v", err)
	}

	toByte := func(kb uint64) uint64 {
		return kb * 1024
	}

	t.Run("PartialFields_OnlyProvidedFieldsSet", func(t *testing.T) {
		if info.Total != toByte(4000000) {
			t.Errorf("expected Total %d, got %d", toByte(4000000), info.Total)
		}
		if info.Free != toByte(500000) {
			t.Errorf("expected Free %d, got %d", toByte(500000), info.Free)
		}
		// Other fields should be 0
		if info.Available != 0 {
			t.Errorf("expected Available 0, got %d", info.Available)
		}
		if info.Buffers != 0 {
			t.Errorf("expected Buffers 0, got %d", info.Buffers)
		}
		if info.Cached != 0 {
			t.Errorf("expected Cached 0, got %d", info.Cached)
		}
	})
}

func TestNewLinuxMemoryCollector(t *testing.T) {
	collector := NewLinuxMemoryCollector()

	t.Run("DefaultPath", func(t *testing.T) {
		expectedPath := "/proc/meminfo"
		if collector.Path != expectedPath {
			t.Errorf("expected Path %q, got %q", expectedPath, collector.Path)
		}
	})
}

func TestLinuxMemoryCollector_Collect_FileNotFound(t *testing.T) {
	collector := NewLinuxMemoryCollector()
	collector.Path = "testdata/nonexistent"

	_, err := collector.Collect()
	if err == nil {
		t.Error("expected error when file not found, got nil")
	}
}

