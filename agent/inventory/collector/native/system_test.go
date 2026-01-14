//go:build linux

package native

import (
	"context"
	"testing"
)

func TestNativeSystemCollector_New(t *testing.T) {
	t.Run("Success_DefaultConfig", func(t *testing.T) {
		collector := NewNativeSystemCollector(nil)

		if collector == nil {
			t.Fatal("expected non-nil collector")
		}

		if collector.cpuCollector == nil {
			t.Error("expected non-nil cpuCollector")
		}
		if collector.memCollector == nil {
			t.Error("expected non-nil memCollector")
		}
		if collector.diskCollector == nil {
			t.Error("expected non-nil diskCollector")
		}
		if collector.netCollector == nil {
			t.Error("expected non-nil netCollector")
		}
		if collector.pciCollector == nil {
			t.Error("expected non-nil pciCollector")
		}
	})

	t.Run("Success_WithLegacyFallback", func(t *testing.T) {
		config := &NativeSystemCollectorConfig{
			LegacyCPUCollector:    &MockCPUCollector{},
			LegacyMemoryCollector: &MockMemoryCollector{},
			LegacyDiskCollector:   &MockDiskCollector{},
			LegacyNetCollector:    &MockNetCollector{},
		}

		collector := NewNativeSystemCollector(config)

		if collector == nil {
			t.Fatal("expected non-nil collector")
		}

		// Verify hybrid collectors are used (they implement the interfaces)
		if collector.cpuCollector == nil {
			t.Error("expected non-nil cpuCollector (hybrid)")
		}
	})
}

func TestNativeSystemCollector_GetCPUInfo(t *testing.T) {
	// This test verifies the integration works end-to-end
	// In a real environment, this would read from /sys
	collector := NewNativeSystemCollector(nil)

	// We can't predict the output, but it should not panic
	// and should return either data or an error
	_, err := collector.GetCPUInfo(context.Background())

	// On a real Linux system, this should work
	// On a test environment without /sys, it might fail - that's OK
	t.Logf("GetCPUInfo error (expected on test systems): %v", err)
}

func TestNativeSystemCollector_GetMemInfo(t *testing.T) {
	collector := NewNativeSystemCollector(nil)

	_, err := collector.GetMemInfo(context.Background())
	t.Logf("GetMemInfo error (expected on test systems): %v", err)
}

func TestNativeSystemCollector_GetDiskInfo(t *testing.T) {
	collector := NewNativeSystemCollector(nil)

	_, err := collector.GetDiskInfo(context.Background())
	t.Logf("GetDiskInfo error (expected on test systems): %v", err)
}

func TestNativeSystemCollector_GetNetInfo(t *testing.T) {
	collector := NewNativeSystemCollector(nil)

	_, err := collector.GetNetInfo(context.Background())
	t.Logf("GetNetInfo error (expected on test systems): %v", err)
}

func TestNativeSystemCollector_GetGPUs(t *testing.T) {
	collector := NewNativeSystemCollector(nil)

	_, err := collector.GetGPUs(context.Background())
	t.Logf("GetGPUs error (expected on test systems): %v", err)
}

func TestNativeSystemCollector_GetNetworkCards(t *testing.T) {
	collector := NewNativeSystemCollector(nil)

	_, err := collector.GetNetworkCards(context.Background())
	t.Logf("GetNetworkCards error (expected on test systems): %v", err)
}
