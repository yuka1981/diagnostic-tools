package linux

import (
	"context"
	"testing"
)

func TestParseDMIDecodeOutput(t *testing.T) {
	output := `Handle 0x0000, DMI type 0, 26 bytes
BIOS Information
	Vendor: American Megatrends International, LLC.
	Version: 3B05.QCT402
	Release Date: 11/17/2023
	Address: 0xF0000
	Runtime Size: 64 kB
	ROM Size: 64 MB

Handle 0x0001, DMI type 1, 27 bytes
System Information
	Manufacturer: Quanta Cloud Technology Inc.
	Product Name: QuantaGrid D54X-1U
	Version: ---
	Serial Number: QT54X12345678
	UUID: 7d916442-2c24-11ee-be23-74d4dd2e9195
	SKU Number: Default string
	Family: Default String

Handle 0x0011, DMI type 17, 92 bytes
Memory Device
	Size: 32 GB
	Form Factor: DIMM
	Type: DDR4
	Type Detail: Synchronous
	Speed: 2666 MT/s
	Manufacturer: Samsung
	Serial Number: 12345678
	Asset Tag: 00000000
	Part Number: M393A4K40CB2-CTD
	Rank: 2
	Configured Memory Speed: 2400 MT/s
	Minimum Voltage: 1.2 V
	Maximum Voltage: 1.2 V
	Configured Voltage: 1.2 V
	Firmware Version: 1.2.3
	Locator: DIMM_A1
	Bank Locator: P0_Node0_Channel0_Dimm0

Handle 0x0012, DMI type 17, 92 bytes
Memory Device
	Size: No Module Installed
	Locator: DIMM_A2
	Bank Locator: P0_Node0_Channel0_Dimm1
	Firmware Version: Not Available
`
	dmiInfo := parseDMIDecodeOutput(output)

	t.Run("BIOSInfo", func(t *testing.T) {
		if dmiInfo.BIOS.Vendor != "American Megatrends International, LLC." {
			t.Errorf("expected Vendor American Megatrends International, LLC., got %s", dmiInfo.BIOS.Vendor)
		}
	})

	t.Run("SystemInfo", func(t *testing.T) {
		if dmiInfo.System.ProductName != "QuantaGrid D54X-1U" {
			t.Errorf("expected Product Name QuantaGrid D54X-1U, got %s", dmiInfo.System.ProductName)
		}
		if dmiInfo.System.UUID != "7d916442-2c24-11ee-be23-74d4dd2e9195" {
			t.Errorf("expected UUID 7d916442-2c24-11ee-be23-74d4dd2e9195, got %s", dmiInfo.System.UUID)
		}
	})

	t.Run("MemoryInfo", func(t *testing.T) {
		if len(dmiInfo.Memory) != 2 {
			t.Fatalf("expected 2 DIMMs, got %d", len(dmiInfo.Memory))
		}

		t.Run("InstalledDIMM", func(t *testing.T) {
			dimm := dmiInfo.Memory[0]
			if dimm.Locator != "DIMM_A1" {
				t.Errorf("expected Locator DIMM_A1, got %s", dimm.Locator)
			}
			if dimm.Size != "32 GB" {
				t.Errorf("expected Size 32 GB, got %s", dimm.Size)
			}
			if dimm.FormFactor != "DIMM" {
				t.Errorf("expected Form Factor DIMM, got %s", dimm.FormFactor)
			}
			if dimm.FirmwareVersion != "1.2.3" {
				t.Errorf("expected Firmware Version 1.2.3, got %s", dimm.FirmwareVersion)
			}
		})

		t.Run("EmptyDIMM", func(t *testing.T) {
			dimm := dmiInfo.Memory[1]
			if dimm.Size != "No Module Installed" {
				t.Errorf("expected Size No Module Installed, got %s", dimm.Size)
			}
			if dimm.FirmwareVersion != "" {
				t.Errorf("expected normalized Firmware Version to be empty, got %q", dimm.FirmwareVersion)
			}
		})
	})
}

func TestLinuxDMICollector_Collect(t *testing.T) {
	runner := &MockCommandRunner{
		Output: "Handle 0x0000, DMI type 0, 26 bytes\nBIOS Information\n\tVendor: Test Vendor\n",
	}

	collector := NewLinuxDMICollector(runner)
	info, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect failed: %v", err)
	}

	if info.BIOS.Vendor != "Test Vendor" {
		t.Errorf("expected Test Vendor, got %s", info.BIOS.Vendor)
	}
}

func TestLinuxDMICollector_Collect_Error(t *testing.T) {
	runner := &MockCommandRunner{
		Err: context.DeadlineExceeded,
	}

	collector := NewLinuxDMICollector(runner)
	info, err := collector.Collect(context.Background())

	// Should not return error, just return nil info and log warning
	if err != nil {
		t.Errorf("expected nil error, got %v", err)
	}
	if info != nil {
		t.Error("expected nil info on error")
	}
}
