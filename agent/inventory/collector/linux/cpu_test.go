package linux

import (
	"os"
	"testing"
)

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

	expectedModel := "12th Gen Intel(R) Core(TM) i5-1235U"
	if info.ModelName != expectedModel {
		t.Errorf("expected ModelName %q, got %q", expectedModel, info.ModelName)
	}

	if info.Sockets != 1 {
		t.Errorf("expected Sockets 1, got %d", info.Sockets)
	}

	if info.Cores != 6 {
		t.Errorf("expected Cores 6, got %d", info.Cores)
	}

	if info.Threads != 2 {
		t.Errorf("expected Threads 2, got %d", info.Threads)
	}

	if len(info.Flags) == 0 {
		t.Error("expected Flags to be non-empty")
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

	if info.Sockets != 1 {
		t.Errorf("expected Sockets 1 (default), got %d", info.Sockets)
	}

	if info.Threads != 1 {
		t.Errorf("expected Threads 1, got %d", info.Threads)
	}

	// Since 'cpu cores' is missing, it should default to threads count (1)
	if info.Cores != 1 {
		t.Errorf("expected Cores 1 (default), got %d", info.Cores)
	}
}
