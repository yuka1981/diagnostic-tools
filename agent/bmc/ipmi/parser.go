// Package ipmi provides IPMI client implementation for BMC communication.
package ipmi

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// ParseSensorList parses `ipmitool sensor list` output into sensor readings.
// Example output format:
// CPU0 Temp        | 45.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
// Fan1             | 3500.000   | RPM        | ok    | na        | 500.000   | 1000.000  | na        | na        | na
func ParseSensorList(output string) []model.BMCSensorReading {
	var sensors []model.BMCSensorReading

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Split by | separator
		parts := strings.Split(line, "|")
		if len(parts) < 4 {
			continue
		}

		name := strings.TrimSpace(parts[0])
		valueStr := strings.TrimSpace(parts[1])
		unit := strings.TrimSpace(parts[2])
		status := strings.TrimSpace(parts[3])

		// Skip if name is empty
		if name == "" {
			continue
		}

		// Parse value
		var value float64
		if valueStr != "na" && valueStr != "" {
			if v, err := strconv.ParseFloat(valueStr, 64); err == nil {
				value = v
			}
		}

		// Normalize status
		status = normalizeStatus(status)

		sensors = append(sensors, model.BMCSensorReading{
			Name:   name,
			Value:  value,
			Unit:   normalizeUnit(unit),
			Status: status,
		})
	}

	return sensors
}

// ParseMCInfo parses `ipmitool mc info` output into BMC controller info.
// Example output format:
// Device ID                 : 32
// Device Revision           : 1
// Firmware Revision         : 2.60
// IPMI Version              : 2.0
// Manufacturer ID           : 10876
// Manufacturer Name         : Supermicro
// Product ID                : 2379 (0x094b)
// Product Name              : Unknown (0x94B)
func ParseMCInfo(output string) *model.BMCControllerInfo {
	info := &model.BMCControllerInfo{}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "Firmware Revision":
			info.Firmware = value
		case "Manufacturer Name":
			info.Model = value
		case "Product Name":
			// Append to model if manufacturer already set
			if info.Model != "" {
				info.Model = info.Model + " " + value
			} else {
				info.Model = value
			}
		}
	}

	return info
}

// ParseFRU parses `ipmitool fru print` output into a key-value map.
// Example output format:
// FRU Device Description : Builtin FRU Device (ID 0)
//  Chassis Type          : Rack Mount Chassis
//  Board Mfg Date        : Mon Jan  1 00:00:00 1996
//  Board Mfg             : Supermicro
//  Board Product         : X11SPL-F
//  Board Serial          : VM190S012345
//  Product Manufacturer  : Supermicro
//  Product Name          : Super Server
//  Product Serial        : A12345678901234
func ParseFRU(output string) map[string]string {
	fru := make(map[string]string)

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		// Trim leading whitespace but keep original for key matching
		trimmedLine := strings.TrimSpace(line)
		if trimmedLine == "" {
			continue
		}

		parts := strings.SplitN(trimmedLine, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Skip empty values
		if value == "" {
			continue
		}

		fru[key] = value
	}

	return fru
}

// ParseChassisStatus parses `ipmitool chassis status` output.
// Example output format:
// System Power         : on
// Power Overload       : false
// Power Interlock      : inactive
// Main Power Fault     : false
// Power Control Fault  : false
// Power Restore Policy : always-off
// Last Power Event     :
// Chassis Intrusion    : inactive
// Front-Panel Lockout  : inactive
// Drive Fault          : false
// Cooling/Fan Fault    : false
func ParseChassisStatus(output string) map[string]string {
	status := make(map[string]string)

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		status[key] = value
	}

	return status
}

// ParseLANInfo parses `ipmitool lan print` output for BMC network config.
// Example output format:
// Set in Progress         : Set Complete
// Auth Type Support       : NONE MD2 MD5 PASSWORD
// IP Address Source       : Static Address
// IP Address              : 192.168.1.100
// Subnet Mask             : 255.255.255.0
// MAC Address             : 3c:ec:ef:12:34:56
// Default Gateway IP      : 192.168.1.1
func ParseLANInfo(output string) map[string]string {
	lan := make(map[string]string)

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		lan[key] = value
	}

	return lan
}

// ParseSDR parses `ipmitool sdr` output for compact sensor data.
// Example output format:
// CPU0 Temp        | 45 degrees C      | ok
// CPU1 Temp        | 47 degrees C      | ok
// System Temp      | 32 degrees C      | ok
// FAN1             | 3500 RPM          | ok
func ParseSDR(output string) []model.BMCSensorReading {
	var sensors []model.BMCSensorReading

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) < 3 {
			continue
		}

		name := strings.TrimSpace(parts[0])
		valueWithUnit := strings.TrimSpace(parts[1])
		status := strings.TrimSpace(parts[2])

		if name == "" {
			continue
		}

		value, unit := parseValueWithUnit(valueWithUnit)

		sensors = append(sensors, model.BMCSensorReading{
			Name:   name,
			Value:  value,
			Unit:   unit,
			Status: normalizeStatus(status),
		})
	}

	return sensors
}

// parseValueWithUnit extracts numeric value and unit from strings like "45 degrees C" or "3500 RPM".
func parseValueWithUnit(s string) (float64, string) {
	s = strings.TrimSpace(s)
	if s == "" || s == "disabled" || s == "no reading" {
		return 0, ""
	}

	// Match numeric value at the beginning
	re := regexp.MustCompile(`^(-?\d+\.?\d*)\s*(.*)$`)
	matches := re.FindStringSubmatch(s)
	if len(matches) < 3 {
		return 0, s
	}

	value, err := strconv.ParseFloat(matches[1], 64)
	if err != nil {
		return 0, s
	}

	unit := normalizeUnit(strings.TrimSpace(matches[2]))
	return value, unit
}

// normalizeUnit converts various unit representations to a standard form.
func normalizeUnit(unit string) string {
	unit = strings.TrimSpace(unit)
	lowerUnit := strings.ToLower(unit)

	switch {
	case strings.Contains(lowerUnit, "degrees c"):
		return "Celsius"
	case strings.Contains(lowerUnit, "degrees f"):
		return "Fahrenheit"
	case strings.Contains(lowerUnit, "rpm"):
		return "RPM"
	case strings.Contains(lowerUnit, "volts"):
		return "Volts"
	case strings.Contains(lowerUnit, "watts"):
		return "Watts"
	case strings.Contains(lowerUnit, "amps"):
		return "Amps"
	case lowerUnit == "na" || lowerUnit == "":
		return ""
	default:
		return unit
	}
}

// normalizeStatus converts IPMI status strings to standard form.
func normalizeStatus(status string) string {
	status = strings.TrimSpace(strings.ToLower(status))

	switch status {
	case "ok", "nominal":
		return "OK"
	case "nc", "non-critical", "lnc", "unc":
		return "Warning"
	case "cr", "critical", "lcr", "ucr", "nr", "non-recoverable", "lnr", "unr":
		return "Critical"
	case "na", "no reading", "disabled", "not present":
		return "N/A"
	default:
		if status == "" {
			return "Unknown"
		}
		// Capitalize first letter
		return strings.ToUpper(status[:1]) + status[1:]
	}
}

// ExtractBIOSInfoFromFRU extracts BIOS information from FRU data.
func ExtractBIOSInfoFromFRU(fru map[string]string) *model.BMCBIOSInfo {
	info := &model.BMCBIOSInfo{}

	// Look for BIOS-related fields
	if v, ok := fru["BIOS Vendor"]; ok {
		info.Vendor = v
	}
	if v, ok := fru["BIOS Version"]; ok {
		info.Version = v
	}
	if v, ok := fru["BIOS Revision"]; ok && info.Version == "" {
		info.Version = v
	}
	if v, ok := fru["BIOS Release Date"]; ok {
		info.ReleaseDate = v
	}

	// Fallback: Use product manufacturer if BIOS vendor not available
	if info.Vendor == "" {
		if v, ok := fru["Product Manufacturer"]; ok {
			info.Vendor = v
		} else if v, ok := fru["Board Mfg"]; ok {
			info.Vendor = v
		}
	}

	return info
}

// ExtractMemoryFromFRU attempts to extract memory information from FRU data.
// Note: IPMI FRU data typically has limited memory information.
func ExtractMemoryFromFRU(fru map[string]string) []model.BMCMemoryModule {
	var modules []model.BMCMemoryModule

	// FRU data rarely contains detailed memory info
	// This is a placeholder for potential parsing of DIMM FRU entries
	// In practice, memory info is better obtained via Redfish or in-band tools

	return modules
}

// DeriveHealthFromSensors derives overall health status from sensor readings.
func DeriveHealthFromSensors(sensors []model.BMCSensorReading) *model.BMCHealthSummary {
	health := &model.BMCHealthSummary{
		Overall:    "OK",
		Components: make(map[string]string),
	}

	// Group sensors by component type
	componentStatus := make(map[string]string)

	for _, sensor := range sensors {
		category := categorizeSensor(sensor.Name)

		currentStatus, exists := componentStatus[category]
		if !exists {
			componentStatus[category] = sensor.Status
		} else {
			// Keep the worst status
			componentStatus[category] = worstStatus(currentStatus, sensor.Status)
		}
	}

	// Determine overall status
	overallStatus := "OK"
	for component, status := range componentStatus {
		health.Components[component] = status
		overallStatus = worstStatus(overallStatus, status)
	}
	health.Overall = overallStatus

	return health
}

// categorizeSensor determines the component category based on sensor name.
func categorizeSensor(name string) string {
	lowerName := strings.ToLower(name)

	switch {
	case strings.Contains(lowerName, "cpu") || strings.Contains(lowerName, "processor"):
		return "CPU"
	case strings.Contains(lowerName, "mem") || strings.Contains(lowerName, "dimm"):
		return "Memory"
	case strings.Contains(lowerName, "fan"):
		return "Fans"
	case strings.Contains(lowerName, "psu") || strings.Contains(lowerName, "power"):
		return "Power"
	case strings.Contains(lowerName, "volt") || strings.Contains(lowerName, "vcore") ||
		strings.HasSuffix(lowerName, "v") || strings.Contains(lowerName, "12v") ||
		strings.Contains(lowerName, "5v") || strings.Contains(lowerName, "3.3v"):
		return "Voltage"
	case strings.Contains(lowerName, "disk") || strings.Contains(lowerName, "hdd") || strings.Contains(lowerName, "ssd"):
		return "Storage"
	case strings.Contains(lowerName, "temp") || strings.Contains(lowerName, "thermal"):
		return "Thermal"
	default:
		return "Other"
	}
}

// worstStatus returns the more severe of two status values.
func worstStatus(a, b string) string {
	statusPriority := map[string]int{
		"Critical": 3,
		"Warning":  2,
		"OK":       1,
		"N/A":      0,
		"Unknown":  0,
	}

	priorityA := statusPriority[a]
	priorityB := statusPriority[b]

	if priorityA >= priorityB {
		return a
	}
	return b
}

// DeriveHealthFromChassisStatus derives health from chassis status output.
func DeriveHealthFromChassisStatus(status map[string]string) map[string]string {
	components := make(map[string]string)

	// Check power-related faults
	if status["Main Power Fault"] == "true" || status["Power Overload"] == "true" {
		components["Power"] = "Critical"
	} else {
		components["Power"] = "OK"
	}

	// Check cooling/fan fault
	if status["Cooling/Fan Fault"] == "true" {
		components["Fans"] = "Critical"
	} else {
		components["Fans"] = "OK"
	}

	// Check drive fault
	if status["Drive Fault"] == "true" {
		components["Storage"] = "Critical"
	} else {
		components["Storage"] = "OK"
	}

	// Check chassis intrusion
	if status["Chassis Intrusion"] == "active" {
		components["Chassis"] = "Warning"
	} else {
		components["Chassis"] = "OK"
	}

	return components
}
