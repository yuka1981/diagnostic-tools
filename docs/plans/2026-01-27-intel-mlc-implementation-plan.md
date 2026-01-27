# Intel MLC Benchmark Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Intel MLC benchmark support to qis-agent with Rails visualization and threshold evaluation.

**Architecture:** Go agent package `agent/mlc/` handles binary execution and output parsing. Rails receives metrics via existing benchmark API, stores baselines in new `MlcBaseline` model, and renders heatmap/comparison visualizations using Stimulus controllers.

**Tech Stack:** Go 1.21+ (agent), Rails 7.2 + Hotwire/Stimulus (backend/frontend), Chart.js (visualizations), RSpec + Go testing (tests)

---

## Phase 1: Go Agent - MLC Metrics Model

### Task 1.1: Create MLCMetrics struct

**Files:**
- Create: `agent/core/model/mlc.go`
- Test: `agent/core/model/mlc_test.go`

**Step 1: Write the failing test**

Create `agent/core/model/mlc_test.go`:

```go
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
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
```

**Step 2: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./core/model -run TestMLCMetrics
```

Expected: FAIL with `undefined: MLCMetrics`

**Step 3: Write minimal implementation**

Create `agent/core/model/mlc.go`:

```go
package model

// MLCMetrics contains Intel Memory Latency Checker results.
type MLCMetrics struct {
	// Idle latency (unloaded memory access latency)
	IdleLatencyNs float64 `json:"idle_latency_ns,omitempty"`

	// NUMA latency matrix [from_node][to_node] in nanoseconds
	LatencyMatrix [][]float64 `json:"latency_matrix,omitempty"`

	// NUMA bandwidth matrix [from_node][to_node] in MB/s
	BandwidthMatrix [][]float64 `json:"bandwidth_matrix,omitempty"`

	// Peak injection bandwidth at different read/write ratios
	// Keys: "all_reads", "3:1", "2:1", "1:1", "stream_triad"
	PeakBandwidth map[string]float64 `json:"peak_bandwidth,omitempty"`

	// Loaded latency curve: bandwidth vs latency pairs
	LoadedLatency []LoadedLatencyPoint `json:"loaded_latency,omitempty"`

	// Cache-to-cache (core-to-core) latency matrix
	C2CLatencyMatrix [][]float64 `json:"c2c_latency_matrix,omitempty"`

	// Metadata
	NumaNodeCount int `json:"numa_node_count"`
	CoreCount     int `json:"core_count,omitempty"`
}

// LoadedLatencyPoint represents a single point on the loaded latency curve.
type LoadedLatencyPoint struct {
	BandwidthMBs float64 `json:"bandwidth_mb_s"`
	LatencyNs    float64 `json:"latency_ns"`
}
```

**Step 4: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./core/model -run TestMLCMetrics
```

Expected: PASS

**Step 5: Commit**

```bash
git add agent/core/model/mlc.go agent/core/model/mlc_test.go
git commit -m "feat(agent): add MLCMetrics model for Intel MLC benchmark results"
```

---

## Phase 2: Go Agent - MLC Parser

### Task 2.1: Create parser for idle latency

**Files:**
- Create: `agent/mlc/parser.go`
- Create: `agent/mlc/parser_test.go`
- Create: `agent/mlc/testdata/idle_latency.txt`

**Step 1: Create test data file**

Create `agent/mlc/testdata/idle_latency.txt`:

```
Intel(R) Memory Latency Checker - v3.12
Command line parameters: --idle_latency

Using buffer size of 2000.000MiB
Each iteration took 186.5 core clocks ( 78.2    ns)
```

**Step 2: Write the failing test**

Create `agent/mlc/parser_test.go`:

```go
package mlc

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseIdleLatency(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "idle_latency.txt"))
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	metrics, err := ParseMLCOutput(string(data))
	if err != nil {
		t.Fatalf("ParseMLCOutput failed: %v", err)
	}

	if metrics.IdleLatencyNs != 78.2 {
		t.Errorf("IdleLatencyNs = %v, want 78.2", metrics.IdleLatencyNs)
	}
}
```

**Step 3: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParseIdleLatency
```

Expected: FAIL with `undefined: ParseMLCOutput`

**Step 4: Write minimal implementation**

Create `agent/mlc/parser.go`:

```go
package mlc

import (
	"regexp"
	"strconv"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	// Matches: "Each iteration took 186.5 core clocks ( 78.2    ns)"
	reIdleLatency = regexp.MustCompile(`Each iteration took[\s\d.]+core clocks\s*\(\s*([\d.]+)\s*ns\)`)
)

// ParseMLCOutput parses Intel MLC output and extracts metrics.
func ParseMLCOutput(output string) (*model.MLCMetrics, error) {
	metrics := &model.MLCMetrics{}

	// Parse idle latency
	if matches := reIdleLatency.FindStringSubmatch(output); len(matches) > 1 {
		if val, err := strconv.ParseFloat(matches[1], 64); err == nil {
			metrics.IdleLatencyNs = val
		}
	}

	return metrics, nil
}
```

**Step 5: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParseIdleLatency
```

Expected: PASS

**Step 6: Commit**

```bash
git add agent/mlc/parser.go agent/mlc/parser_test.go agent/mlc/testdata/
git commit -m "feat(agent): add MLC parser for idle latency"
```

---

### Task 2.2: Add parser for latency matrix

**Files:**
- Modify: `agent/mlc/parser.go`
- Modify: `agent/mlc/parser_test.go`
- Create: `agent/mlc/testdata/latency_matrix.txt`

**Step 1: Create test data file**

Create `agent/mlc/testdata/latency_matrix.txt`:

```
Intel(R) Memory Latency Checker - v3.12
Command line parameters: --latency_matrix

Measuring idle latencies (in ns)...
		Numa node
Numa node	     0	     1	     2	     3
       0	  78.2	 112.4	 156.8	 178.3
       1	 113.1	  79.0	 179.2	 155.4
       2	 157.2	 178.9	  78.5	 112.8
       3	 177.8	 156.1	 113.3	  78.9
```

**Step 2: Write the failing test**

Add to `agent/mlc/parser_test.go`:

```go
func TestParseLatencyMatrix(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "latency_matrix.txt"))
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	metrics, err := ParseMLCOutput(string(data))
	if err != nil {
		t.Fatalf("ParseMLCOutput failed: %v", err)
	}

	if metrics.NumaNodeCount != 4 {
		t.Errorf("NumaNodeCount = %v, want 4", metrics.NumaNodeCount)
	}

	if len(metrics.LatencyMatrix) != 4 {
		t.Fatalf("LatencyMatrix rows = %v, want 4", len(metrics.LatencyMatrix))
	}

	// Check diagonal (local access) values
	expectedDiagonal := []float64{78.2, 79.0, 78.5, 78.9}
	for i, expected := range expectedDiagonal {
		if metrics.LatencyMatrix[i][i] != expected {
			t.Errorf("LatencyMatrix[%d][%d] = %v, want %v", i, i, metrics.LatencyMatrix[i][i], expected)
		}
	}

	// Check a remote access value
	if metrics.LatencyMatrix[0][3] != 178.3 {
		t.Errorf("LatencyMatrix[0][3] = %v, want 178.3", metrics.LatencyMatrix[0][3])
	}
}
```

**Step 3: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParseLatencyMatrix
```

Expected: FAIL - `NumaNodeCount = 0, want 4`

**Step 4: Update implementation**

Update `agent/mlc/parser.go`:

```go
package mlc

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	// Matches: "Each iteration took 186.5 core clocks ( 78.2    ns)"
	reIdleLatency = regexp.MustCompile(`Each iteration took[\s\d.]+core clocks\s*\(\s*([\d.]+)\s*ns\)`)
	// Matches latency matrix header: "Numa node	     0	     1	     2	     3"
	reMatrixHeader = regexp.MustCompile(`^Numa node\s+([\d\s]+)$`)
	// Matches latency matrix row: "       0	  78.2	 112.4	 156.8	 178.3"
	reMatrixRow = regexp.MustCompile(`^\s*(\d+)\s+([\d.\s]+)$`)
)

// ParseMLCOutput parses Intel MLC output and extracts metrics.
func ParseMLCOutput(output string) (*model.MLCMetrics, error) {
	metrics := &model.MLCMetrics{}

	// Parse idle latency
	if matches := reIdleLatency.FindStringSubmatch(output); len(matches) > 1 {
		if val, err := strconv.ParseFloat(matches[1], 64); err == nil {
			metrics.IdleLatencyNs = val
		}
	}

	// Parse latency matrix
	metrics.LatencyMatrix, metrics.NumaNodeCount = parseMatrix(output, "Measuring idle latencies")

	return metrics, nil
}

// parseMatrix extracts a NUMA matrix from MLC output.
// marker identifies which matrix section to parse.
func parseMatrix(output, marker string) ([][]float64, int) {
	lines := strings.Split(output, "\n")
	var matrix [][]float64
	inMatrix := false
	nodeCount := 0

	for _, line := range lines {
		if strings.Contains(line, marker) {
			inMatrix = true
			continue
		}

		if !inMatrix {
			continue
		}

		// Check for header row to get node count
		if matches := reMatrixHeader.FindStringSubmatch(line); len(matches) > 1 {
			fields := strings.Fields(matches[1])
			nodeCount = len(fields)
			continue
		}

		// Check for data row
		if matches := reMatrixRow.FindStringSubmatch(line); len(matches) > 2 {
			fields := strings.Fields(matches[2])
			row := make([]float64, len(fields))
			for i, f := range fields {
				if val, err := strconv.ParseFloat(f, 64); err == nil {
					row[i] = val
				}
			}
			matrix = append(matrix, row)

			// Stop if we've read all rows
			if len(matrix) >= nodeCount && nodeCount > 0 {
				break
			}
		}

		// Stop if we hit an empty line after starting to read data
		if len(matrix) > 0 && strings.TrimSpace(line) == "" {
			break
		}
	}

	return matrix, nodeCount
}
```

**Step 5: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParseLatencyMatrix
```

Expected: PASS

**Step 6: Commit**

```bash
git add agent/mlc/parser.go agent/mlc/parser_test.go agent/mlc/testdata/latency_matrix.txt
git commit -m "feat(agent): add MLC parser for latency matrix"
```

---

### Task 2.3: Add parser for peak bandwidth

**Files:**
- Modify: `agent/mlc/parser.go`
- Modify: `agent/mlc/parser_test.go`
- Create: `agent/mlc/testdata/peak_bandwidth.txt`

**Step 1: Create test data file**

Create `agent/mlc/testdata/peak_bandwidth.txt`:

```
Intel(R) Memory Latency Checker - v3.12
Command line parameters: --peak_injection_bandwidth

Measuring Peak Injection Memory Bandwidths for the system
Bandwidths are in MB/sec (1 MB/sec = 1,000,000 Bytes/sec)
Using all the threads from each core if different cores report different bandwidths

Using traffic with the following read-write ratios
ALL Reads        :	298450.0
3:1 Reads-Writes :	276230.5
2:1 Reads-Writes :	258100.2
1:1 Reads-Writes :	198750.8
Stream-triad like:	251300.3
```

**Step 2: Write the failing test**

Add to `agent/mlc/parser_test.go`:

```go
func TestParsePeakBandwidth(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "peak_bandwidth.txt"))
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	metrics, err := ParseMLCOutput(string(data))
	if err != nil {
		t.Fatalf("ParseMLCOutput failed: %v", err)
	}

	if metrics.PeakBandwidth == nil {
		t.Fatal("PeakBandwidth is nil")
	}

	tests := []struct {
		key      string
		expected float64
	}{
		{"all_reads", 298450.0},
		{"3:1", 276230.5},
		{"2:1", 258100.2},
		{"1:1", 198750.8},
		{"stream_triad", 251300.3},
	}

	for _, tc := range tests {
		if val, ok := metrics.PeakBandwidth[tc.key]; !ok {
			t.Errorf("PeakBandwidth[%s] missing", tc.key)
		} else if val != tc.expected {
			t.Errorf("PeakBandwidth[%s] = %v, want %v", tc.key, val, tc.expected)
		}
	}
}
```

**Step 3: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParsePeakBandwidth
```

Expected: FAIL - `PeakBandwidth is nil`

**Step 4: Update implementation**

Add to `agent/mlc/parser.go` (add regex and update ParseMLCOutput):

```go
var (
	// ... existing regexes ...

	// Matches bandwidth lines: "ALL Reads        :	298450.0"
	reBandwidth = regexp.MustCompile(`^(ALL Reads|[\d:]+\s*Reads-Writes|Stream-triad like)\s*:\s*([\d.]+)`)
)

// Add to ParseMLCOutput function, before return:
	// Parse peak bandwidth
	metrics.PeakBandwidth = parsePeakBandwidth(output)
```

Add new function:

```go
// parsePeakBandwidth extracts peak injection bandwidth values.
func parsePeakBandwidth(output string) map[string]float64 {
	bandwidth := make(map[string]float64)
	lines := strings.Split(output, "\n")

	for _, line := range lines {
		if matches := reBandwidth.FindStringSubmatch(line); len(matches) > 2 {
			key := normalizeRatioKey(matches[1])
			if val, err := strconv.ParseFloat(matches[2], 64); err == nil {
				bandwidth[key] = val
			}
		}
	}

	if len(bandwidth) == 0 {
		return nil
	}
	return bandwidth
}

// normalizeRatioKey converts MLC ratio labels to consistent keys.
func normalizeRatioKey(label string) string {
	label = strings.TrimSpace(label)
	switch {
	case strings.HasPrefix(label, "ALL"):
		return "all_reads"
	case strings.HasPrefix(label, "3:1"):
		return "3:1"
	case strings.HasPrefix(label, "2:1"):
		return "2:1"
	case strings.HasPrefix(label, "1:1"):
		return "1:1"
	case strings.HasPrefix(label, "Stream"):
		return "stream_triad"
	default:
		return strings.ToLower(strings.ReplaceAll(label, " ", "_"))
	}
}
```

**Step 5: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestParsePeakBandwidth
```

Expected: PASS

**Step 6: Commit**

```bash
git add agent/mlc/parser.go agent/mlc/parser_test.go agent/mlc/testdata/peak_bandwidth.txt
git commit -m "feat(agent): add MLC parser for peak injection bandwidth"
```

---

## Phase 3: Go Agent - MLC Profiles

### Task 3.1: Create profile definitions

**Files:**
- Create: `agent/mlc/profiles.go`
- Create: `agent/mlc/profiles_test.go`

**Step 1: Write the failing test**

Create `agent/mlc/profiles_test.go`:

```go
package mlc

import "testing"

func TestGetProfile(t *testing.T) {
	tests := []struct {
		name          string
		expectedTests []string
		expectError   bool
	}{
		{
			name:          "quick",
			expectedTests: []string{"idle_latency", "peak_injection_bandwidth"},
			expectError:   false,
		},
		{
			name:          "standard",
			expectedTests: []string{"latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth"},
			expectError:   false,
		},
		{
			name:          "full",
			expectedTests: []string{"idle_latency", "loaded_latency", "latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth", "c2c_latency"},
			expectError:   false,
		},
		{
			name:        "invalid",
			expectError: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			profile, err := GetProfile(tc.name)

			if tc.expectError {
				if err == nil {
					t.Error("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if len(profile.Tests) != len(tc.expectedTests) {
				t.Errorf("profile.Tests length = %d, want %d", len(profile.Tests), len(tc.expectedTests))
			}

			for i, test := range tc.expectedTests {
				if profile.Tests[i] != test {
					t.Errorf("profile.Tests[%d] = %s, want %s", i, profile.Tests[i], test)
				}
			}
		})
	}
}

func TestDefaultProfile(t *testing.T) {
	profile := DefaultProfile()
	if profile.Name != "quick" {
		t.Errorf("DefaultProfile().Name = %s, want quick", profile.Name)
	}
}
```

**Step 2: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestGetProfile
```

Expected: FAIL with `undefined: GetProfile`

**Step 3: Write minimal implementation**

Create `agent/mlc/profiles.go`:

```go
package mlc

import "fmt"

// Profile defines a set of MLC tests to run.
type Profile struct {
	Name        string
	Description string
	Tests       []string
}

// Predefined profiles for common use cases.
var profiles = map[string]Profile{
	"quick": {
		Name:        "quick",
		Description: "Fast health check (~4 min)",
		Tests:       []string{"idle_latency", "peak_injection_bandwidth"},
	},
	"standard": {
		Name:        "standard",
		Description: "Regular characterization (~6 min)",
		Tests:       []string{"latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth"},
	},
	"full": {
		Name:        "full",
		Description: "Complete characterization (~15 min)",
		Tests:       []string{"idle_latency", "loaded_latency", "latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth", "c2c_latency"},
	},
	"numa": {
		Name:        "numa",
		Description: "NUMA topology focus (~5 min)",
		Tests:       []string{"latency_matrix", "bandwidth_matrix", "c2c_latency"},
	},
	"latency": {
		Name:        "latency",
		Description: "Latency-sensitive workload tuning (~8 min)",
		Tests:       []string{"idle_latency", "loaded_latency", "c2c_latency"},
	},
}

// GetProfile returns the profile with the given name.
func GetProfile(name string) (Profile, error) {
	profile, ok := profiles[name]
	if !ok {
		return Profile{}, fmt.Errorf("unknown profile: %s", name)
	}
	return profile, nil
}

// DefaultProfile returns the default profile (quick).
func DefaultProfile() Profile {
	return profiles["quick"]
}

// ListProfiles returns all available profile names.
func ListProfiles() []string {
	names := make([]string, 0, len(profiles))
	for name := range profiles {
		names = append(names, name)
	}
	return names
}
```

**Step 4: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestGetProfile
go test -v ./mlc -run TestDefaultProfile
```

Expected: PASS

**Step 5: Commit**

```bash
git add agent/mlc/profiles.go agent/mlc/profiles_test.go
git commit -m "feat(agent): add MLC profile definitions (quick, standard, full, numa, latency)"
```

---

## Phase 4: Go Agent - MLC Workflow

### Task 4.1: Create workflow orchestrator

**Files:**
- Create: `agent/mlc/workflow.go`
- Create: `agent/mlc/workflow_test.go`

**Step 1: Write the failing test**

Create `agent/mlc/workflow_test.go`:

```go
package mlc

import (
	"context"
	"strings"
	"testing"
)

type mockRunner struct {
	outputs map[string]string
	cmds    []string
}

func (m *mockRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	cmd := name + " " + strings.Join(args, " ")
	m.cmds = append(m.cmds, cmd)

	// Return mock output based on test type in command
	for key, output := range m.outputs {
		if strings.Contains(cmd, key) {
			return []byte(output), nil
		}
	}
	return []byte(""), nil
}

func TestWorkflowOrchestrator_Run(t *testing.T) {
	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
			"--peak_injection_bandwidth": `Intel(R) Memory Latency Checker - v3.12
ALL Reads        :	298450.0`,
		},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID:   "test-run-123",
		Profile: "quick",
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	if result.Status != "PASS" {
		t.Errorf("Status = %s, want PASS", result.Status)
	}

	if result.RecipeID != "mlc" {
		t.Errorf("RecipeID = %s, want mlc", result.RecipeID)
	}

	// Verify both tests were executed
	if len(runner.cmds) != 2 {
		t.Errorf("expected 2 commands, got %d: %v", len(runner.cmds), runner.cmds)
	}
}
```

**Step 2: Run test to verify it fails**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestWorkflowOrchestrator_Run
```

Expected: FAIL with `undefined: WorkflowOrchestrator`

**Step 3: Write minimal implementation**

Create `agent/mlc/workflow.go`:

```go
package mlc

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// RunParams defines parameters for the MLC workflow.
type RunParams struct {
	RunID      string
	Profile    string   // Profile name (quick, standard, full, etc.)
	Tests      []string // Custom test list (overrides profile)
	Modules    []string // lmod modules to load
	BinaryPath string   // Explicit binary path (overrides workflow BinaryPath)
	LogDir     string
}

// WorkflowOrchestrator manages the MLC benchmark workflow.
type WorkflowOrchestrator struct {
	Runner     ports.CommandRunner
	BinaryPath string // Default binary path
}

// testToFlag maps test names to MLC command-line flags.
var testToFlag = map[string]string{
	"idle_latency":            "--idle_latency",
	"loaded_latency":          "--loaded_latency",
	"latency_matrix":          "--latency_matrix",
	"bandwidth_matrix":        "--bandwidth_matrix",
	"peak_injection_bandwidth": "--peak_injection_bandwidth",
	"c2c_latency":             "--c2c_latency",
}

// Run executes the MLC workflow.
func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
	start := time.Now()

	// Determine which tests to run
	tests, err := w.resolveTests(params)
	if err != nil {
		return nil, err
	}

	// Determine binary path
	binaryPath := w.BinaryPath
	if params.BinaryPath != "" {
		binaryPath = params.BinaryPath
	}

	// Run all tests and aggregate output
	var allOutput string
	for _, test := range tests {
		flag, ok := testToFlag[test]
		if !ok {
			return nil, fmt.Errorf("unknown test: %s", test)
		}

		output, err := w.Runner.Run(ctx, "", binaryPath, flag)
		if err != nil {
			return nil, fmt.Errorf("test %s failed: %w", test, err)
		}
		allOutput += string(output) + "\n"
	}

	end := time.Now()

	// Parse metrics from combined output
	metrics, err := ParseMLCOutput(allOutput)
	if err != nil {
		return nil, fmt.Errorf("failed to parse MLC output: %w", err)
	}

	// Marshal metrics to JSON
	metricsJSON, err := json.Marshal(metrics)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal metrics: %w", err)
	}

	return &model.BenchmarkRun{
		RunID:      params.RunID,
		RecipeID:   "mlc",
		StartTime:  start,
		EndTime:    end,
		Status:     model.BenchmarkStatusPass,
		Metrics:    metricsJSON,
		LogContent: allOutput,
	}, nil
}

// resolveTests determines which tests to run based on params.
func (w *WorkflowOrchestrator) resolveTests(params *RunParams) ([]string, error) {
	// Custom tests take precedence
	if len(params.Tests) > 0 {
		return params.Tests, nil
	}

	// Use profile
	profileName := params.Profile
	if profileName == "" {
		profileName = "quick"
	}

	profile, err := GetProfile(profileName)
	if err != nil {
		return nil, err
	}

	return profile.Tests, nil
}
```

**Step 4: Run test to verify it passes**

```bash
cd /home/reid/diagnostic-tools/agent
go test -v ./mlc -run TestWorkflowOrchestrator_Run
```

Expected: PASS

**Step 5: Commit**

```bash
git add agent/mlc/workflow.go agent/mlc/workflow_test.go
git commit -m "feat(agent): add MLC workflow orchestrator"
```

---

## Phase 5: Go Agent - CLI Command

### Task 5.1: Create mlc CLI command

**Files:**
- Create: `agent/cmd/mlc.go`

**Step 1: Write the implementation**

Create `agent/cmd/mlc.go`:

```go
package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/yuka1981/diagnostic-tools/agent/core/identity"
	"github.com/yuka1981/diagnostic-tools/agent/core/runner"
	"github.com/yuka1981/diagnostic-tools/agent/core/uploader"
	"github.com/yuka1981/diagnostic-tools/agent/mlc"
)

var (
	mlcProfile    string
	mlcTests      []string
	mlcBinaryPath string
	mlcModules    []string
	mlcServer     string
	mlcToken      string
	mlcDryRun     bool
)

var mlcCmd = &cobra.Command{
	Use:   "mlc",
	Short: "Run Intel MLC memory benchmark",
	Long: `Run Intel Memory Latency Checker (MLC) benchmark.

Profiles:
  quick     - Fast health check (~4 min): idle_latency, peak_bandwidth
  standard  - Regular characterization (~6 min): latency_matrix, bandwidth_matrix, peak_bandwidth
  full      - Complete characterization (~15 min): all tests
  numa      - NUMA topology focus (~5 min): latency_matrix, bandwidth_matrix, c2c_latency
  latency   - Latency tuning (~8 min): idle_latency, loaded_latency, c2c_latency

Examples:
  qis-agent mlc --profile quick --server https://hpc-dashboard/api --token $TOKEN
  qis-agent mlc --profile full --binary-path /opt/intel/mlc/mlc
  qis-agent mlc --tests latency_matrix,peak_injection_bandwidth`,
	RunE: runMLC,
}

func init() {
	rootCmd.AddCommand(mlcCmd)

	mlcCmd.Flags().StringVarP(&mlcProfile, "profile", "p", "quick", "Test profile (quick, standard, full, numa, latency)")
	mlcCmd.Flags().StringSliceVar(&mlcTests, "tests", nil, "Custom test list (overrides profile)")
	mlcCmd.Flags().StringVar(&mlcBinaryPath, "binary-path", "", "Path to MLC binary")
	mlcCmd.Flags().StringSliceVar(&mlcModules, "modules", nil, "Environment modules to load")
	mlcCmd.Flags().StringVar(&mlcServer, "server", os.Getenv("QIS_AGENT_SERVER"), "Server URL for results upload")
	mlcCmd.Flags().StringVar(&mlcToken, "token", os.Getenv("AGENT_TOKEN"), "Authentication token")
	mlcCmd.Flags().BoolVar(&mlcDryRun, "dry-run", false, "Print what would be executed without running")
}

func runMLC(cmd *cobra.Command, args []string) error {
	ctx := cmd.Context()

	// Get node ID
	nodeID, err := identity.GetOrGenerateNodeID(configDir)
	if err != nil {
		return fmt.Errorf("failed to get node ID: %w", err)
	}

	// Generate run ID
	runID := fmt.Sprintf("mlc-%s", generateRunID())

	// Build params
	params := &mlc.RunParams{
		RunID:      runID,
		Profile:    mlcProfile,
		Tests:      mlcTests,
		Modules:    mlcModules,
		BinaryPath: mlcBinaryPath,
	}

	// Dry run - just show what would be executed
	if mlcDryRun {
		return dryRunMLC(params)
	}

	// Create workflow
	workflow := &mlc.WorkflowOrchestrator{
		Runner:     runner.NewCommandRunner(),
		BinaryPath: resolveBinaryPath(),
	}

	// Run benchmark
	fmt.Fprintf(os.Stderr, "Starting MLC benchmark (profile: %s)...\n", mlcProfile)
	result, err := workflow.Run(ctx, params)
	if err != nil {
		return fmt.Errorf("benchmark failed: %w", err)
	}

	// Upload results if server is configured
	if mlcServer != "" && mlcToken != "" {
		if err := uploadMLCResults(ctx, result, nodeID); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to upload results: %v\n", err)
		} else {
			fmt.Fprintf(os.Stderr, "Results uploaded to %s\n", mlcServer)
		}
	}

	// Output results to stdout
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(result)
}

func dryRunMLC(params *mlc.RunParams) error {
	tests := params.Tests
	if len(tests) == 0 {
		profile, err := mlc.GetProfile(params.Profile)
		if err != nil {
			return err
		}
		tests = profile.Tests
	}

	fmt.Println("Dry run - would execute:")
	fmt.Printf("  Profile: %s\n", params.Profile)
	fmt.Printf("  Binary:  %s\n", resolveBinaryPath())
	fmt.Printf("  Tests:\n")
	for _, t := range tests {
		fmt.Printf("    - %s\n", t)
	}
	return nil
}

func resolveBinaryPath() string {
	if mlcBinaryPath != "" {
		return mlcBinaryPath
	}
	// Try PATH
	return "mlc"
}

func uploadMLCResults(ctx context.Context, result interface{}, nodeID string) error {
	up := uploader.NewHTTPUploader(mlcServer, mlcToken)
	up.SetNodeID(nodeID)
	return up.Upload(ctx, result)
}

func generateRunID() string {
	return fmt.Sprintf("%d", os.Getpid())
}
```

**Step 2: Verify it compiles**

```bash
cd /home/reid/diagnostic-tools/agent
go build -o qis-agent .
```

Expected: Compiles without errors

**Step 3: Test help output**

```bash
./qis-agent mlc --help
```

Expected: Shows help text with profiles and examples

**Step 4: Test dry run**

```bash
./qis-agent mlc --dry-run --profile full
```

Expected: Shows what would be executed

**Step 5: Commit**

```bash
git add agent/cmd/mlc.go
git commit -m "feat(agent): add qis-agent mlc CLI command"
```

---

## Phase 6: Rails - MlcBaseline Model

### Task 6.1: Create MlcBaseline migration and model

**Files:**
- Create: `db/migrate/XXXXXX_create_mlc_baselines.rb`
- Create: `app/models/mlc_baseline.rb`
- Create: `spec/models/mlc_baseline_spec.rb`
- Create: `spec/factories/mlc_baselines.rb`

**Step 1: Generate migration**

```bash
cd /home/reid/diagnostic-tools
bin/rails generate migration CreateMlcBaselines
```

**Step 2: Write the migration**

Edit the generated migration file:

```ruby
# db/migrate/XXXXXX_create_mlc_baselines.rb
class CreateMlcBaselines < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_baselines do |t|
      t.references :node, null: false, foreign_key: true
      t.references :benchmark_run, null: false, foreign_key: true
      t.string :metric_type, null: false
      t.float :value, null: false

      t.timestamps
    end

    add_index :mlc_baselines, [:node_id, :metric_type], unique: true
  end
end
```

**Step 3: Run migration**

```bash
bin/rails db:migrate
```

Expected: Migration runs successfully

**Step 4: Write the failing spec**

Create `spec/models/mlc_baseline_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe MlcBaseline, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:benchmark_run) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:metric_type) }
    it { is_expected.to validate_presence_of(:value) }

    describe "uniqueness of metric_type per node" do
      subject { create(:mlc_baseline) }

      it { is_expected.to validate_uniqueness_of(:metric_type).scoped_to(:node_id) }
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let(:other_node) { create(:node) }
    let!(:baseline1) { create(:mlc_baseline, node: node, metric_type: "idle_latency") }
    let!(:baseline2) { create(:mlc_baseline, node: node, metric_type: "peak_bandwidth") }
    let!(:baseline3) { create(:mlc_baseline, node: other_node, metric_type: "idle_latency") }

    describe ".for_node" do
      it "returns baselines for the specified node" do
        expect(described_class.for_node(node)).to contain_exactly(baseline1, baseline2)
      end
    end

    describe ".by_metric_type" do
      it "returns baselines with the specified metric type" do
        expect(described_class.by_metric_type("idle_latency")).to contain_exactly(baseline1, baseline3)
      end
    end
  end
end
```

**Step 5: Run spec to verify it fails**

```bash
bin/rspec spec/models/mlc_baseline_spec.rb
```

Expected: FAIL - `uninitialized constant MlcBaseline`

**Step 6: Create factory**

Create `spec/factories/mlc_baselines.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :mlc_baseline do
    association :node
    association :benchmark_run
    metric_type { "idle_latency" }
    value { 78.2 }

    trait :peak_bandwidth do
      metric_type { "peak_bandwidth_all_reads" }
      value { 298450.0 }
    end

    trait :latency_matrix do
      metric_type { "latency_matrix_0_1" }
      value { 112.4 }
    end
  end
end
```

**Step 7: Create model**

Create `app/models/mlc_baseline.rb`:

```ruby
# frozen_string_literal: true

class MlcBaseline < ApplicationRecord
  belongs_to :node
  belongs_to :benchmark_run

  validates :metric_type, presence: true, uniqueness: { scope: :node_id }
  validates :value, presence: true

  scope :for_node, ->(node) { where(node: node) }
  scope :by_metric_type, ->(type) { where(metric_type: type) }
  scope :latest, -> { order(created_at: :desc) }
end
```

**Step 8: Run spec to verify it passes**

```bash
bin/rspec spec/models/mlc_baseline_spec.rb
```

Expected: PASS

**Step 9: Commit**

```bash
git add db/migrate/*_create_mlc_baselines.rb app/models/mlc_baseline.rb spec/models/mlc_baseline_spec.rb spec/factories/mlc_baselines.rb
git commit -m "feat(rails): add MlcBaseline model for threshold comparison"
```

---

## Phase 7: Rails - Threshold Evaluator Service

### Task 7.1: Create threshold evaluator service

**Files:**
- Create: `app/services/mlc/threshold_evaluator.rb`
- Create: `spec/services/mlc/threshold_evaluator_spec.rb`

**Step 1: Write the failing spec**

Create `spec/services/mlc/threshold_evaluator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ThresholdEvaluator do
  let(:node) { create(:node) }
  let(:recipe) { create(:benchmark_recipe, slug: "mlc", default_profile: config) }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, metrics: metrics) }

  let(:metrics) do
    {
      "idle_latency_ns" => 78.2,
      "peak_bandwidth" => { "all_reads" => 298450.0 },
      "numa_node_count" => 4
    }
  end

  describe "#evaluate" do
    context "with manual threshold mode" do
      let(:config) do
        {
          "threshold_mode" => "manual",
          "manual_thresholds" => {
            "idle_latency_ns" => { "max" => 90 },
            "peak_bandwidth.all_reads" => { "min" => 200000 }
          }
        }
      end

      it "returns pass when all thresholds are met" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("pass")
        expect(result[:results]["idle_latency_ns"][:status]).to eq("pass")
      end

      it "returns fail when threshold is exceeded" do
        run.update!(metrics: { "idle_latency_ns" => 95.0 })
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("fail")
        expect(result[:results]["idle_latency_ns"][:status]).to eq("fail")
      end
    end

    context "with auto_baseline threshold mode" do
      let(:config) do
        {
          "threshold_mode" => "auto_baseline",
          "baseline_tolerance" => { "warning_percent" => 10, "fail_percent" => 20 }
        }
      end

      let!(:baseline) do
        create(:mlc_baseline, node: node, metric_type: "idle_latency_ns", value: 78.0)
      end

      it "returns pass when within tolerance" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("pass")
      end

      it "returns warn when deviation exceeds warning threshold" do
        run.update!(metrics: { "idle_latency_ns" => 88.0 }) # +12.8%
        result = described_class.new(run, recipe).evaluate
        expect(result[:results]["idle_latency_ns"][:status]).to eq("warn")
      end

      it "returns fail when deviation exceeds fail threshold" do
        run.update!(metrics: { "idle_latency_ns" => 100.0 }) # +28.2%
        result = described_class.new(run, recipe).evaluate
        expect(result[:results]["idle_latency_ns"][:status]).to eq("fail")
      end
    end

    context "with no threshold mode configured" do
      let(:config) { {} }

      it "returns skipped status" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("skipped")
      end
    end
  end
end
```

**Step 2: Run spec to verify it fails**

```bash
bin/rspec spec/services/mlc/threshold_evaluator_spec.rb
```

Expected: FAIL - `uninitialized constant Mlc::ThresholdEvaluator`

**Step 3: Create service**

Create directory and file:

```bash
mkdir -p app/services/mlc
```

Create `app/services/mlc/threshold_evaluator.rb`:

```ruby
# frozen_string_literal: true

module Mlc
  class ThresholdEvaluator
    def initialize(benchmark_run, recipe)
      @run = benchmark_run
      @recipe = recipe
      @node = benchmark_run.node
      @config = recipe.default_profile || {}
      @metrics = benchmark_run.metrics || {}
    end

    def evaluate
      case @config["threshold_mode"]
      when "manual"
        evaluate_manual
      when "auto_baseline"
        evaluate_auto_baseline
      when "cluster_relative"
        evaluate_cluster_relative
      else
        { status: "skipped", message: "No threshold mode configured", results: {} }
      end
    end

    private

    def evaluate_manual
      thresholds = @config["manual_thresholds"] || {}
      results = {}
      overall_status = "pass"

      thresholds.each do |metric_path, constraints|
        value = dig_metric(metric_path)
        next if value.nil?

        result = check_manual_constraints(value, constraints)
        results[metric_path] = result
        overall_status = worse_status(overall_status, result[:status])
      end

      { status: overall_status, results: results }
    end

    def evaluate_auto_baseline
      tolerance = @config["baseline_tolerance"] || {}
      warning_pct = tolerance["warning_percent"] || 10
      fail_pct = tolerance["fail_percent"] || 20

      baselines = MlcBaseline.for_node(@node).index_by(&:metric_type)
      results = {}
      overall_status = "pass"

      flatten_metrics(@metrics).each do |metric_type, value|
        baseline = baselines[metric_type]
        next unless baseline

        deviation_pct = ((value - baseline.value) / baseline.value * 100).abs
        status = if deviation_pct > fail_pct
                   "fail"
                 elsif deviation_pct > warning_pct
                   "warn"
                 else
                   "pass"
                 end

        results[metric_type] = {
          status: status,
          value: value,
          baseline: baseline.value,
          deviation_percent: deviation_pct.round(2)
        }
        overall_status = worse_status(overall_status, status)
      end

      { status: overall_status, results: results }
    end

    def evaluate_cluster_relative
      # TODO: Implement cluster-relative comparison
      { status: "skipped", message: "Cluster-relative mode not yet implemented", results: {} }
    end

    def dig_metric(path)
      parts = path.split(".")
      parts.reduce(@metrics) do |obj, key|
        return nil unless obj.is_a?(Hash)

        obj[key] || obj[key.to_sym]
      end
    end

    def flatten_metrics(hash, prefix = "")
      hash.each_with_object({}) do |(key, value), result|
        full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        if value.is_a?(Hash)
          result.merge!(flatten_metrics(value, full_key))
        elsif value.is_a?(Numeric)
          result[full_key] = value
        end
      end
    end

    def check_manual_constraints(value, constraints)
      status = "pass"

      if constraints["max"] && value > constraints["max"]
        status = "fail"
      elsif constraints["min"] && value < constraints["min"]
        status = "fail"
      end

      { status: status, value: value, constraints: constraints }
    end

    def worse_status(current, new_status)
      order = { "pass" => 0, "warn" => 1, "fail" => 2 }
      order[new_status] > order[current] ? new_status : current
    end
  end
end
```

**Step 4: Run spec to verify it passes**

```bash
bin/rspec spec/services/mlc/threshold_evaluator_spec.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add app/services/mlc/threshold_evaluator.rb spec/services/mlc/threshold_evaluator_spec.rb
git commit -m "feat(rails): add Mlc::ThresholdEvaluator service for baseline comparison"
```

---

## Phase 8: Rails - Seed MLC Recipe

### Task 8.1: Add MLC benchmark recipe seed

**Files:**
- Modify: `db/seeds.rb` or create `db/seeds/mlc_recipe.rb`

**Step 1: Create seed file**

Create `db/seeds/mlc_recipe.rb`:

```ruby
# frozen_string_literal: true

puts "Seeding MLC benchmark recipe..."

BenchmarkRecipe.find_or_create_by!(slug: "mlc") do |recipe|
  recipe.name = "Intel MLC"
  recipe.version = "3.12"
  recipe.command = "qis-agent mlc"
  recipe.description = "Intel Memory Latency Checker - comprehensive memory subsystem characterization"
  recipe.default_profile = {
    "profile" => "quick",
    "binary_path" => "",
    "modules" => [],
    "threshold_mode" => "auto_baseline",
    "baseline_tolerance" => {
      "warning_percent" => 10,
      "fail_percent" => 20
    },
    "manual_thresholds" => {
      "idle_latency_ns" => { "max" => 100 },
      "peak_bandwidth.all_reads" => { "min" => 150000 }
    }
  }
end

puts "MLC benchmark recipe created."
```

**Step 2: Update main seeds file to load MLC seed**

Add to `db/seeds.rb`:

```ruby
load Rails.root.join("db/seeds/mlc_recipe.rb")
```

**Step 3: Run seed**

```bash
bin/rails db:seed
```

Expected: "MLC benchmark recipe created."

**Step 4: Verify in console**

```bash
bin/rails console -e development
BenchmarkRecipe.find_by(slug: "mlc")
```

Expected: Returns the MLC recipe

**Step 5: Commit**

```bash
git add db/seeds.rb db/seeds/mlc_recipe.rb
git commit -m "feat(rails): add MLC benchmark recipe seed data"
```

---

## Summary

This implementation plan covers:

1. **Go Agent (Phase 1-5):**
   - MLCMetrics model with JSON serialization
   - Parser for idle latency, latency matrix, and peak bandwidth
   - Profile definitions (quick, standard, full, numa, latency)
   - Workflow orchestrator
   - CLI command (`qis-agent mlc`)

2. **Rails Backend (Phase 6-8):**
   - MlcBaseline model for storing baseline values
   - ThresholdEvaluator service for manual/auto-baseline comparison
   - MLC recipe seed data

**Not included (future phases):**
- Bandwidth matrix and loaded latency parsers
- C2C latency parser
- Cluster-relative threshold comparison
- Visualization components (heatmaps, charts)
- PDF export

---

**Plan complete and saved to `docs/plans/2026-01-27-intel-mlc-implementation-plan.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
