package model

import "time"

// HostInfo represents the basic operating system and hardware information of the node.
type HostInfo struct {
	Hostname        string `json:"hostname"`
	OS              string `json:"os"`               // e.g., "linux"
	Platform        string `json:"platform"`         // e.g., "ubuntu", "centos"
	PlatformFamily  string `json:"platform_family"`  // e.g., "debian", "rhel"
	PlatformVersion string `json:"platform_version"` // e.g., "22.04"
	Kernel          string `json:"kernel"`           // e.g., "5.15.0-101-generic"
	Arch            string `json:"arch"`             // e.g., "x86_64", "aarch64"
}

// CPUInfo represents processor details.
type CPUInfo struct {
	Architecture   string   `json:"architecture"`
	VendorID       string   `json:"vendor_id"`
	ModelName      string   `json:"model_name"`
	CPUs           int      `json:"cpus"`
	ThreadsPerCore int      `json:"threads_per_core"`
	CoresPerSocket int      `json:"cores_per_socket"`
	Sockets        int      `json:"sockets"`
	Cores          int      `json:"cores"`
	Threads        int      `json:"threads"`
	Flags          []string `json:"flags"`
}

// MemoryInfo represents memory statistics in bytes.
type MemoryInfo struct {
	Total     uint64 `json:"total"`     // Total physical memory in bytes
	Free      uint64 `json:"free"`      // Free physical memory in bytes
	Available uint64 `json:"available"` // Available memory for applications in bytes
	Buffers   uint64 `json:"buffers"`   // Memory used by kernel buffers (in bytes)
	Cached    uint64 `json:"cached"`    // Memory used for page cache (in bytes)
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
	Name        string   `json:"name"`            // Interface name, e.g., "eth0"
	MacAddress  string   `json:"mac_address"`     // Hardware address
	IPAddresses []string `json:"ip_addresses"`    // List of IP addresses (IPv4/IPv6)
	Speed       int      `json:"speed,omitempty"` // Link speed in Mbps, if available
	Up          bool     `json:"up"`              // Interface operational status
}

// NodeState represents a snapshot of the node's complete inventory state.
// This matches the structure expected by the backend for versioning.
type NodeState struct {
	CapturedAt time.Time  `json:"captured_at"`
	Host       HostInfo   `json:"host"`
	Disks      []DiskInfo `json:"disks"`
	Network    []NetInfo  `json:"network"`
	CPU        CPUInfo    `json:"cpu"`
	Memory     MemoryInfo `json:"memory"`
}
