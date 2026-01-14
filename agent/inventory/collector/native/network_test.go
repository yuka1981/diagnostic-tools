//go:build linux

package native

import (
	"context"
	"errors"
	"testing"

	"github.com/jaypipes/ghw/pkg/net"
	"github.com/jaypipes/ghw/pkg/option"
	gopsnet "github.com/shirou/gopsutil/v3/net"
)

// MockNetworkProvider is a mock implementation for testing.
type MockNetworkProvider struct {
	NetworkErr     error
	InterfaceErr   error
	IOCountersErr  error
	NetworkInfo    *net.Info
	InterfaceStats gopsnet.InterfaceStatList
	IOCountersData []gopsnet.IOCountersStat
}

func (m *MockNetworkProvider) Network(opts ...*option.Option) (*net.Info, error) {
	return m.NetworkInfo, m.NetworkErr
}

func (m *MockNetworkProvider) Interfaces() (gopsnet.InterfaceStatList, error) {
	return m.InterfaceStats, m.InterfaceErr
}

func (m *MockNetworkProvider) IOCounters(pernic bool) ([]gopsnet.IOCountersStat, error) {
	return m.IOCountersData, m.IOCountersErr
}

func TestNativeNetworkCollector_Collect(t *testing.T) {
	t.Run("Success_MultipleInterfaces", func(t *testing.T) {
		mockProvider := &MockNetworkProvider{
			InterfaceStats: gopsnet.InterfaceStatList{
				{
					Index:        1,
					Name:         "eth0",
					HardwareAddr: "00:11:22:33:44:55",
					MTU:          1500,
					Flags:        []string{"up", "broadcast", "multicast"},
					Addrs: gopsnet.InterfaceAddrList{
						{Addr: "192.168.1.100/24"},
						{Addr: "fe80::1/64"},
					},
				},
				{
					Index:        2,
					Name:         "lo",
					HardwareAddr: "",
					MTU:          65536,
					Flags:        []string{"up", "loopback"},
					Addrs: gopsnet.InterfaceAddrList{
						{Addr: "127.0.0.1/8"},
					},
				},
			},
			IOCountersData: []gopsnet.IOCountersStat{
				{
					Name:        "eth0",
					BytesSent:   1000000,
					BytesRecv:   2000000,
					PacketsSent: 1000,
					PacketsRecv: 2000,
				},
				{
					Name:        "lo",
					BytesSent:   100,
					BytesRecv:   100,
					PacketsSent: 10,
					PacketsRecv: 10,
				},
			},
		}

		collector := NewNativeNetworkCollector(mockProvider)
		interfaces, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(interfaces) != 2 {
			t.Fatalf("expected 2 interfaces, got %d", len(interfaces))
		}

		// Check eth0
		eth0 := interfaces[0]
		if eth0.Name != "eth0" {
			t.Errorf("expected Name 'eth0', got %q", eth0.Name)
		}
		if eth0.MacAddress != "00:11:22:33:44:55" {
			t.Errorf("expected MacAddress '00:11:22:33:44:55', got %q", eth0.MacAddress)
		}
		if !eth0.Up {
			t.Error("expected Up to be true")
		}
		if len(eth0.IPAddresses) != 2 {
			t.Errorf("expected 2 IP addresses, got %d", len(eth0.IPAddresses))
		}
		if eth0.BytesSent != 1000000 {
			t.Errorf("expected BytesSent 1000000, got %d", eth0.BytesSent)
		}
		if eth0.BytesRecv != 2000000 {
			t.Errorf("expected BytesRecv 2000000, got %d", eth0.BytesRecv)
		}
	})

	t.Run("Error_InterfacesFails", func(t *testing.T) {
		mockProvider := &MockNetworkProvider{
			InterfaceErr: errors.New("permission denied"),
		}

		collector := NewNativeNetworkCollector(mockProvider)
		_, err := collector.Collect(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("Success_IOCountersFails_GracefulDegradation", func(t *testing.T) {
		mockProvider := &MockNetworkProvider{
			InterfaceStats: gopsnet.InterfaceStatList{
				{
					Index:        1,
					Name:         "eth0",
					HardwareAddr: "00:11:22:33:44:55",
					Flags:        []string{"up"},
				},
			},
			IOCountersErr: errors.New("cannot read counters"),
		}

		collector := NewNativeNetworkCollector(mockProvider)
		interfaces, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error (graceful degradation), got %v", err)
		}

		if len(interfaces) != 1 {
			t.Fatalf("expected 1 interface, got %d", len(interfaces))
		}

		// IO counters should be zero
		if interfaces[0].BytesSent != 0 {
			t.Errorf("expected BytesSent 0, got %d", interfaces[0].BytesSent)
		}
	})

	t.Run("Success_NoInterfaces", func(t *testing.T) {
		mockProvider := &MockNetworkProvider{
			InterfaceStats: gopsnet.InterfaceStatList{},
		}

		collector := NewNativeNetworkCollector(mockProvider)
		interfaces, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if len(interfaces) != 0 {
			t.Errorf("expected 0 interfaces, got %d", len(interfaces))
		}
	})
}

func TestNativeNetworkCollector_InterfaceFlags(t *testing.T) {
	t.Run("Success_FlagsMapping", func(t *testing.T) {
		mockProvider := &MockNetworkProvider{
			InterfaceStats: gopsnet.InterfaceStatList{
				{
					Name:  "eth0",
					Flags: []string{"up", "broadcast", "multicast", "running"},
				},
				{
					Name:  "eth1",
					Flags: []string{"broadcast"}, // down
				},
			},
		}

		collector := NewNativeNetworkCollector(mockProvider)
		interfaces, err := collector.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}

		if !interfaces[0].Up {
			t.Error("expected eth0 to be up")
		}
		if interfaces[1].Up {
			t.Error("expected eth1 to be down")
		}
	})
}

func TestNewNativeNetworkCollector_DefaultProvider(t *testing.T) {
	collector := NewNativeNetworkCollector(nil)

	if collector == nil {
		t.Fatal("expected non-nil collector")
	}

	if collector.provider == nil {
		t.Fatal("expected non-nil provider")
	}
}
