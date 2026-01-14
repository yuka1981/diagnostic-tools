//go:build linux

package native

import (
	"context"
	"fmt"

	"github.com/jaypipes/ghw/pkg/net"
	"github.com/jaypipes/ghw/pkg/option"
	gopsnet "github.com/shirou/gopsutil/v3/net"
	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// NetworkProvider abstracts ghw net and gopsutil net functions for testability.
type NetworkProvider interface {
	Network(opts ...*option.Option) (*net.Info, error)
	Interfaces() (gopsnet.InterfaceStatList, error)
	IOCounters(pernic bool) ([]gopsnet.IOCountersStat, error)
}

// RealNetworkProvider is the production implementation.
type RealNetworkProvider struct{}

func (r *RealNetworkProvider) Network(opts ...*option.Option) (*net.Info, error) {
	return net.New(opts...)
}

func (r *RealNetworkProvider) Interfaces() (gopsnet.InterfaceStatList, error) {
	return gopsnet.Interfaces()
}

func (r *RealNetworkProvider) IOCounters(pernic bool) ([]gopsnet.IOCountersStat, error) {
	return gopsnet.IOCounters(pernic)
}

// NetworkInterface represents a network interface with traffic statistics.
type NetworkInterface struct {
	Name        string   `json:"name"`
	MacAddress  string   `json:"mac_address"`
	IPAddresses []string `json:"ip_addresses"`
	MTU         int      `json:"mtu"`
	Up          bool     `json:"up"`
	Flags       []string `json:"flags"`
	BytesSent   uint64   `json:"bytes_sent"`
	BytesRecv   uint64   `json:"bytes_recv"`
	PacketsSent uint64   `json:"packets_sent"`
	PacketsRecv uint64   `json:"packets_recv"`
}

// NativeNetworkCollector collects network interface information using gopsutil.
type NativeNetworkCollector struct {
	provider NetworkProvider
}

// NewNativeNetworkCollector creates a new NativeNetworkCollector.
// If provider is nil, a default RealNetworkProvider is used.
func NewNativeNetworkCollector(provider NetworkProvider) *NativeNetworkCollector {
	if provider == nil {
		provider = &RealNetworkProvider{}
	}
	return &NativeNetworkCollector{
		provider: provider,
	}
}

// Collect gathers network interface information using gopsutil.
func (c *NativeNetworkCollector) Collect(_ context.Context) ([]NetworkInterface, error) {
	interfaces, err := c.provider.Interfaces()
	if err != nil {
		return nil, fmt.Errorf("failed to get interfaces: %w", err)
	}

	// Get IO counters (graceful degradation if fails)
	ioCounters := make(map[string]gopsnet.IOCountersStat)
	counters, err := c.provider.IOCounters(true)
	if err == nil {
		for _, counter := range counters {
			ioCounters[counter.Name] = counter
		}
	}

	result := make([]NetworkInterface, 0, len(interfaces))
	for _, iface := range interfaces {
		netIface := NetworkInterface{
			Name:       iface.Name,
			MacAddress: iface.HardwareAddr,
			MTU:        iface.MTU,
			Flags:      iface.Flags,
			Up:         hasFlag(iface.Flags, "up"),
		}

		// Extract IP addresses
		for _, addr := range iface.Addrs {
			netIface.IPAddresses = append(netIface.IPAddresses, addr.Addr)
		}

		// Add IO counters if available
		if counter, ok := ioCounters[iface.Name]; ok {
			netIface.BytesSent = counter.BytesSent
			netIface.BytesRecv = counter.BytesRecv
			netIface.PacketsSent = counter.PacketsSent
			netIface.PacketsRecv = counter.PacketsRecv
		}

		result = append(result, netIface)
	}

	return result, nil
}

// CollectSimple gathers basic network interface information for the legacy NetInfo model.
func (c *NativeNetworkCollector) CollectSimple(_ context.Context) ([]model.NetInfo, error) {
	interfaces, err := c.provider.Interfaces()
	if err != nil {
		return nil, fmt.Errorf("failed to get interfaces: %w", err)
	}

	result := make([]model.NetInfo, 0, len(interfaces))
	for _, iface := range interfaces {
		netInfo := model.NetInfo{
			Name:       iface.Name,
			MacAddress: iface.HardwareAddr,
			Up:         hasFlag(iface.Flags, "up"),
		}

		// Extract IP addresses
		for _, addr := range iface.Addrs {
			netInfo.IPAddresses = append(netInfo.IPAddresses, addr.Addr)
		}

		result = append(result, netInfo)
	}

	return result, nil
}

// hasFlag checks if a flag is present in the flags list.
func hasFlag(flags []string, flag string) bool {
	for _, f := range flags {
		if f == flag {
			return true
		}
	}
	return false
}
