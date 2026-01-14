//go:build linux

package native

import (
	"context"
	"errors"
	"log"
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// MockCPUCollector is a mock for NativeCPUCollector.
type MockCPUCollector struct {
	Result *model.CPUInfo
	Err    error
}

func (m *MockCPUCollector) Collect(ctx context.Context) (*model.CPUInfo, error) {
	return m.Result, m.Err
}

// MockLegacyCPUCollector is a mock for legacy CPU collector.
type MockLegacyCPUCollector struct {
	Result *model.CPUInfo
	Err    error
}

func (m *MockLegacyCPUCollector) Collect(ctx context.Context) (*model.CPUInfo, error) {
	return m.Result, m.Err
}

func TestHybridCPUCollector_Collect(t *testing.T) {
	t.Run("Success_NativeWorks", func(t *testing.T) {
		nativeResult := &model.CPUInfo{
			ModelName: "Intel Xeon (native)",
			Cores:     16,
		}
		native := &MockCPUCollector{Result: nativeResult}
		legacy := &MockLegacyCPUCollector{Result: &model.CPUInfo{ModelName: "Intel Xeon (legacy)"}}

		hybrid := NewHybridCPUCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if result.ModelName != "Intel Xeon (native)" {
			t.Errorf("expected native result, got %q", result.ModelName)
		}
	})

	t.Run("Fallback_NativeFails", func(t *testing.T) {
		native := &MockCPUCollector{Err: errors.New("cannot read /sys")}
		legacyResult := &model.CPUInfo{
			ModelName: "Intel Xeon (legacy)",
			Cores:     16,
		}
		legacy := &MockLegacyCPUCollector{Result: legacyResult}

		// Capture log output
		var logOutput strings.Builder
		logger := log.New(&logOutput, "", 0)

		hybrid := NewHybridCPUCollector(native, legacy, logger)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (fallback should work), got %v", err)
		}

		if result.ModelName != "Intel Xeon (legacy)" {
			t.Errorf("expected legacy result, got %q", result.ModelName)
		}

		// Check that warning was logged
		if !strings.Contains(logOutput.String(), "falling back") {
			t.Errorf("expected fallback warning in log, got %q", logOutput.String())
		}
	})

	t.Run("Error_BothFail", func(t *testing.T) {
		native := &MockCPUCollector{Err: errors.New("native failed")}
		legacy := &MockLegacyCPUCollector{Err: errors.New("legacy failed")}

		hybrid := NewHybridCPUCollector(native, legacy, nil)
		_, err := hybrid.Collect(context.Background())

		if err == nil {
			t.Fatal("expected error when both collectors fail")
		}
	})
}

// MockMemoryCollector mocks for memory collection.
type MockMemoryCollector struct {
	Result *model.MemoryInfo
	Err    error
}

func (m *MockMemoryCollector) Collect(ctx context.Context) (*model.MemoryInfo, error) {
	return m.Result, m.Err
}

type MockLegacyMemoryCollector struct {
	Result *model.MemoryInfo
	Err    error
}

func (m *MockLegacyMemoryCollector) Collect(ctx context.Context) (*model.MemoryInfo, error) {
	return m.Result, m.Err
}

func TestHybridMemoryCollector_Collect(t *testing.T) {
	t.Run("Success_NativeWorks", func(t *testing.T) {
		nativeResult := &model.MemoryInfo{Total: 137438953472}
		native := &MockMemoryCollector{Result: nativeResult}
		legacy := &MockLegacyMemoryCollector{Result: &model.MemoryInfo{Total: 1}}

		hybrid := NewHybridMemoryCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if result.Total != 137438953472 {
			t.Errorf("expected native Total, got %d", result.Total)
		}
	})

	t.Run("Fallback_NativeFails", func(t *testing.T) {
		native := &MockMemoryCollector{Err: errors.New("cannot read /proc/meminfo")}
		legacyResult := &model.MemoryInfo{Total: 64000000000}
		legacy := &MockLegacyMemoryCollector{Result: legacyResult}

		hybrid := NewHybridMemoryCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (fallback), got %v", err)
		}

		if result.Total != 64000000000 {
			t.Errorf("expected legacy Total, got %d", result.Total)
		}
	})
}

// MockDiskCollector mocks for disk collection.
type MockDiskCollector struct {
	Result []model.DiskInfo
	Err    error
}

func (m *MockDiskCollector) Collect(ctx context.Context) ([]model.DiskInfo, error) {
	return m.Result, m.Err
}

type MockLegacyDiskCollector struct {
	Result []model.DiskInfo
	Err    error
}

func (m *MockLegacyDiskCollector) Collect(ctx context.Context) ([]model.DiskInfo, error) {
	return m.Result, m.Err
}

func TestHybridDiskCollector_Collect(t *testing.T) {
	t.Run("Success_NativeWorks", func(t *testing.T) {
		nativeResult := []model.DiskInfo{{Device: "/dev/nvme0n1p1", Total: 500000000000}}
		native := &MockDiskCollector{Result: nativeResult}
		legacy := &MockLegacyDiskCollector{Result: []model.DiskInfo{{Device: "/dev/sda1"}}}

		hybrid := NewHybridDiskCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if result[0].Device != "/dev/nvme0n1p1" {
			t.Errorf("expected native result, got %q", result[0].Device)
		}
	})

	t.Run("Fallback_NativeFails", func(t *testing.T) {
		native := &MockDiskCollector{Err: errors.New("native failed")}
		legacyResult := []model.DiskInfo{{Device: "/dev/sda1"}}
		legacy := &MockLegacyDiskCollector{Result: legacyResult}

		hybrid := NewHybridDiskCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (fallback), got %v", err)
		}

		if result[0].Device != "/dev/sda1" {
			t.Errorf("expected legacy result, got %q", result[0].Device)
		}
	})
}

// MockNetCollector mocks for network collection.
type MockNetCollector struct {
	Result []model.NetInfo
	Err    error
}

func (m *MockNetCollector) Collect(ctx context.Context) ([]model.NetInfo, error) {
	return m.Result, m.Err
}

type MockLegacyNetCollector struct {
	Result []model.NetInfo
	Err    error
}

func (m *MockLegacyNetCollector) Collect(ctx context.Context) ([]model.NetInfo, error) {
	return m.Result, m.Err
}

func TestHybridNetCollector_Collect(t *testing.T) {
	t.Run("Success_NativeWorks", func(t *testing.T) {
		nativeResult := []model.NetInfo{{Name: "eth0", Up: true}}
		native := &MockNetCollector{Result: nativeResult}
		legacy := &MockLegacyNetCollector{Result: []model.NetInfo{{Name: "eth0-legacy"}}}

		hybrid := NewHybridNetCollector(native, legacy, nil)
		result, err := hybrid.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if result[0].Name != "eth0" {
			t.Errorf("expected native result, got %q", result[0].Name)
		}
	})
}
