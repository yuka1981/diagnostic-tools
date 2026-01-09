package model

// NetworkInventory represents the complete network inventory of a node.
type NetworkInventory struct {
	Interfaces []InterfaceInfo `json:"interfaces"`
}

// InterfaceInfo represents a single network interface and its properties.
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
	Speed       string   `json:"speed,omitempty"` // e.g., "10 Gbps", "HDR (200 Gbps)"
	MTU         int      `json:"mtu"`
	NUMANode    int      `json:"numa_node"`
}

// IBInfo represents InfiniBand specific details.
type IBInfo struct {
	HCAName   string `json:"hca_name"`
	LID       string `json:"lid"`
	GUID      string `json:"guid"`
	LinkSpeed string `json:"link_speed"` // e.g., "HDR"
	Port      int    `json:"port"`
}
