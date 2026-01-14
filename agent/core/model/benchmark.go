package model

import (
	"encoding/json"
	"time"
)

// BenchmarkStatus represents the final state of a benchmark run.
type BenchmarkStatus string

const (
	BenchmarkStatusUnknown BenchmarkStatus = "UNKNOWN"
	BenchmarkStatusRunning BenchmarkStatus = "RUNNING"
	BenchmarkStatusPass    BenchmarkStatus = "PASS"
	BenchmarkStatusFail    BenchmarkStatus = "FAIL"
	BenchmarkStatusError   BenchmarkStatus = "ERROR"
)

// HPCGMetrics represents the specific results from an HPCG run.
type HPCGMetrics struct {
	GFLOPS        float64 `json:"gflops"`
	Residual      float64 `json:"residual"`
	ExecutionTime float64 `json:"execution_time"` // in seconds
}

// BenchmarkRun represents a complete benchmark execution result.
type BenchmarkRun struct {
	StartTime  time.Time       `json:"start_time"`
	EndTime    time.Time       `json:"end_time"`
	RunID      string          `json:"run_id"`
	NodeID     string          `json:"node_id,omitempty"`
	RecipeID   string          `json:"recipe_id"`
	LogContent string          `json:"log_content,omitempty"`
	Status     BenchmarkStatus `json:"status"`
	Metrics    json.RawMessage `json:"metrics"`
	Artifacts  []string        `json:"artifacts,omitempty"`
}
