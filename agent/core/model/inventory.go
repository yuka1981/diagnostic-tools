package model

import "time"

// HostInfo represents the basic operating system and hardware information of the node.
type HostInfo struct {
	Hostname string `json:"hostname"`
	OS       string `json:"os"`     // e.g., "linux"
	Platform string `json:"platform"` // e.g., "ubuntu", "centos"
	PlatformFamily string `json:"platform_family"` // e.g., "debian", "rhel"
	PlatformVersion string `json:"platform_version"` // e.g., "22.04"
	Kernel   string `json:"kernel"` // e.g., "5.15.0-101-generic"
	Arch     string `json:"arch"`   // e.g., "x86_64", "aarch64"
}

// CPUInfo represents processor details.
type CPUInfo struct {
	ModelName string   `json:"model_name"`
	Cores     int      `json:"cores"`   // Physical cores
	Threads   int      `json:"threads"` // Logical processors
	Sockets   int      `json:"sockets"` // Number of physical CPU packages
	Flags     []string `json:"flags"`   // CPU feature flags
}

// MemInfo represents memory statistics in bytes.
type MemInfo struct {
	Total     uint64 `json:"total"`     // Total physical memory in bytes
	Free      uint64 `json:"free"`      // Free physical memory in bytes
	Available uint64 `json:"available"` // Available memory for applications in bytes
	Buffers   uint64 `json:"buffers"`
	Cached    uint64 `json:"cached"`
	SwapTotal uint64 `json:"swap_total"`
	SwapFree  uint64 `json:"swap_free"`
}

// DiskInfo represents a single filesystem/partition usage.
type DiskInfo struct {
	Device     string `json:"device"`
	Mountpoint string `json:"mountpoint"`
	Fstype     string `json:"fstype"`
	Total      uint64 `json:"total"` // Total size in bytes
	Used       uint64 `json:"used"`  // Used size in bytes
	Free       uint64 `json:"free"`  // Free size in bytes
}

// NetInfo represents a network interface configuration.
type NetInfo struct {
	Name      string   `json:"name"`       // Interface name, e.g., "eth0"
	MacAddress string  `json:"mac_address"` // Hardware address
	IPAddresses []string `json:"ip_addresses"` // List of IP addresses (IPv4/IPv6)
	Speed     int      `json:"speed,omitempty"` // Link speed in Mbps, if available
	Up        bool     `json:"up"`         // Interface operational status
}

// NodeState represents a snapshot of the node's complete inventory state.
// This matches the structure expected by the backend for versioning.
type NodeState struct {
	Host       HostInfo   `json:"host"`
	CPU        CPUInfo    `json:"cpu"`
	Memory     MemInfo    `json:"memory"`
	Disks      []DiskInfo `json:"disks"`
	Network    []NetInfo  `json:"network"`
	CapturedAt time.Time  `json:"captured_at"`
}

