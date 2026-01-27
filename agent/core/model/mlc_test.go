package model

import (
	"encoding/json"
	"testing"
)

func TestMLCMetrics_JSON(t *testing.T) {
	t.Run("Marshal basic metrics", func(t *testing.T) {
		metrics := MLCMetrics{
			IdleLatencyNs: 78.2,
			NumaNodeCount: 4,
			PeakBandwidth: map[string]float64{
				"all_reads": 298450.0,
				"3:1":       276230.0,
			},
		}

		data, err := json.Marshal(metrics)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		var decoded MLCMetrics
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}

		if decoded.IdleLatencyNs != 78.2 {
			t.Errorf("IdleLatencyNs = %v, want 78.2", decoded.IdleLatencyNs)
		}
		if decoded.NumaNodeCount != 4 {
			t.Errorf("NumaNodeCount = %v, want 4", decoded.NumaNodeCount)
		}
		if decoded.PeakBandwidth["all_reads"] != 298450.0 {
			t.Errorf("PeakBandwidth[all_reads] = %v, want 298450.0", decoded.PeakBandwidth["all_reads"])
		}
	})

	t.Run("Marshal latency matrix", func(t *testing.T) {
		metrics := MLCMetrics{
			LatencyMatrix: [][]float64{
				{78.2, 112.4, 156.8, 178.3},
				{113.1, 79.0, 179.2, 155.4},
			},
			NumaNodeCount: 2,
		}

		data, err := json.Marshal(metrics)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		var decoded MLCMetrics
		if err := json.Unmarshal(data, &decoded); err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}

		if len(decoded.LatencyMatrix) != 2 {
			t.Errorf("LatencyMatrix rows = %v, want 2", len(decoded.LatencyMatrix))
		}
		if decoded.LatencyMatrix[0][0] != 78.2 {
			t.Errorf("LatencyMatrix[0][0] = %v, want 78.2", decoded.LatencyMatrix[0][0])
		}
	})

	t.Run("Omit empty fields", func(t *testing.T) {
		metrics := MLCMetrics{
			IdleLatencyNs: 78.2,
			NumaNodeCount: 4,
		}

		data, err := json.Marshal(metrics)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		str := string(data)
		if contains(str, "latency_matrix") {
			t.Errorf("JSON should omit empty latency_matrix, got: %s", str)
		}
		if contains(str, "peak_bandwidth") {
			t.Errorf("JSON should omit empty peak_bandwidth, got: %s", str)
		}
	})
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || s != "" && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
