package linux

import (
	"context"
	"log"
	"os"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// LinuxDMICollector collects DMI information using dmidecode.
type LinuxDMICollector struct {
	runner ports.CommandRunner
}

// NewLinuxDMICollector creates a new LinuxDMICollector.
func NewLinuxDMICollector(runner ports.CommandRunner) *LinuxDMICollector {
	return &LinuxDMICollector{runner: runner}
}

// Collect gathers DMI info for System (1), BIOS (0), and Memory (17).
func (c *LinuxDMICollector) Collect(ctx context.Context) (*model.HostDMIInfo, error) {
	method := os.Getenv("HPC_DMIDECODE_METHOD")
	var output []byte
	var err error

	if method == "sudo" {
		output, err = c.runner.Run(ctx, "", "sudo", "dmidecode", "-t", "0,1,17")
	} else {
		// Default to direct (Phase 1: SUID or permission granted)
		output, err = c.runner.Run(ctx, "", "dmidecode", "-t", "0,1,17")
	}

	if err != nil {
		// dmidecode may not be installed or may fail. This is not a fatal error for inventory collection.
		// We can log this and return nil to indicate DMI info is unavailable.
		log.Printf("Warning: failed to collect DMI information: %v", err)
		return nil, nil
	}

	return parseDMIDecodeOutput(string(output)), nil
}

func parseDMIDecodeOutput(output string) *model.HostDMIInfo {
	dmiInfo := &model.HostDMIInfo{}
	sections := strings.Split(output, "\nHandle ")

	for _, section := range sections {
		lines := strings.Split(section, "\n")
		if len(lines) < 2 {
			continue
		}

		header := lines[1]
		switch {
		case strings.Contains(header, "BIOS Information"):
			dmiInfo.BIOS = parseBIOSInfo(lines)
		case strings.Contains(header, "System Information"):
			dmiInfo.System = parseSystemInfo(lines)
		case strings.Contains(header, "Memory Device"):
			dimm := parseDIMMInfo(lines)
			dmiInfo.Memory = append(dmiInfo.Memory, dimm)
		}
	}

	return dmiInfo
}

func parseBIOSInfo(lines []string) model.BIOSInfo {
	info := model.BIOSInfo{}
	data := parseKV(lines)
	info.Vendor = data["Vendor"]
	info.Version = data["Version"]
	info.ReleaseDate = data["Release Date"]
	info.Address = data["Address"]
	info.RuntimeSize = data["Runtime Size"]
	info.ROMSize = data["ROM Size"]
	return info
}

func parseSystemInfo(lines []string) model.SystemInfo {
	info := model.SystemInfo{}
	data := parseKV(lines)
	info.Manufacturer = data["Manufacturer"]
	info.ProductName = data["Product Name"]
	info.Version = data["Version"]
	info.SerialNumber = data["Serial Number"]
	info.UUID = data["UUID"]
	info.SKU = data["SKU Number"]
	info.Family = data["Family"]
	return info
}

func parseDIMMInfo(lines []string) model.DIMMInfo {
	info := model.DIMMInfo{}
	data := parseKV(lines)
	info.Locator = data["Locator"]
	info.BankLocator = data["Bank Locator"]
	info.Size = data["Size"]
	info.Type = data["Type"]
	info.Speed = data["Speed"]
	info.ConfiguredSpeed = data["Configured Memory Speed"]
	info.Manufacturer = data["Manufacturer"]
	info.PartNumber = data["Part Number"]
	info.SerialNumber = data["Serial Number"]
	info.AssetTag = data["Asset Tag"]
	info.Rank = data["Rank"]
	info.FirmwareVersion = data["Firmware Version"]
	info.FormFactor = data["Form Factor"]
	info.MinVoltage = data["Minimum Voltage"]
	info.MaxVoltage = data["Maximum Voltage"]
	info.ConfiguredVoltage = data["Configured Voltage"]
	return info
}

func parseKV(lines []string) map[string]string {
	data := make(map[string]string)
	for _, line := range lines {
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			data[key] = val
		}
	}
	return data
}
