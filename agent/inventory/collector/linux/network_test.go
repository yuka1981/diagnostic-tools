package linux

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

type MultiMockRunner struct {
	responses map[string]string
}

func (m *MultiMockRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	cmd := name
	for _, arg := range args {
		cmd += " " + arg
	}
	if resp, ok := m.responses[cmd]; ok {
		return []byte(resp), nil
	}
	return nil, nil
}

func TestLinuxNetworkCollector_Collect(t *testing.T) {
	tmpDir := filepath.Join(os.TempDir(), "network_test")
	err := os.MkdirAll(tmpDir, 0755)
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	sysClassNet := filepath.Join(tmpDir, "sys", "class", "net")
	sysClassIB := filepath.Join(tmpDir, "sys", "class", "infiniband")
	_ = os.MkdirAll(sysClassNet, 0755)
	_ = os.MkdirAll(sysClassIB, 0755)

	// Mock eth0
	eth0Dir := filepath.Join(sysClassNet, "eth0")
	os.MkdirAll(eth0Dir, 0755)
	pci0Dir := filepath.Join(tmpDir, "0000:00:03.0")
	os.MkdirAll(pci0Dir, 0755)
	os.Symlink(pci0Dir, filepath.Join(eth0Dir, "device"))
	os.WriteFile(filepath.Join(pci0Dir, "numa_node"), []byte("0\n"), 0644)

	// Mock ib0
	ib0Dir := filepath.Join(sysClassNet, "ib0")
	os.MkdirAll(ib0Dir, 0755)
	pci1Dir := filepath.Join(tmpDir, "0000:00:04.0")
	os.MkdirAll(pci1Dir, 0755)
	os.Symlink(pci1Dir, filepath.Join(ib0Dir, "device"))
	os.WriteFile(filepath.Join(ib0Dir, "dev_id"), []byte("0x0\n"), 0644)
	os.WriteFile(filepath.Join(pci1Dir, "numa_node"), []byte("0\n"), 0644)

	// InfiniBand details for ib0
	ibDeviceDir := filepath.Join(pci1Dir, "infiniband", "mlx5_0")
	os.MkdirAll(ibDeviceDir, 0755)

	// Mock IB sysfs
	ibPort1Dir := filepath.Join(sysClassIB, "mlx5_0", "ports", "1")
	os.MkdirAll(ibPort1Dir, 0755)
	os.WriteFile(filepath.Join(sysClassIB, "mlx5_0", "node_guid"), []byte("52:54:00:12:34:56\n"), 0644)
	os.WriteFile(filepath.Join(ibPort1Dir, "lid"), []byte("14\n"), 0644)
	os.WriteFile(filepath.Join(ibPort1Dir, "rate"), []byte("HDR (200 Gbps)\n"), 0644)

	runner := &MultiMockRunner{
		responses: map[string]string{
			"ip -j link show": `[
				{"ifname": "eth0", "link_type": "ether", "operstate": "UP", "address": "52:54:00:12:34:56", "mtu": 1500},
				{
					"ifname": "ib0",
					"link_type": "infiniband",
					"operstate": "UP",
					"address": "80:00:00:48:fe:80:00:00:00:00:00:00:52:54:00:ff:fe:12:34:56",
					"mtu": 4096
				}
			]`,
			"ip -j addr show": `[
				{"ifname": "eth0", "addr_info": [{"local": "192.168.1.10", "prefixlen": 24}]},
				{"ifname": "ib0", "addr_info": [{"local": "10.0.0.1", "prefixlen": 24}]}
			]`,
			"lspci -vmm -D": `Slot: 0000:00:03.0
Class: Ethernet controller
Vendor: Red Hat, Inc.
Device: Virtio network device

Slot: 0000:00:04.0
Class: InfiniBand controller
Vendor: Mellanox Technologies
Device: MT28908 Family [ConnectX-6]
`,
		},
	}

	collector := &LinuxNetworkCollector{
		Runner:      runner,
		SysClassNet: sysClassNet,
		SysClassIB:  sysClassIB,
	}

	inventory, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect failed: %v", err)
	}

	for _, iface := range inventory.Interfaces {
		if iface.Name == "eth0" {
			if iface.PCIAddress != "0000:00:03.0" {
				t.Errorf("eth0: expected PCI address 0000:00:03.0, got %s", iface.PCIAddress)
			}
			if iface.Vendor != "Red Hat, Inc." {
				t.Errorf("eth0: expected vendor Red Hat, Inc., got %s", iface.Vendor)
			}
			if len(iface.IPAddresses) != 1 || iface.IPAddresses[0] != "192.168.1.10/24" {
				t.Errorf("eth0: unexpected IPs: %v", iface.IPAddresses)
			}
		} else if iface.Name == "ib0" {
			if iface.InfiniBand == nil {
				t.Errorf("ib0: expected InfiniBand info, got nil")
			} else {
				if iface.InfiniBand.HCAName != "mlx5_0" {
					t.Errorf("ib0: expected HCA mlx5_0, got %s", iface.InfiniBand.HCAName)
				}
				if iface.InfiniBand.LID != "14" {
					t.Errorf("ib0: expected LID 14, got %s", iface.InfiniBand.LID)
				}
			}
		}
	}
}

func TestLinuxNetworkCollector_Collect_PartialFailures(t *testing.T) {
	runner := &MultiMockRunner{
		responses: map[string]string{
			"ip -j link show": `[{"ifname": "eth0", "link_type": "ether"}]`,
			"ip -j addr show": "invalid json",
			"lspci -vmm -D":   "invalid output",
		},
	}
	collector := NewLinuxNetworkCollector(runner)

	inventory, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect should not fail on partial command failures: %v", err)
	}
	if len(inventory.Interfaces) != 1 {
		t.Errorf("Expected 1 interface, got %d", len(inventory.Interfaces))
	}
}

func TestLinuxNetworkCollector_getLinks_Error(t *testing.T) {
	runner := &MultiMockRunner{
		responses: map[string]string{
			"ip -j link show": "invalid json",
		},
	}
	collector := NewLinuxNetworkCollector(runner)
	_, err := collector.getLinks(context.Background())
	if err == nil {
		t.Error("Expected error on invalid JSON from getLinks")
	}
}
