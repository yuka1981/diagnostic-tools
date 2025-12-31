package linux

import (
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestLinuxNetCollector_Collect(t *testing.T) {
	// Mock the /sys/class/net path by pointing to our testdata directory
	// In a real implementation, we might inject the base path or interface.
	// Here we'll use a struct field for the base path.

	collector := NewLinuxNetCollector()
	collector.SysClassNetPath = "testdata/sys/class/net"

	nets, err := collector.Collect()
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if len(nets) != 2 {
		t.Errorf("expected 2 interfaces, got %d", len(nets))
	}

	// Verify eth0
	var eth0 *model.NetInfo
	for i := range nets {
		if nets[i].Name == "eth0" {
			eth0 = &nets[i]
			break
		}
	}

	if eth0 == nil {
		t.Fatal("eth0 not found")
	}

	if eth0.MacAddress != "00:11:22:33:44:55" {
		t.Errorf("expected mac 00:11:22:33:44:55, got %s", eth0.MacAddress)
	}
	if !eth0.Up {
		t.Error("expected eth0 to be Up")
	}
	if eth0.Speed != 1000 {
		t.Errorf("expected speed 1000, got %d", eth0.Speed)
	}

	// Verify lo
	var lo *model.NetInfo
	for i := range nets {
		if nets[i].Name == "lo" {
			lo = &nets[i]
			break
		}
	}
	if lo == nil {
		t.Fatal("lo not found")
	}
	if lo.MacAddress != "00:00:00:00:00:00" {
		t.Errorf("expected mac 00:00:00:00:00:00, got %s", lo.MacAddress)
	}
	if lo.Up {
		t.Error("expected lo interface to be down, but it was up")
	}
}
