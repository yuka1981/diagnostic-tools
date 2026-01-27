//nolint:govet // fieldalignment: test structs don't need optimal alignment
package ipmi

import (
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestParseSensorList(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []model.BMCSensorReading
	}{
		{
			name: "typical sensor output",
			input: `CPU0 Temp        | 45.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
CPU1 Temp        | 47.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
Fan1             | 3500.000   | RPM        | ok    | na        | 500.000   | 1000.000  | na        | na        | na
Inlet Temp       | 28.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 40.000    | 45.000    | na`,
			expected: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Value: 45.0, Unit: "Celsius", Status: "OK"},
				{Name: "CPU1 Temp", Value: 47.0, Unit: "Celsius", Status: "OK"},
				{Name: "Fan1", Value: 3500.0, Unit: "RPM", Status: "OK"},
				{Name: "Inlet Temp", Value: 28.0, Unit: "Celsius", Status: "OK"},
			},
		},
		{
			name: "sensors with warnings and critical",
			input: `CPU0 Temp        | 92.000     | degrees C  | unc   | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
Fan2             | 0.000      | RPM        | cr    | na        | 500.000   | 1000.000  | na        | na        | na
PSU Power        | 450.000    | Watts      | ok    | na        | na        | na        | 600.000   | 650.000   | na`,
			expected: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Value: 92.0, Unit: "Celsius", Status: "Warning"},
				{Name: "Fan2", Value: 0.0, Unit: "RPM", Status: "Critical"},
				{Name: "PSU Power", Value: 450.0, Unit: "Watts", Status: "OK"},
			},
		},
		{
			name: "sensors with na values",
			input: `Chassis Intru    | na         |            | na    | na        | na        | na        | na        | na        | na
PS Redundancy    | na         | discrete   | na    | na        | na        | na        | na        | na        | na`,
			expected: []model.BMCSensorReading{
				{Name: "Chassis Intru", Value: 0, Unit: "", Status: "N/A"},
				{Name: "PS Redundancy", Value: 0, Unit: "discrete", Status: "N/A"},
			},
		},
		{
			name:     "empty input",
			input:    "",
			expected: nil,
		},
		{
			name: "malformed lines",
			input: `This is not valid
CPU0 Temp        | 45.000     | degrees C  | ok    | na
Another bad line`,
			expected: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Value: 45.0, Unit: "Celsius", Status: "OK"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseSensorList(tt.input)

			if len(result) != len(tt.expected) {
				t.Fatalf("expected %d sensors, got %d", len(tt.expected), len(result))
			}

			for i, expected := range tt.expected {
				if result[i].Name != expected.Name {
					t.Errorf("sensor %d: expected Name %q, got %q", i, expected.Name, result[i].Name)
				}
				if result[i].Value != expected.Value {
					t.Errorf("sensor %d: expected Value %f, got %f", i, expected.Value, result[i].Value)
				}
				if result[i].Unit != expected.Unit {
					t.Errorf("sensor %d: expected Unit %q, got %q", i, expected.Unit, result[i].Unit)
				}
				if result[i].Status != expected.Status {
					t.Errorf("sensor %d: expected Status %q, got %q", i, expected.Status, result[i].Status)
				}
			}
		})
	}
}

func TestParseMCInfo(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected *model.BMCControllerInfo
	}{
		{
			name: "supermicro BMC",
			input: `Device ID                 : 32
Device Revision           : 1
Firmware Revision         : 2.60
IPMI Version              : 2.0
Manufacturer ID           : 10876
Manufacturer Name         : Supermicro
Product ID                : 2379 (0x094b)
Product Name              : Super Server
Device Available          : yes
Provides Device SDRs      : no
Additional Device Support :
    Sensor Device
    SDR Repository Device
    SEL Device
    FRU Inventory Device
    IPMB Event Receiver
    IPMB Event Generator`,
			expected: &model.BMCControllerInfo{
				Firmware: "2.60",
				Model:    "Supermicro Super Server",
			},
		},
		{
			name: "dell BMC",
			input: `Device ID                 : 32
Device Revision           : 1
Firmware Revision         : 6.00
IPMI Version              : 2.0
Manufacturer ID           : 674
Manufacturer Name         : Dell Inc
Product ID                : 2312 (0x0908)
Product Name              : iDRAC`,
			expected: &model.BMCControllerInfo{
				Firmware: "6.00",
				Model:    "Dell Inc iDRAC",
			},
		},
		{
			name: "minimal output",
			input: `Firmware Revision         : 1.50
Manufacturer Name         : Generic`,
			expected: &model.BMCControllerInfo{
				Firmware: "1.50",
				Model:    "Generic",
			},
		},
		{
			name:     "empty output",
			input:    "",
			expected: &model.BMCControllerInfo{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseMCInfo(tt.input)

			if result.Firmware != tt.expected.Firmware {
				t.Errorf("expected Firmware %q, got %q", tt.expected.Firmware, result.Firmware)
			}
			if result.Model != tt.expected.Model {
				t.Errorf("expected Model %q, got %q", tt.expected.Model, result.Model)
			}
		})
	}
}

func TestParseFRU(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected map[string]string
	}{
		{
			name: "typical FRU output",
			input: `FRU Device Description : Builtin FRU Device (ID 0)
 Chassis Type          : Rack Mount Chassis
 Chassis Part Number   : CSE-123
 Chassis Serial        : C123456789
 Board Mfg Date        : Mon Jan  1 00:00:00 1996
 Board Mfg             : Supermicro
 Board Product         : X11SPL-F
 Board Serial          : VM190S012345
 Board Part Number     : X11SPL-F
 Product Manufacturer  : Supermicro
 Product Name          : Super Server
 Product Part Number   : SYS-123
 Product Serial        : A12345678901234`,
			expected: map[string]string{
				"FRU Device Description": "Builtin FRU Device (ID 0)",
				"Chassis Type":           "Rack Mount Chassis",
				"Chassis Part Number":    "CSE-123",
				"Chassis Serial":         "C123456789",
				"Board Mfg Date":         "Mon Jan  1 00:00:00 1996",
				"Board Mfg":              "Supermicro",
				"Board Product":          "X11SPL-F",
				"Board Serial":           "VM190S012345",
				"Board Part Number":      "X11SPL-F",
				"Product Manufacturer":   "Supermicro",
				"Product Name":           "Super Server",
				"Product Part Number":    "SYS-123",
				"Product Serial":         "A12345678901234",
			},
		},
		{
			name:     "empty output",
			input:    "",
			expected: map[string]string{},
		},
		{
			name: "with empty values",
			input: `Board Mfg             : Supermicro
Board Serial          :
Product Name          : Server`,
			expected: map[string]string{
				"Board Mfg":    "Supermicro",
				"Product Name": "Server",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseFRU(tt.input)

			if len(result) != len(tt.expected) {
				t.Errorf("expected %d entries, got %d", len(tt.expected), len(result))
			}

			for key, expectedVal := range tt.expected {
				if result[key] != expectedVal {
					t.Errorf("key %q: expected %q, got %q", key, expectedVal, result[key])
				}
			}
		})
	}
}

func TestParseChassisStatus(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected map[string]string
	}{
		{
			name: "typical chassis status",
			input: `System Power         : on
Power Overload       : false
Power Interlock      : inactive
Main Power Fault     : false
Power Control Fault  : false
Power Restore Policy : always-off
Last Power Event     :
Chassis Intrusion    : inactive
Front-Panel Lockout  : inactive
Drive Fault          : false
Cooling/Fan Fault    : false`,
			expected: map[string]string{
				"System Power":         "on",
				"Power Overload":       "false",
				"Power Interlock":      "inactive",
				"Main Power Fault":     "false",
				"Power Control Fault":  "false",
				"Power Restore Policy": "always-off",
				"Last Power Event":     "",
				"Chassis Intrusion":    "inactive",
				"Front-Panel Lockout":  "inactive",
				"Drive Fault":          "false",
				"Cooling/Fan Fault":    "false",
			},
		},
		{
			name: "with faults",
			input: `System Power         : on
Main Power Fault     : true
Cooling/Fan Fault    : true
Drive Fault          : true`,
			expected: map[string]string{
				"System Power":      "on",
				"Main Power Fault":  "true",
				"Cooling/Fan Fault": "true",
				"Drive Fault":       "true",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseChassisStatus(tt.input)

			for key, expectedVal := range tt.expected {
				if result[key] != expectedVal {
					t.Errorf("key %q: expected %q, got %q", key, expectedVal, result[key])
				}
			}
		})
	}
}

func TestParseLANInfo(t *testing.T) {
	input := `Set in Progress         : Set Complete
Auth Type Support       : NONE MD2 MD5 PASSWORD
IP Address Source       : Static Address
IP Address              : 192.168.1.100
Subnet Mask             : 255.255.255.0
MAC Address             : 3c:ec:ef:12:34:56
Default Gateway IP      : 192.168.1.1
SNMP Community String   : public
Cipher Suite Priv Max   : aaaaaaaaaaaaaaa`

	result := ParseLANInfo(input)

	expected := map[string]string{
		"IP Address Source":     "Static Address",
		"IP Address":            "192.168.1.100",
		"Subnet Mask":           "255.255.255.0",
		"MAC Address":           "3c:ec:ef:12:34:56",
		"Default Gateway IP":    "192.168.1.1",
		"SNMP Community String": "public",
	}

	for key, expectedVal := range expected {
		if result[key] != expectedVal {
			t.Errorf("key %q: expected %q, got %q", key, expectedVal, result[key])
		}
	}
}

func TestParseSDR(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []model.BMCSensorReading
	}{
		{
			name: "typical SDR output",
			input: `CPU0 Temp        | 45 degrees C      | ok
CPU1 Temp        | 47 degrees C      | ok
System Temp      | 32 degrees C      | ok
FAN1             | 3500 RPM          | ok
FAN2             | 3450 RPM          | ok
Vcore            | 1.24 Volts        | ok
12V              | 12.19 Volts       | ok
5VCC             | 5.01 Volts        | ok`,
			expected: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Value: 45, Unit: "Celsius", Status: "OK"},
				{Name: "CPU1 Temp", Value: 47, Unit: "Celsius", Status: "OK"},
				{Name: "System Temp", Value: 32, Unit: "Celsius", Status: "OK"},
				{Name: "FAN1", Value: 3500, Unit: "RPM", Status: "OK"},
				{Name: "FAN2", Value: 3450, Unit: "RPM", Status: "OK"},
				{Name: "Vcore", Value: 1.24, Unit: "Volts", Status: "OK"},
				{Name: "12V", Value: 12.19, Unit: "Volts", Status: "OK"},
				{Name: "5VCC", Value: 5.01, Unit: "Volts", Status: "OK"},
			},
		},
		{
			name: "SDR with no reading",
			input: `CPU0 Temp        | 45 degrees C      | ok
HDD Temp         | no reading        | ns
PSU Status       | disabled          | ns`,
			expected: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Value: 45, Unit: "Celsius", Status: "OK"},
				{Name: "HDD Temp", Value: 0, Unit: "", Status: "Ns"},
				{Name: "PSU Status", Value: 0, Unit: "", Status: "Ns"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseSDR(tt.input)

			if len(result) != len(tt.expected) {
				t.Fatalf("expected %d sensors, got %d", len(tt.expected), len(result))
			}

			for i, expected := range tt.expected {
				if result[i].Name != expected.Name {
					t.Errorf("sensor %d: expected Name %q, got %q", i, expected.Name, result[i].Name)
				}
				if result[i].Value != expected.Value {
					t.Errorf("sensor %d: expected Value %f, got %f", i, expected.Value, result[i].Value)
				}
				if result[i].Unit != expected.Unit {
					t.Errorf("sensor %d: expected Unit %q, got %q", i, expected.Unit, result[i].Unit)
				}
				if result[i].Status != expected.Status {
					t.Errorf("sensor %d: expected Status %q, got %q", i, expected.Status, result[i].Status)
				}
			}
		})
	}
}

func TestParseValueWithUnit(t *testing.T) {
	tests := []struct {
		input         string
		expectedValue float64
		expectedUnit  string
	}{
		{"45 degrees C", 45, "Celsius"},
		{"3500 RPM", 3500, "RPM"},
		{"1.24 Volts", 1.24, "Volts"},
		{"450 Watts", 450, "Watts"},
		{"-10 degrees C", -10, "Celsius"},
		{"disabled", 0, ""},
		{"no reading", 0, ""},
		{"", 0, ""},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			value, unit := parseValueWithUnit(tt.input)
			if value != tt.expectedValue {
				t.Errorf("expected value %f, got %f", tt.expectedValue, value)
			}
			if unit != tt.expectedUnit {
				t.Errorf("expected unit %q, got %q", tt.expectedUnit, unit)
			}
		})
	}
}

func TestNormalizeStatus(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"ok", "OK"},
		{"OK", "OK"},
		{"nominal", "OK"},
		{"nc", "Warning"},
		{"non-critical", "Warning"},
		{"lnc", "Warning"},
		{"unc", "Warning"},
		{"cr", "Critical"},
		{"critical", "Critical"},
		{"lcr", "Critical"},
		{"ucr", "Critical"},
		{"nr", "Critical"},
		{"lnr", "Critical"},
		{"unr", "Critical"},
		{"na", "N/A"},
		{"no reading", "N/A"},
		{"disabled", "N/A"},
		{"not present", "N/A"},
		{"", "Unknown"},
		{"custom", "Custom"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := normalizeStatus(tt.input)
			if result != tt.expected {
				t.Errorf("normalizeStatus(%q) = %q, expected %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestNormalizeUnit(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"degrees C", "Celsius"},
		{"degrees c", "Celsius"},
		{"degrees F", "Fahrenheit"},
		{"RPM", "RPM"},
		{"rpm", "RPM"},
		{"Volts", "Volts"},
		{"volts", "Volts"},
		{"Watts", "Watts"},
		{"Amps", "Amps"},
		{"na", ""},
		{"", ""},
		{"custom unit", "custom unit"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := normalizeUnit(tt.input)
			if result != tt.expected {
				t.Errorf("normalizeUnit(%q) = %q, expected %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestExtractBIOSInfoFromFRU(t *testing.T) {
	tests := []struct {
		name     string
		fru      map[string]string
		expected *model.BMCBIOSInfo
	}{
		{
			name: "with BIOS fields",
			fru: map[string]string{
				"BIOS Vendor":       "American Megatrends Inc.",
				"BIOS Version":      "2.3",
				"BIOS Release Date": "01/15/2023",
			},
			expected: &model.BMCBIOSInfo{
				Vendor:      "American Megatrends Inc.",
				Version:     "2.3",
				ReleaseDate: "01/15/2023",
			},
		},
		{
			name: "fallback to manufacturer",
			fru: map[string]string{
				"Product Manufacturer": "Dell Inc.",
			},
			expected: &model.BMCBIOSInfo{
				Vendor: "Dell Inc.",
			},
		},
		{
			name: "fallback to board mfg",
			fru: map[string]string{
				"Board Mfg": "Supermicro",
			},
			expected: &model.BMCBIOSInfo{
				Vendor: "Supermicro",
			},
		},
		{
			name:     "empty FRU",
			fru:      map[string]string{},
			expected: &model.BMCBIOSInfo{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ExtractBIOSInfoFromFRU(tt.fru)

			if result.Vendor != tt.expected.Vendor {
				t.Errorf("expected Vendor %q, got %q", tt.expected.Vendor, result.Vendor)
			}
			if result.Version != tt.expected.Version {
				t.Errorf("expected Version %q, got %q", tt.expected.Version, result.Version)
			}
			if result.ReleaseDate != tt.expected.ReleaseDate {
				t.Errorf("expected ReleaseDate %q, got %q", tt.expected.ReleaseDate, result.ReleaseDate)
			}
		})
	}
}

func TestDeriveHealthFromSensors(t *testing.T) {
	tests := []struct {
		name            string
		sensors         []model.BMCSensorReading
		expectedOverall string
	}{
		{
			name: "all OK",
			sensors: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Status: "OK"},
				{Name: "CPU1 Temp", Status: "OK"},
				{Name: "Fan1", Status: "OK"},
			},
			expectedOverall: "OK",
		},
		{
			name: "one warning",
			sensors: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Status: "OK"},
				{Name: "CPU1 Temp", Status: "Warning"},
				{Name: "Fan1", Status: "OK"},
			},
			expectedOverall: "Warning",
		},
		{
			name: "one critical",
			sensors: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Status: "OK"},
				{Name: "CPU1 Temp", Status: "Warning"},
				{Name: "Fan1", Status: "Critical"},
			},
			expectedOverall: "Critical",
		},
		{
			name: "with N/A",
			sensors: []model.BMCSensorReading{
				{Name: "CPU0 Temp", Status: "OK"},
				{Name: "DIMM Temp", Status: "N/A"},
			},
			expectedOverall: "OK",
		},
		{
			name:            "empty sensors",
			sensors:         []model.BMCSensorReading{},
			expectedOverall: "OK",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DeriveHealthFromSensors(tt.sensors)

			if result.Overall != tt.expectedOverall {
				t.Errorf("expected Overall %q, got %q", tt.expectedOverall, result.Overall)
			}
		})
	}
}

func TestCategorizeSensor(t *testing.T) {
	tests := []struct {
		name     string
		expected string
	}{
		{"CPU0 Temp", "CPU"},
		{"Processor Temp", "CPU"},
		{"DIMM0 Temp", "Memory"},
		{"Memory Temp", "Memory"},
		{"Fan1", "Fans"},
		{"FAN2 RPM", "Fans"},
		{"System Temp", "Thermal"},
		{"Thermal Zone", "Thermal"},
		{"PSU1 Power", "Power"},
		{"Power Supply", "Power"},
		{"Vcore", "Voltage"},
		{"12V Rail", "Voltage"},
		{"HDD0 Status", "Storage"}, // "Temp" would categorize as Thermal due to keyword priority
		{"SSD Status", "Storage"},
		{"Inlet Temp", "Thermal"},
		{"Unknown Sensor", "Other"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := categorizeSensor(tt.name)
			if result != tt.expected {
				t.Errorf("categorizeSensor(%q) = %q, expected %q", tt.name, result, tt.expected)
			}
		})
	}
}

func TestDeriveHealthFromChassisStatus(t *testing.T) {
	tests := []struct {
		name     string
		status   map[string]string
		expected map[string]string
	}{
		{
			name: "all OK",
			status: map[string]string{
				"Main Power Fault":  "false",
				"Power Overload":    "false",
				"Cooling/Fan Fault": "false",
				"Drive Fault":       "false",
				"Chassis Intrusion": "inactive",
			},
			expected: map[string]string{
				"Power":   "OK",
				"Fans":    "OK",
				"Storage": "OK",
				"Chassis": "OK",
			},
		},
		{
			name: "power fault",
			status: map[string]string{
				"Main Power Fault":  "true",
				"Cooling/Fan Fault": "false",
				"Drive Fault":       "false",
				"Chassis Intrusion": "inactive",
			},
			expected: map[string]string{
				"Power":   "Critical",
				"Fans":    "OK",
				"Storage": "OK",
				"Chassis": "OK",
			},
		},
		{
			name: "multiple faults",
			status: map[string]string{
				"Main Power Fault":  "true",
				"Cooling/Fan Fault": "true",
				"Drive Fault":       "true",
				"Chassis Intrusion": "active",
			},
			expected: map[string]string{
				"Power":   "Critical",
				"Fans":    "Critical",
				"Storage": "Critical",
				"Chassis": "Warning",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := DeriveHealthFromChassisStatus(tt.status)

			for key, expectedVal := range tt.expected {
				if result[key] != expectedVal {
					t.Errorf("component %q: expected %q, got %q", key, expectedVal, result[key])
				}
			}
		})
	}
}

func TestWorstStatus(t *testing.T) {
	tests := []struct {
		a, b     string
		expected string
	}{
		{"OK", "OK", "OK"},
		{"OK", "Warning", "Warning"},
		{"Warning", "OK", "Warning"},
		{"Warning", "Critical", "Critical"},
		{"Critical", "Warning", "Critical"},
		{"OK", "Critical", "Critical"},
		{"N/A", "OK", "OK"},
		{"Unknown", "Warning", "Warning"},
	}

	for _, tt := range tests {
		t.Run(tt.a+"_"+tt.b, func(t *testing.T) {
			result := worstStatus(tt.a, tt.b)
			if result != tt.expected {
				t.Errorf("worstStatus(%q, %q) = %q, expected %q", tt.a, tt.b, result, tt.expected)
			}
		})
	}
}
