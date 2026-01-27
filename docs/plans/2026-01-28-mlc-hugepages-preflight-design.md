# MLC Hugepages Pre-flight Check Design

## Problem

When users run MLC benchmarks without hugepages configured, the benchmark fails instantly with an unclear error (`exit status 22`). MLC requires hugepages for accurate memory latency measurements.

## Solution

Add a pre-flight check in the Go agent that validates hugepages before running any MLC tests. On failure, return an actionable error message explaining the problem and how to fix it.

## Implementation

### 1. Pre-flight Check (`agent/mlc/preflight.go`)

New file with:

```go
const MinHugepages = 1000

// CheckHugepages verifies sufficient hugepages are allocated for MLC.
// Returns nil if OK, or an error with actionable guidance.
func CheckHugepages(minPages int) error
```

Behavior:
- Read `/proc/sys/vm/nr_hugepages` to get current count
- Compare against minimum threshold (1000 pages)
- Return structured error if insufficient
- Skip check gracefully on non-Linux systems

Error message format:
```
Hugepages not configured (found: 0, required: 1000)

Fix: echo 4000 > /proc/sys/vm/nr_hugepages (requires root)
```

### 2. Workflow Integration (`agent/mlc/workflow.go`)

Add pre-flight call at start of `Run()`:

```go
func (w *WorkflowOrchestrator) Run(ctx context.Context, params *RunParams) (*model.BenchmarkRun, error) {
    start := time.Now()

    // Pre-flight: Check hugepages before doing anything
    if err := CheckHugepages(MinHugepages); err != nil {
        return w.buildFailedRun(params.RunID, start, "", err.Error()), nil
    }

    // ... rest of existing logic
}
```

### 3. Testing (`agent/mlc/preflight_test.go`)

Test cases:
1. Sufficient hugepages (4000) - expect nil
2. Insufficient hugepages (500) - expect error with guidance
3. Zero hugepages - expect error mentioning "found: 0"
4. Missing procfs file - expect nil (skip gracefully)
5. Malformed file content - handle parse errors

Use path variable for test mocking:
```go
var hugepagesPath = "/proc/sys/vm/nr_hugepages"
```

### 4. Workflow Test (`agent/mlc/workflow_test.go`)

Add one test case for pre-flight failure path.

## UI Impact

No Rails changes needed. The improved error message flows through the existing `error_message` field and displays in the benchmark run detail view.

## Design Decisions

1. **Fail immediately** (vs warn and continue) - MLC explicitly states results are inaccurate without hugepages
2. **Fixed threshold of 1000** (vs NUMA-aware) - Simple and works for most systems
3. **Actionable error message** (vs docs link) - Users can fix immediately without leaving the UI
