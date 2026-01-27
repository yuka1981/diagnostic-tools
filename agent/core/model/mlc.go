package model

// MLCMetrics contains Intel Memory Latency Checker results.
type MLCMetrics struct {
	// Peak injection bandwidth at different read/write ratios
	// Keys: "all_reads", "3:1", "2:1", "1:1", "stream_triad"
	PeakBandwidth map[string]float64 `json:"peak_bandwidth,omitempty"`

	// NUMA latency matrix [from_node][to_node] in nanoseconds
	LatencyMatrix [][]float64 `json:"latency_matrix,omitempty"`

	// NUMA bandwidth matrix [from_node][to_node] in MB/s
	BandwidthMatrix [][]float64 `json:"bandwidth_matrix,omitempty"`

	// Loaded latency curve: bandwidth vs latency pairs
	LoadedLatency []LoadedLatencyPoint `json:"loaded_latency,omitempty"`

	// Cache-to-cache (core-to-core) latency matrix
	C2CLatencyMatrix [][]float64 `json:"c2c_latency_matrix,omitempty"`

	// Idle latency (unloaded memory access latency)
	IdleLatencyNs float64 `json:"idle_latency_ns,omitempty"`

	// Metadata
	NumaNodeCount int `json:"numa_node_count"`
	CoreCount     int `json:"core_count,omitempty"`
}

// LoadedLatencyPoint represents a single point on the loaded latency curve.
type LoadedLatencyPoint struct {
	BandwidthMBs float64 `json:"bandwidth_mb_s"`
	LatencyNs    float64 `json:"latency_ns"`
}
