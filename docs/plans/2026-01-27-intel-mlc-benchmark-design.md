# Intel MLC Benchmark Integration Design

## Overview

Integration of Intel Memory Latency Checker (MLC) v3.12 into the diagnostic-tools platform for comprehensive memory subsystem characterization on HPC cluster nodes.

**Goals:**
- Full memory characterization: NUMA topology, latency matrices, bandwidth tests, cache-to-cache latencies
- Visualization: Heatmaps, comparison views, diagnostic reports
- Threshold evaluation: Manual, auto-baseline, and cluster-relative comparison modes

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RAILS APPLICATION                           │
├─────────────────────────────────────────────────────────────────────┤
│  BenchmarkRecipe (mlc)     │  BenchmarkRun        │  MlcBaseline    │
│  - profiles (quick/full)   │  - metrics (JSON)    │  - node_id      │
│  - threshold_mode          │  - threshold_results │  - metric_type  │
│  - manual_thresholds       │  - baseline_id       │  - value        │
├─────────────────────────────────────────────────────────────────────┤
│  Visualization Views                                                 │
│  - Heatmap (NUMA matrix)   │  - Comparison        │  - Report       │
│  - Bandwidth charts        │  - Trend graphs      │  - Export PDF   │
└─────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │ API POST /api/v1/benchmark_runs
                                    │
┌─────────────────────────────────────────────────────────────────────┐
│                           GO AGENT                                   │
├─────────────────────────────────────────────────────────────────────┤
│  agent/mlc/                                                          │
│  ├── workflow.go      # Orchestrates MLC execution                  │
│  ├── parser.go        # Parses MLC stdout into structured metrics   │
│  ├── config.go        # Profile definitions, test parameters        │
│  └── profiles.go      # Pre-defined test profiles                   │
├─────────────────────────────────────────────────────────────────────┤
│  cmd/mlc.go           # CLI: qis-agent mlc --profile standard       │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                           Intel MLC Binary
                    (site-specific installation path)
```

## Agent Configuration

### Binary Resolution

The MLC binary location is resolved in this order:

1. **BinaryPath** if specified → use directly (e.g., `/shared/tools/mlc/mlc`)
2. **Modules** if specified → load lmod modules, then find `mlc` in `$PATH`
3. **Default** → search `$PATH` for `mlc`
4. **Error** if not found → "MLC binary not found. Specify --binary-path or ensure mlc is in PATH"

**Typical HPC deployment patterns:**

| Pattern | Configuration |
|---------|---------------|
| Shared filesystem | `binary_path: "/opt/intel/mlc/mlc"` |
| Environment modules | `modules: ["intel-mlc/3.12"]` |
| Node-local install | `binary_path: "/usr/local/bin/mlc"` |
| Already in PATH | No config needed (default) |

### Pre-defined Profiles

| Profile | Tests Included | Use Case | Runtime |
|---------|---------------|----------|---------|
| **quick** (default) | `idle_latency`, `peak_injection_bandwidth` | Fast health check, pre-job validation | ~4 min |
| **standard** | `latency_matrix`, `bandwidth_matrix`, `peak_injection_bandwidth` | Regular characterization | ~6 min |
| **full** | All 6 tests | Complete baseline, troubleshooting | ~15 min |
| **numa** | `latency_matrix`, `bandwidth_matrix`, `c2c_latency` | NUMA topology focus | ~5 min |
| **latency** | `idle_latency`, `loaded_latency`, `c2c_latency` | Latency-sensitive workload tuning | ~8 min |

### Recipe Configuration (default_profile JSON)

```json
{
  "binary_path": "/shared/software/intel/mlc/mlc",
  "modules": [],
  "profile": "quick",
  "threshold_mode": "auto_baseline",
  "baseline_tolerance": {
    "warning_percent": 10,
    "fail_percent": 20
  },
  "manual_thresholds": {
    "idle_latency_ns": { "max": 90, "unit": "ns" },
    "peak_bandwidth_all_reads": { "min": 200000, "unit": "MB/s" }
  }
}
```

## Agent Implementation

### Go Package Structure

```
agent/mlc/
├── workflow.go      # WorkflowOrchestrator - runs MLC tests
├── parser.go        # Parses MLC stdout to MLCMetrics
├── config.go        # RunParams, ConfigParams
└── profiles.go      # Profile definitions
```

### Configuration Types

```go
// config.go
type Profile struct {
    Name        string
    Tests       []string
    Description string
}

type RunParams struct {
    RunID      string
    Profile    string            // Profile name or empty for custom
    Tests      []string          // Custom test list (overrides profile)
    Modules    []string          // lmod modules to load
    BinaryPath string            // Explicit path override
    LogDir     string
}

var Profiles = map[string]Profile{
    "quick":    {Tests: []string{"idle_latency", "peak_injection_bandwidth"}},
    "standard": {Tests: []string{"latency_matrix", "bandwidth_matrix", "peak_injection_bandwidth"}},
    "full":     {Tests: []string{"idle_latency", "loaded_latency", "latency_matrix",
                                  "bandwidth_matrix", "peak_injection_bandwidth", "c2c_latency"}},
    "numa":     {Tests: []string{"latency_matrix", "bandwidth_matrix", "c2c_latency"}},
    "latency":  {Tests: []string{"idle_latency", "loaded_latency", "c2c_latency"}},
}
```

### Metrics Model

```go
// agent/core/model/mlc.go
type MLCMetrics struct {
    // Idle latency (unloaded)
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

type LoadedLatencyPoint struct {
    BandwidthMBs float64 `json:"bandwidth_mb_s"`
    LatencyNs    float64 `json:"latency_ns"`
}
```

### CLI Commands

```bash
# Quick health check (default profile)
qis-agent mlc --server <SERVER_URL> --token $TOKEN

# Full characterization with explicit profile
qis-agent mlc --profile full --server <SERVER_URL> --token $TOKEN

# Custom binary path
qis-agent mlc --profile standard --binary-path /opt/intel/mlc/mlc

# With environment modules
qis-agent mlc --profile standard --modules intel-mlc/3.12,gcc/11.2

# Custom test selection (overrides profile)
qis-agent mlc --tests latency_matrix,bandwidth_matrix,idle_latency
```

## Rails Implementation

### New Model: MlcBaseline

```ruby
# app/models/mlc_baseline.rb
class MlcBaseline < ApplicationRecord
  belongs_to :node
  belongs_to :benchmark_run  # The run that established this baseline

  # metric_type examples: "idle_latency", "peak_bandwidth_all_reads",
  #                       "latency_matrix_0_1", "latency_matrix_0_2", etc.
  validates :metric_type, presence: true
  validates :value, presence: true

  scope :for_node, ->(node) { where(node: node) }
  scope :latest, -> { order(created_at: :desc) }
end
```

### Migration

```ruby
# db/migrate/xxx_create_mlc_baselines.rb
class CreateMlcBaselines < ActiveRecord::Migration[7.2]
  def change
    create_table :mlc_baselines do |t|
      t.references :node, null: false, foreign_key: true
      t.references :benchmark_run, null: false, foreign_key: true
      t.string :metric_type, null: false
      t.float :value, null: false
      t.timestamps
    end

    add_index :mlc_baselines, [:node_id, :metric_type]
  end
end
```

### Threshold Evaluation Service

```ruby
# app/services/mlc/threshold_evaluator.rb
module Mlc
  class ThresholdEvaluator
    def initialize(benchmark_run, recipe)
      @run = benchmark_run
      @recipe = recipe
      @node = benchmark_run.node
      @config = recipe.default_profile || {}
    end

    def evaluate
      case @config["threshold_mode"]
      when "manual"
        evaluate_manual_thresholds
      when "auto_baseline"
        evaluate_auto_baseline
      when "cluster_relative"
        evaluate_cluster_relative
      else
        { status: "skipped", message: "No threshold mode configured" }
      end
    end

    private

    def evaluate_manual_thresholds
      # Compare metrics against @config["manual_thresholds"]
    end

    def evaluate_auto_baseline
      # Compare metrics against MlcBaseline records for @node
      # Use @config["baseline_tolerance"]["warning_percent"] and "fail_percent"
    end

    def evaluate_cluster_relative
      # Compare metrics against cluster median from recent runs
    end
  end
end
```

## Node Identification

The MLC integration uses the existing agent identity pattern - no new registration flow needed.

```
┌─────────────────────────────────────────────────────────────────┐
│  Existing Identity Pattern                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Agent generates UUID from hardware fingerprint:             │
│     - /etc/machine-id (primary)                                 │
│     - MAC address (fallback)                                    │
│     - Hostname (last resort)                                    │
│     → SHA256 hash = stable node UUID                            │
│                                                                 │
│  2. UUID persisted to /etc/qis-agent/node_id                    │
│                                                                 │
│  3. All API requests include:                                   │
│     Headers:                                                    │
│       Authorization: Bearer <TOKEN>                             │
│       X-Node-ID: <UUID>                                         │
│       X-Hostname: <hostname>                                    │
│       X-Agent-Version: <version>                                │
│                                                                 │
│  4. Server auto-creates node on first request if needed         │
│     (via ProcessStateService.find_or_create_by_uuid)            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Compute Node (Agent)                                           │
├─────────────────────────────────────────────────────────────────┤
│  1. qis-agent mlc --profile full --server <URL> --token <TOKEN> │
│     ↓                                                           │
│  2. Load modules / resolve binary path                          │
│     ↓                                                           │
│  3. Execute MLC tests sequentially                              │
│     ↓                                                           │
│  4. Parse stdout → MLCMetrics struct                            │
│     ↓                                                           │
│  5. POST /api/v1/benchmark_runs                                 │
│     Headers:                                                    │
│       Authorization: Bearer <TOKEN>                             │
│       X-Node-ID: <UUID>                                         │
│     Body:                                                       │
│     {                                                           │
│       "run_id": "uuid",                                         │
│       "recipe_id": "mlc",                                       │
│       "status": "PASS",                                         │
│       "metrics": { MLCMetrics JSON },                           │
│       "log_content": "raw MLC output",                          │
│       "artifact_uploads": [{ base64 log file }]                 │
│     }                                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Rails Server                                                   │
├─────────────────────────────────────────────────────────────────┤
│  1. BenchmarkRunsController#create                              │
│     - Find/create node via X-Node-ID header                     │
│     ↓                                                           │
│  2. Mlc::ThresholdEvaluator.evaluate(metrics, recipe)           │
│     - Manual: compare against recipe.manual_thresholds          │
│     - Auto-baseline: compare against MlcBaseline for node       │
│     - Cluster-relative: compare against cluster median          │
│     ↓                                                           │
│  3. Store threshold_results JSON in benchmark_run               │
│     ↓                                                           │
│  4. Optionally update MlcBaseline if first run / flagged        │
│     ↓                                                           │
│  5. Broadcast via Turbo Streams to update dashboard             │
└─────────────────────────────────────────────────────────────────┘
```

## Visualization

### 1. NUMA Latency Heatmap

Color-coded matrix showing latency between NUMA nodes:
- **Green** - Low latency (local access, ~78ns)
- **Yellow/Orange** - Medium latency (adjacent nodes, ~112ns)
- **Red** - High latency (remote nodes, ~156-178ns)

Interactive features:
- Toggle between latency and bandwidth matrix
- Hover for exact values
- Export as PNG

### 2. Peak Bandwidth Bar Chart

Horizontal bar chart showing bandwidth at different read/write ratios:
- All Reads
- 3:1 R/W
- 2:1 R/W
- 1:1 R/W
- Stream Triad

### 3. Node Comparison View

Side-by-side comparison cards:
- Select multiple nodes for comparison
- Show deviation percentages (+5%, -4%)
- Color-coded deviation indicators (green = within tolerance, yellow = warning)

### 4. Diagnostic Report

Structured threshold evaluation table:
- Metric name, current value, baseline value, deviation percentage
- Per-metric PASS/WARN/FAIL status
- Summary counts (12 PASS, 2 WARN, 0 FAIL)
- Export to PDF capability

### 5. Loaded Latency Curve

Line chart showing latency vs bandwidth relationship:
- X-axis: Injection bandwidth (MB/s)
- Y-axis: Latency (ns)
- Identifies the "knee" point where latency spikes

## Implementation Phases

### Phase 1: Agent Core
- [ ] Create `agent/mlc/` package structure
- [ ] Implement MLC binary resolution (path/modules/PATH)
- [ ] Implement profile system with 5 pre-defined profiles
- [ ] Implement MLC output parser for all 6 test types
- [ ] Add `qis-agent mlc` CLI command
- [ ] Unit tests for parser

### Phase 2: Rails Backend
- [ ] Create MlcBaseline model and migration
- [ ] Create Mlc::ThresholdEvaluator service
- [ ] Extend BenchmarkRunsController for MLC metrics
- [ ] Add MLC recipe seed data with default profiles
- [ ] Integration tests

### Phase 3: Visualization
- [ ] NUMA latency heatmap component (Stimulus + Chart.js)
- [ ] Peak bandwidth bar chart
- [ ] Loaded latency curve chart
- [ ] Node comparison view
- [ ] Diagnostic report view with threshold table

### Phase 4: Polish
- [ ] PDF export for diagnostic reports
- [ ] Historical trend graphs
- [ ] Cluster-wide outlier detection
- [ ] Documentation and user guide

## Design Reference

See visualization mockup in: `pencil-new.pen` (Intel MLC Benchmark Results frame)

Style guide: Terminal Minimal - dark mode with monospace typography, green accents for pass states, amber for warnings, red for failures.
