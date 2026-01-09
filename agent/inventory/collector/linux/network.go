package linux

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// LinuxNetworkCollector collects detailed network information on Linux.
type LinuxNetworkCollector struct {
	Runner      ports.CommandRunner
	SysClassNet string
	SysClassIB  string
	SysClassPCI string
}

// NewLinuxNetworkCollector creates a new network collector.
func NewLinuxNetworkCollector(runner ports.CommandRunner) *LinuxNetworkCollector {
	return &LinuxNetworkCollector{
		Runner:      runner,
		SysClassNet: "/sys/class/net",
		SysClassIB:  "/sys/class/infiniband",
		SysClassPCI: "/sys/class/pci_bus", // Not strictly needed for symlink resolution
	}
}

// ipLink represents the structure of ip -j link show output.
type ipLink struct {
	Flags     []string `json:"flags"`
	IfName    string   `json:"ifname"`
	LinkType  string   `json:"link_type"`
	OperState string   `json:"operstate"`
	Address   string   `json:"address"`
	Master    string   `json:"master"`
	MTU       int      `json:"mtu"`
}

// ipAddr represents the structure of ip -j addr show output.
type ipAddr struct {
	IfName   string `json:"ifname"`
	AddrInfo []struct {
		Local     string `json:"local"`
		PrefixLen int    `json:"prefixlen"`
	} `json:"addr_info"`
}

// Collect gathers all network interface information.
func (c *LinuxNetworkCollector) Collect(ctx context.Context) (*model.NetworkInventory, error) {
	// 1. PCI Discovery
	pciMap, _ := c.getPCIMap(ctx)

	// 2. Link Discovery
	links, err := c.getLinks(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get links: %w", err)
	}

	// 3. IP Discovery
	addrs, err := c.getAddrs(ctx)
	if err != nil {
		addrs = make(map[string][]string)
	}

	inventory := &model.NetworkInventory{
		Interfaces: make([]model.InterfaceInfo, 0, len(links)),
	}

	for _, link := range links {
		info := model.InterfaceInfo{
			Name:        link.IfName,
			Type:        link.LinkType,
			OperState:   link.OperState,
			MACAddress:  link.Address,
			MTU:         link.MTU,
			Master:      link.Master,
			IPAddresses: addrs[link.IfName],
		}

		// Resolve PCI Address
		pciAddr, err := c.resolvePCIAddress(link.IfName)
		if err == nil {
			info.PCIAddress = pciAddr
			if device, ok := pciMap[pciAddr]; ok {
				info.Vendor = device.Vendor
				info.Model = device.Device
			}
			info.NUMANode = c.getNUMANode(link.IfName)
		}

		// Speed collection
		if link.LinkType == "infiniband" {
			info.InfiniBand = c.collectIBInfo(link.IfName)
			if info.InfiniBand != nil {
				info.Speed = info.InfiniBand.LinkSpeed
			}
		} else {
			info.Speed = c.getEthernetSpeed(link.IfName)
		}

		inventory.Interfaces = append(inventory.Interfaces, info)
	}

	return inventory, nil
}

type pciDevice struct {
	Vendor string
	Device string
}

func (c *LinuxNetworkCollector) getPCIMap(ctx context.Context) (map[string]pciDevice, error) {
	out, err := c.Runner.Run(ctx, "", "lspci", "-vmm", "-D")
	if err != nil {
		return nil, err
	}

	pciMap := make(map[string]pciDevice)
	lines := strings.Split(string(out), "\n")
	var currentSlot string
	var currentDevice pciDevice

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			if currentSlot != "" {
				pciMap[currentSlot] = currentDevice
			}
			currentSlot = ""
			currentDevice = pciDevice{}
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])

		switch key {
		case "Slot":
			currentSlot = val
		case "Vendor":
			currentDevice.Vendor = val
		case "Device":
			currentDevice.Device = val
		}
	}
	if currentSlot != "" {
		pciMap[currentSlot] = currentDevice
	}

	return pciMap, nil
}

func (c *LinuxNetworkCollector) getLinks(ctx context.Context) ([]ipLink, error) {
	out, err := c.Runner.Run(ctx, "", "ip", "-j", "link", "show")
	if err != nil {
		return nil, err
	}
	var links []ipLink
	if err := json.Unmarshal(out, &links); err != nil {
		return nil, err
	}
	return links, nil
}

func (c *LinuxNetworkCollector) getAddrs(ctx context.Context) (map[string][]string, error) {
	out, err := c.Runner.Run(ctx, "", "ip", "-j", "addr", "show")
	if err != nil {
		return nil, err
	}
	var addrs []ipAddr
	if err := json.Unmarshal(out, &addrs); err != nil {
		return nil, err
	}

	addrMap := make(map[string][]string)
	for _, a := range addrs {
		ips := make([]string, 0, len(a.AddrInfo))
		for _, info := range a.AddrInfo {
			if info.Local != "" {
				ips = append(ips, fmt.Sprintf("%s/%d", info.Local, info.PrefixLen))
			}
		}
		addrMap[a.IfName] = ips
	}
	return addrMap, nil
}

func (c *LinuxNetworkCollector) resolvePCIAddress(iface string) (string, error) {
	devicePath := filepath.Join(c.SysClassNet, iface, "device")
	link, err := os.Readlink(devicePath)
	if err != nil {
		return "", err
	}
	// The link is usually something like "../../../0000:00:03.0"
	return filepath.Base(link), nil
}

func (c *LinuxNetworkCollector) getNUMANode(iface string) int {
	numaPath := filepath.Join(c.SysClassNet, iface, "device", "numa_node")
	content, err := os.ReadFile(numaPath)
	if err != nil {
		return -1
	}
	numa, err := strconv.Atoi(strings.TrimSpace(string(content)))
	if err != nil {
		return -1
	}
	return numa
}

func (c *LinuxNetworkCollector) getEthernetSpeed(iface string) string {
	speedPath := filepath.Join(c.SysClassNet, iface, "speed")
	content, err := os.ReadFile(speedPath)
	if err != nil {
		return ""
	}

	speedMbps, err := strconv.Atoi(strings.TrimSpace(string(content)))
	if err != nil || speedMbps <= 0 {
		return ""
	}

	if speedMbps >= 1000 {
		return fmt.Sprintf("%g Gbps", float64(speedMbps)/1000)
	}
	return fmt.Sprintf("%d Mbps", speedMbps)
}

func (c *LinuxNetworkCollector) collectIBInfo(iface string) *model.IBInfo {
	// For InfiniBand, we need to find the HCA name.
	// Often it's in /sys/class/net/<iface>/device/infiniband_verbs/uverbs0/device/infiniband/
	// Actually, /sys/class/net/<iface>/device/infiniband/ contains the HCA name
	ibDir := filepath.Join(c.SysClassNet, iface, "device", "infiniband")
	entries, err := os.ReadDir(ibDir)
	if err != nil || len(entries) == 0 {
		return nil
	}
	hcaName := entries[0].Name()

	// Port is usually 1 for most HCAs, but we can try to find it.
	// For simplicity, let's assume port 1 or look into /sys/class/net/<iface>/dev_id
	port := 1
	devIDPath := filepath.Join(c.SysClassNet, iface, "dev_id")
	if content, err := os.ReadFile(devIDPath); err == nil {
		if id, err := strconv.ParseInt(strings.TrimSpace(string(content)), 0, 64); err == nil {
			port = int(id) + 1
		}
	}

	ib := &model.IBInfo{
		HCAName: hcaName,
		Port:    port,
	}

	portPath := filepath.Join(c.SysClassIB, hcaName, "ports", strconv.Itoa(port))

	if lid, err := os.ReadFile(filepath.Join(portPath, "lid")); err == nil {
		ib.LID = strings.TrimSpace(string(lid))
	}
	if guid, err := os.ReadFile(filepath.Join(c.SysClassIB, hcaName, "node_guid")); err == nil {
		ib.GUID = strings.TrimSpace(string(guid))
	}
	if rate, err := os.ReadFile(filepath.Join(portPath, "rate")); err == nil {
		ib.LinkSpeed = strings.ReplaceAll(strings.TrimSpace(string(rate)), "Gb/sec", "Gb/s")
	}

	return ib
}
