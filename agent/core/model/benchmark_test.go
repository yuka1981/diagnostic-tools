package model

import (
	"bytes"
	"encoding/json"
	"testing"
	"time"
)

func TestBenchmarkStatus_Constants(t *testing.T) {
	t.Run("ConstantValues", func(t *testing.T) {
		if BenchmarkStatusUnknown != "UNKNOWN" {
			t.Errorf("expected UNKNOWN, got %q", BenchmarkStatusUnknown)
		}
		if BenchmarkStatusPass != "PASS" {
			t.Errorf("expected PASS, got %q", BenchmarkStatusPass)
		}
		if BenchmarkStatusFail != "FAIL" {
			t.Errorf("expected FAIL, got %q", BenchmarkStatusFail)
		}
		if BenchmarkStatusError != "ERROR" {
			t.Errorf("expected ERROR, got %q", BenchmarkStatusError)
		}
	})
}

func TestHPCGMetrics_JSON(t *testing.T) {
	original := HPCGMetrics{
		GFLOPS:        123.45,
		Residual:      0.0001,
		ExecutionTime: 3600.5,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal HPCGMetrics: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded HPCGMetrics
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal HPCGMetrics: %v", err)
		}

		if decoded.GFLOPS != original.GFLOPS {
			t.Errorf("expected GFLOPS %f, got %f", original.GFLOPS, decoded.GFLOPS)
		}
		if decoded.Residual != original.Residual {
			t.Errorf("expected Residual %f, got %f", original.Residual, decoded.Residual)
		}
		if decoded.ExecutionTime != original.ExecutionTime {
			t.Errorf("expected ExecutionTime %f, got %f", original.ExecutionTime, decoded.ExecutionTime)
		}
	})
}

func TestBenchmarkRun_JSON(t *testing.T) {
	startTime := time.Now().UTC().Truncate(time.Second)
	endTime := startTime.Add(1 * time.Hour)

	metricsData := HPCGMetrics{
		GFLOPS:        100.0,
		Residual:      0.0001,
		ExecutionTime: 3600.0,
	}
	metricsJSON, _ := json.Marshal(metricsData)

	original := BenchmarkRun{
		RunID:     "run-123",
		NodeID:    "node-456",
		RecipeID:  "hpcg",
		StartTime: startTime,
		EndTime:   endTime,
		Status:    BenchmarkStatusPass,
		Metrics:   json.RawMessage(metricsJSON),
		Artifacts: []string{"output.txt", "results.dat"},
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BenchmarkRun: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BenchmarkRun
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BenchmarkRun: %v", err)
		}

		if decoded.RunID != original.RunID {
			t.Errorf("expected RunID %q, got %q", original.RunID, decoded.RunID)
		}
		if decoded.NodeID != original.NodeID {
			t.Errorf("expected NodeID %q, got %q", original.NodeID, decoded.NodeID)
		}
		if decoded.RecipeID != original.RecipeID {
			t.Errorf("expected RecipeID %q, got %q", original.RecipeID, decoded.RecipeID)
		}
		if !decoded.StartTime.Equal(original.StartTime) {
			t.Errorf("expected StartTime %v, got %v", original.StartTime, decoded.StartTime)
		}
		if !decoded.EndTime.Equal(original.EndTime) {
			t.Errorf("expected EndTime %v, got %v", original.EndTime, decoded.EndTime)
		}
		if decoded.Status != original.Status {
			t.Errorf("expected Status %q, got %q", original.Status, decoded.Status)
		}
		if len(decoded.Artifacts) != len(original.Artifacts) {
			t.Errorf("expected %d artifacts, got %d", len(original.Artifacts), len(decoded.Artifacts))
		}
	})

	t.Run("Metrics_Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BenchmarkRun
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BenchmarkRun: %v", err)
		}

		// Unmarshal the metrics field
		var metrics HPCGMetrics
		err = json.Unmarshal(decoded.Metrics, &metrics)
		if err != nil {
			t.Fatalf("failed to unmarshal Metrics: %v", err)
		}

		if metrics.GFLOPS != metricsData.GFLOPS {
			t.Errorf("expected GFLOPS %f, got %f", metricsData.GFLOPS, metrics.GFLOPS)
		}
		if metrics.Residual != metricsData.Residual {
			t.Errorf("expected Residual %f, got %f", metricsData.Residual, metrics.Residual)
		}
		if metrics.ExecutionTime != metricsData.ExecutionTime {
			t.Errorf("expected ExecutionTime %f, got %f", metricsData.ExecutionTime, metrics.ExecutionTime)
		}
	})

	t.Run("RoundTrip", func(t *testing.T) {
		// Marshal to JSON
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		// Unmarshal back
		var decoded BenchmarkRun
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
}

func TestBenchmarkRun_EmptyOptionalFields(t *testing.T) {
	startTime := time.Now().UTC().Truncate(time.Second)
	endTime := startTime.Add(1 * time.Hour)

	original := BenchmarkRun{
		RunID:     "run-123",
		RecipeID:  "hpcg",
		StartTime: startTime,
		EndTime:   endTime,
		Status:    BenchmarkStatusPass,
		Metrics:   json.RawMessage(`{}`),
	}

	t.Run("Marshal_OmitEmpty", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal: %v", err)
		}

		var decoded map[string]interface{}
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal to map: %v", err)
		}

		// NodeID should be omitted if empty
		if _, exists := decoded["node_id"]; exists && original.NodeID == "" {
			t.Error("expected node_id to be omitted when empty")
		}

		// Artifacts should be omitted if nil/empty
		if _, exists := decoded["artifacts"]; exists && len(original.Artifacts) == 0 {
			t.Error("expected artifacts to be omitted when empty")
		}
	})
}
