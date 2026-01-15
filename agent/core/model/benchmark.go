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

// ArtifactUpload represents a file to be uploaded to the server.
type ArtifactUpload struct {
	Filename string `json:"filename"`  // Original filename
	Content  string `json:"content"`   // Base64 encoded file content
	FileType string `json:"file_type"` // File extension without dot (e.g., "txt", "log")
	Size     int64  `json:"size"`      // Original file size in bytes
}

// BenchmarkRun represents a complete benchmark execution result.
type BenchmarkRun struct {
	StartTime       time.Time        `json:"start_time,omitempty"`
	EndTime         time.Time        `json:"end_time,omitempty"`
	RunID           string           `json:"run_id"`
	NodeID          string           `json:"node_id,omitempty"`
	RecipeID        string           `json:"recipe_id"`
	LogContent      string           `json:"log_content,omitempty"`
	Status          BenchmarkStatus  `json:"status"`
	Metrics         json.RawMessage  `json:"metrics"`
	Artifacts       []string         `json:"artifacts,omitempty"`        // Legacy: file paths (kept for backwards compatibility)
	ArtifactUploads []ArtifactUpload `json:"artifact_uploads,omitempty"` // New: actual file contents
}
