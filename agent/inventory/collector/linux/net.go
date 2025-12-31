package linux

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// LinuxNetCollector collects network interface information.
type LinuxNetCollector struct {
	SysClassNetPath string
}

// NewLinuxNetCollector creates a new network collector.
func NewLinuxNetCollector() *LinuxNetCollector {
	return &LinuxNetCollector{SysClassNetPath: "/sys/class/net"}
}

// Collect scans /sys/class/net for interfaces.
func (c *LinuxNetCollector) Collect() ([]model.NetInfo, error) {
	entries, err := os.ReadDir(c.SysClassNetPath)
	if err != nil {
		return nil, err
	}

	var interfaces []model.NetInfo

	for _, entry := range entries {
		name := entry.Name()
		if name == "." || name == ".." {
			continue
		}

		iface := model.NetInfo{
			Name: name,
		}

		// Read Mac Address
		mac, _ := readFile(filepath.Join(c.SysClassNetPath, name, "address"))
		iface.MacAddress = strings.TrimSpace(mac)

		// Read OperState
		operstate, _ := readFile(filepath.Join(c.SysClassNetPath, name, "operstate"))
		if strings.TrimSpace(operstate) == "up" {
			iface.Up = true
		}

		// Read Speed
		speedStr, err := readFile(filepath.Join(c.SysClassNetPath, name, "speed"))
		if err == nil {
			speed, _ := strconv.Atoi(strings.TrimSpace(speedStr))
			iface.Speed = speed
		}

		// IP Addresses would typically require netlink or parsing `ip addr`,
		// but simple sysfs reading is often safer/easier for basic hardware info.
		// Detailed IP info might be out of scope for "hardware" inventory unless needed.
		// Let's leave IP extraction for now or use `net` package if needed.
		// The prompt mentioned /sys/class/net.

		interfaces = append(interfaces, iface)
	}

	return interfaces, nil
}

func readFile(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(content), nil
}
