package model

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestBMCProcessor_JSON(t *testing.T) {
	original := BMCProcessor{
		Socket:   "CPU0",
		Model:    "Intel(R) Xeon(R) Gold 6248",
		Cores:    20,
		FreqBase: 2500,
		FreqMax:  3900,
		Serial:   "ABC123",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCProcessor: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCProcessor
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCProcessor: %v", err)
		}

		if decoded.Socket != original.Socket {
			t.Errorf("expected Socket %q, got %q", original.Socket, decoded.Socket)
		}
		if decoded.Model != original.Model {
			t.Errorf("expected Model %q, got %q", original.Model, decoded.Model)
		}
		if decoded.Cores != original.Cores {
			t.Errorf("expected Cores %d, got %d", original.Cores, decoded.Cores)
		}
		if decoded.FreqBase != original.FreqBase {
			t.Errorf("expected FreqBase %d, got %d", original.FreqBase, decoded.FreqBase)
		}
		if decoded.FreqMax != original.FreqMax {
			t.Errorf("expected FreqMax %d, got %d", original.FreqMax, decoded.FreqMax)
		}
		if decoded.Serial != original.Serial {
			t.Errorf("expected Serial %q, got %q", original.Serial, decoded.Serial)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCProcessor{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCProcessor: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data for empty struct")
		}

		var decoded BMCProcessor
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCProcessor: %v", err)
		}
	})
}

func TestBMCMemoryModule_JSON(t *testing.T) {
	original := BMCMemoryModule{
		Slot:         "DIMM_A1",
		SizeGB:       32,
		SpeedMHz:     3200,
		Manufacturer: "Samsung",
		Serial:       "SN123456",
		Type:         "DDR4",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCMemoryModule: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCMemoryModule
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCMemoryModule: %v", err)
		}

		if decoded.Slot != original.Slot {
			t.Errorf("expected Slot %q, got %q", original.Slot, decoded.Slot)
		}
		if decoded.SizeGB != original.SizeGB {
			t.Errorf("expected SizeGB %d, got %d", original.SizeGB, decoded.SizeGB)
		}
		if decoded.SpeedMHz != original.SpeedMHz {
			t.Errorf("expected SpeedMHz %d, got %d", original.SpeedMHz, decoded.SpeedMHz)
		}
		if decoded.Manufacturer != original.Manufacturer {
			t.Errorf("expected Manufacturer %q, got %q", original.Manufacturer, decoded.Manufacturer)
		}
		if decoded.Serial != original.Serial {
			t.Errorf("expected Serial %q, got %q", original.Serial, decoded.Serial)
		}
		if decoded.Type != original.Type {
			t.Errorf("expected Type %q, got %q", original.Type, decoded.Type)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCMemoryModule{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCMemoryModule: %v", err)
		}

		var decoded BMCMemoryModule
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCMemoryModule: %v", err)
		}
	})
}

func TestBMCStorageDrive_JSON(t *testing.T) {
	original := BMCStorageDrive{
		Name:      "Disk0",
		Capacity:  1000000000000, // 1TB
		Model:     "Samsung SSD 980 PRO",
		Serial:    "S6PENX0T123456",
		Interface: "NVMe",
		Health:    "OK",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCStorageDrive: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCStorageDrive
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCStorageDrive: %v", err)
		}

		if decoded.Name != original.Name {
			t.Errorf("expected Name %q, got %q", original.Name, decoded.Name)
		}
		if decoded.Capacity != original.Capacity {
			t.Errorf("expected Capacity %d, got %d", original.Capacity, decoded.Capacity)
		}
		if decoded.Model != original.Model {
			t.Errorf("expected Model %q, got %q", original.Model, decoded.Model)
		}
		if decoded.Serial != original.Serial {
			t.Errorf("expected Serial %q, got %q", original.Serial, decoded.Serial)
		}
		if decoded.Interface != original.Interface {
			t.Errorf("expected Interface %q, got %q", original.Interface, decoded.Interface)
		}
		if decoded.Health != original.Health {
			t.Errorf("expected Health %q, got %q", original.Health, decoded.Health)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCStorageDrive{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCStorageDrive: %v", err)
		}

		var decoded BMCStorageDrive
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCStorageDrive: %v", err)
		}
	})
}

func TestBMCNetworkAdapter_JSON(t *testing.T) {
	original := BMCNetworkAdapter{
		Name:     "NIC1",
		MAC:      "00:11:22:33:44:55",
		Model:    "Intel X710",
		Speed:    "10Gbps",
		Firmware: "1.2.3",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCNetworkAdapter: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCNetworkAdapter
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCNetworkAdapter: %v", err)
		}

		if decoded.Name != original.Name {
			t.Errorf("expected Name %q, got %q", original.Name, decoded.Name)
		}
		if decoded.MAC != original.MAC {
			t.Errorf("expected MAC %q, got %q", original.MAC, decoded.MAC)
		}
		if decoded.Model != original.Model {
			t.Errorf("expected Model %q, got %q", original.Model, decoded.Model)
		}
		if decoded.Speed != original.Speed {
			t.Errorf("expected Speed %q, got %q", original.Speed, decoded.Speed)
		}
		if decoded.Firmware != original.Firmware {
			t.Errorf("expected Firmware %q, got %q", original.Firmware, decoded.Firmware)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCNetworkAdapter{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCNetworkAdapter: %v", err)
		}

		var decoded BMCNetworkAdapter
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCNetworkAdapter: %v", err)
		}
	})
}

func TestBMCInfinibandAdapter_JSON(t *testing.T) {
	original := BMCInfinibandAdapter{
		HCA:       "mlx5_0",
		PortState: "Active",
		Firmware:  "20.31.1014",
		GUID:      "0x506b4b0300ab1234",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCInfinibandAdapter: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCInfinibandAdapter
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCInfinibandAdapter: %v", err)
		}

		if decoded.HCA != original.HCA {
			t.Errorf("expected HCA %q, got %q", original.HCA, decoded.HCA)
		}
		if decoded.PortState != original.PortState {
			t.Errorf("expected PortState %q, got %q", original.PortState, decoded.PortState)
		}
		if decoded.Firmware != original.Firmware {
			t.Errorf("expected Firmware %q, got %q", original.Firmware, decoded.Firmware)
		}
		if decoded.GUID != original.GUID {
			t.Errorf("expected GUID %q, got %q", original.GUID, decoded.GUID)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCInfinibandAdapter{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCInfinibandAdapter: %v", err)
		}

		var decoded BMCInfinibandAdapter
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCInfinibandAdapter: %v", err)
		}
	})
}

func TestBMCBIOSInfo_JSON(t *testing.T) {
	original := BMCBIOSInfo{
		Vendor:      "Dell Inc.",
		Version:     "2.12.0",
		ReleaseDate: "2024-01-15",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCBIOSInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCBIOSInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCBIOSInfo: %v", err)
		}

		if decoded.Vendor != original.Vendor {
			t.Errorf("expected Vendor %q, got %q", original.Vendor, decoded.Vendor)
		}
		if decoded.Version != original.Version {
			t.Errorf("expected Version %q, got %q", original.Version, decoded.Version)
		}
		if decoded.ReleaseDate != original.ReleaseDate {
			t.Errorf("expected ReleaseDate %q, got %q", original.ReleaseDate, decoded.ReleaseDate)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCBIOSInfo{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCBIOSInfo: %v", err)
		}

		var decoded BMCBIOSInfo
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCBIOSInfo: %v", err)
		}
	})
}

func TestBMCControllerInfo_JSON(t *testing.T) {
	original := BMCControllerInfo{
		Model:    "iDRAC9",
		Firmware: "5.10.00.00",
		IP:       "192.168.1.100",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCControllerInfo: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCControllerInfo
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCControllerInfo: %v", err)
		}

		if decoded.Model != original.Model {
			t.Errorf("expected Model %q, got %q", original.Model, decoded.Model)
		}
		if decoded.Firmware != original.Firmware {
			t.Errorf("expected Firmware %q, got %q", original.Firmware, decoded.Firmware)
		}
		if decoded.IP != original.IP {
			t.Errorf("expected IP %q, got %q", original.IP, decoded.IP)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCControllerInfo{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCControllerInfo: %v", err)
		}

		var decoded BMCControllerInfo
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCControllerInfo: %v", err)
		}
	})
}

func TestBMCSensorReading_JSON(t *testing.T) {
	original := BMCSensorReading{
		Name:   "CPU0 Temp",
		Value:  45.5,
		Unit:   "Celsius",
		Status: "OK",
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCSensorReading: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCSensorReading
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCSensorReading: %v", err)
		}

		if decoded.Name != original.Name {
			t.Errorf("expected Name %q, got %q", original.Name, decoded.Name)
		}
		if decoded.Value != original.Value {
			t.Errorf("expected Value %f, got %f", original.Value, decoded.Value)
		}
		if decoded.Unit != original.Unit {
			t.Errorf("expected Unit %q, got %q", original.Unit, decoded.Unit)
		}
		if decoded.Status != original.Status {
			t.Errorf("expected Status %q, got %q", original.Status, decoded.Status)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCSensorReading{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCSensorReading: %v", err)
		}

		var decoded BMCSensorReading
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCSensorReading: %v", err)
		}
	})
}

func TestBMCHealthSummary_JSON(t *testing.T) {
	original := BMCHealthSummary{
		Overall: "OK",
		Components: map[string]string{
			"CPU":     "OK",
			"Memory":  "OK",
			"Storage": "Warning",
			"Network": "OK",
		},
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCHealthSummary: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCHealthSummary
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCHealthSummary: %v", err)
		}

		if decoded.Overall != original.Overall {
			t.Errorf("expected Overall %q, got %q", original.Overall, decoded.Overall)
		}
		if len(decoded.Components) != len(original.Components) {
			t.Errorf("expected %d components, got %d", len(original.Components), len(decoded.Components))
		}
		for key, expectedVal := range original.Components {
			if decoded.Components[key] != expectedVal {
				t.Errorf("expected Components[%q] = %q, got %q", key, expectedVal, decoded.Components[key])
			}
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCHealthSummary{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCHealthSummary: %v", err)
		}

		var decoded BMCHealthSummary
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCHealthSummary: %v", err)
		}
	})

	t.Run("NilComponents", func(t *testing.T) {
		withNil := BMCHealthSummary{
			Overall:    "Unknown",
			Components: nil,
		}
		data, err := json.Marshal(withNil)
		if err != nil {
			t.Fatalf("failed to marshal BMCHealthSummary with nil components: %v", err)
		}

		var decoded BMCHealthSummary
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCHealthSummary with nil components: %v", err)
		}
		if decoded.Overall != withNil.Overall {
			t.Errorf("expected Overall %q, got %q", withNil.Overall, decoded.Overall)
		}
	})
}

func TestBMCInventory_JSON(t *testing.T) {
	original := BMCInventory{
		Processors: []BMCProcessor{
			{
				Socket:   "CPU0",
				Model:    "Intel Xeon Gold 6248",
				Cores:    20,
				FreqBase: 2500,
				FreqMax:  3900,
				Serial:   "CPU123",
			},
			{
				Socket:   "CPU1",
				Model:    "Intel Xeon Gold 6248",
				Cores:    20,
				FreqBase: 2500,
				FreqMax:  3900,
				Serial:   "CPU456",
			},
		},
		Memory: []BMCMemoryModule{
			{
				Slot:         "DIMM_A1",
				SizeGB:       32,
				SpeedMHz:     3200,
				Manufacturer: "Samsung",
				Serial:       "MEM123",
				Type:         "DDR4",
			},
		},
		Storage: []BMCStorageDrive{
			{
				Name:      "Disk0",
				Capacity:  1000000000000,
				Model:     "Samsung SSD",
				Serial:    "DISK123",
				Interface: "NVMe",
				Health:    "OK",
			},
		},
		Network: []BMCNetworkAdapter{
			{
				Name:     "NIC1",
				MAC:      "00:11:22:33:44:55",
				Model:    "Intel X710",
				Speed:    "10Gbps",
				Firmware: "1.2.3",
			},
		},
		Infiniband: []BMCInfinibandAdapter{
			{
				HCA:       "mlx5_0",
				PortState: "Active",
				Firmware:  "20.31.1014",
				GUID:      "0x506b4b0300ab1234",
			},
		},
		BIOS: BMCBIOSInfo{
			Vendor:      "Dell Inc.",
			Version:     "2.12.0",
			ReleaseDate: "2024-01-15",
		},
		BMCInfo: BMCControllerInfo{
			Model:    "iDRAC9",
			Firmware: "5.10.00.00",
			IP:       "192.168.1.100",
		},
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCInventory: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCInventory
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCInventory: %v", err)
		}

		if len(decoded.Processors) != len(original.Processors) {
			t.Errorf("expected %d processors, got %d", len(original.Processors), len(decoded.Processors))
		}
		if len(decoded.Memory) != len(original.Memory) {
			t.Errorf("expected %d memory modules, got %d", len(original.Memory), len(decoded.Memory))
		}
		if len(decoded.Storage) != len(original.Storage) {
			t.Errorf("expected %d storage drives, got %d", len(original.Storage), len(decoded.Storage))
		}
		if len(decoded.Network) != len(original.Network) {
			t.Errorf("expected %d network adapters, got %d", len(original.Network), len(decoded.Network))
		}
		if len(decoded.Infiniband) != len(original.Infiniband) {
			t.Errorf("expected %d infiniband adapters, got %d", len(original.Infiniband), len(decoded.Infiniband))
		}
		if decoded.BIOS.Vendor != original.BIOS.Vendor {
			t.Errorf("expected BIOS.Vendor %q, got %q", original.BIOS.Vendor, decoded.BIOS.Vendor)
		}
		if decoded.BMCInfo.Model != original.BMCInfo.Model {
			t.Errorf("expected BMCInfo.Model %q, got %q", original.BMCInfo.Model, decoded.BMCInfo.Model)
		}
	})

	t.Run("RoundTrip", func(t *testing.T) {
		// Marshal to JSON
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		// Unmarshal back
		var decoded BMCInventory
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}

		// Marshal again
		data2, err := json.Marshal(decoded)
		if err != nil {
			t.Fatalf("failed to marshal decoded: %v", err)
		}

		// Compare JSON strings
		if !bytes.Equal(data, data2) {
			t.Error("round-trip JSON does not match")
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCInventory{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCInventory: %v", err)
		}

		var decoded BMCInventory
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCInventory: %v", err)
		}
	})
}
