package model

// BMCProcessor represents CPU information from BMC.
type BMCProcessor struct {
	Socket   string `json:"socket"`
	Model    string `json:"model"`
	Cores    int    `json:"cores"`
	FreqBase int    `json:"freq_base_mhz"`
	FreqMax  int    `json:"freq_max_mhz"`
	Serial   string `json:"serial"`
}

// BMCMemoryModule represents a DIMM from BMC.
type BMCMemoryModule struct {
	Slot         string `json:"slot"`
	SizeGB       int    `json:"size_gb"`
	SpeedMHz     int    `json:"speed_mhz"`
	Manufacturer string `json:"manufacturer"`
	Serial       string `json:"serial"`
	Type         string `json:"type"`
}

// BMCStorageDrive represents a storage device from BMC.
type BMCStorageDrive struct {
	Name      string `json:"name"`
	Capacity  int64  `json:"capacity_bytes"`
	Model     string `json:"model"`
	Serial    string `json:"serial"`
	Interface string `json:"interface"`
	Health    string `json:"health"`
}

// BMCNetworkAdapter represents a NIC from BMC.
type BMCNetworkAdapter struct {
	Name     string `json:"name"`
	MAC      string `json:"mac"`
	Model    string `json:"model"`
	Speed    string `json:"speed"`
	Firmware string `json:"firmware"`
}

// BMCInfinibandAdapter represents an IB HCA from BMC.
type BMCInfinibandAdapter struct {
	HCA       string `json:"hca"`
	PortState string `json:"port_state"`
	Firmware  string `json:"firmware"`
	GUID      string `json:"guid"`
}

// BMCBIOSInfo represents BIOS information from BMC.
type BMCBIOSInfo struct {
	Vendor      string `json:"vendor"`
	Version     string `json:"version"`
	ReleaseDate string `json:"release_date"`
}

// BMCControllerInfo represents BMC controller information.
type BMCControllerInfo struct {
	Model    string `json:"model"`
	Firmware string `json:"firmware"`
	IP       string `json:"ip"`
}

// BMCSensorReading represents a sensor value from BMC.
type BMCSensorReading struct {
	Name   string  `json:"name"`
	Value  float64 `json:"value"`
	Unit   string  `json:"unit"`
	Status string  `json:"status"`
}

// BMCHealthSummary represents overall system health.
type BMCHealthSummary struct {
	Overall    string            `json:"overall"`
	Components map[string]string `json:"components"`
}

// BMCInventory is the complete inventory from BMC.
type BMCInventory struct {
	Processors []BMCProcessor         `json:"processors"`
	Memory     []BMCMemoryModule      `json:"memory"`
	Storage    []BMCStorageDrive      `json:"storage"`
	Network    []BMCNetworkAdapter    `json:"network"`
	Infiniband []BMCInfinibandAdapter `json:"infiniband"`
	BIOS       BMCBIOSInfo            `json:"bios"`
	BMCInfo    BMCControllerInfo      `json:"bmc_info"`
}
