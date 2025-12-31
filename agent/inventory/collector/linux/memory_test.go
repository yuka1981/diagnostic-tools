package linux

import (
	"os"
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

	if info.Total != toByte(8000000) {
		t.Errorf("expected Total %d, got %d", toByte(8000000), info.Total)
	}
	if info.Free != toByte(1000000) {
		t.Errorf("expected Free %d, got %d", toByte(1000000), info.Free)
	}
	if info.Available != toByte(2000000) {
		t.Errorf("expected Available %d, got %d", toByte(2000000), info.Available)
	}
	if info.Buffers != toByte(50000) {
		t.Errorf("expected Buffers %d, got %d", toByte(50000), info.Buffers)
	}
	if info.Cached != toByte(500000) {
		t.Errorf("expected Cached %d, got %d", toByte(500000), info.Cached)
	}
	if info.SwapTotal != toByte(1000000) {
		t.Errorf("expected SwapTotal %d, got %d", toByte(1000000), info.SwapTotal)
	}
	if info.SwapFree != toByte(500000) {
		t.Errorf("expected SwapFree %d, got %d", toByte(500000), info.SwapFree)
	}
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

