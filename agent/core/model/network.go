package model

// NetworkInventory represents the complete network inventory of a node.
type NetworkInventory struct {
	Interfaces []InterfaceInfo `json:"interfaces"`
}

// InterfaceInfo represents a single network interface and its properties.
//
//nolint:govet,nolintlint // fieldalignment: struct size optimization not required
type InterfaceInfo struct {
	InfiniBand  *IBInfo  `json:"infiniband,omitempty"`
	IPAddresses []string `json:"ip_addresses"`
	Name        string   `json:"name"`
	Type        string   `json:"type"`       // ether, infiniband, loopback
	OperState   string   `json:"oper_state"` // UP, DOWN
	MACAddress  string   `json:"mac_address"`
	Master      string   `json:"master"` // For bonding (e.g., "bond0")
	PCIAddress  string   `json:"pci_address,omitempty"`
	Vendor      string   `json:"vendor,omitempty"`
	Model       string   `json:"model,omitempty"`
	Speed       string   `json:"speed,omitempty"` // e.g., "10 Gbps", "HDR (200 Gb/s)"
	NUMANode    int      `json:"numa_node"`
	MTU         int      `json:"mtu"`
}

// IBInfo represents InfiniBand specific details.
//
//nolint:govet,nolintlint // fieldalignment: struct size optimization not required
type IBInfo struct {
	HCAName   string `json:"hca_name"`
	LID       string `json:"lid"`
	GUID      string `json:"guid"`
	LinkSpeed string `json:"link_speed"` // e.g., "HDR"
	Port      int    `json:"port"`
}
