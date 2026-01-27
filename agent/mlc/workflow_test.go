package mlc

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

type mockRunner struct {
	outputs map[string]string
	cmds    []string
}

// skipHugepagesCheck sets hugepagesPath to a non-existent path to skip the check.
// Returns a cleanup function to restore the original path.
func skipHugepagesCheck() func() {
	oldPath := hugepagesPath
	hugepagesPath = "/nonexistent/path/nr_hugepages"
	return func() { hugepagesPath = oldPath }
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
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
			"--peak_injection_bandwidth": `Intel(R) Memory Latency Checker - v3.12
Measuring Peak Injection Memory Bandwidths for various Read/Write Ratios
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

	if result.Status != model.BenchmarkStatusPass {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusPass)
	}

	if result.RecipeID != "mlc" {
		t.Errorf("RecipeID = %s, want mlc", result.RecipeID)
	}

	// Verify both tests were executed
	if len(runner.cmds) != 2 {
		t.Errorf("expected 2 commands, got %d: %v", len(runner.cmds), runner.cmds)
	}
}

func TestWorkflowOrchestrator_Run_CustomTests(t *testing.T) {
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
		},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID: "test-run-456",
		Tests: []string{"idle_latency"},
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	if result.Status != model.BenchmarkStatusPass {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusPass)
	}

	// Verify only one test was executed
	if len(runner.cmds) != 1 {
		t.Errorf("expected 1 command, got %d: %v", len(runner.cmds), runner.cmds)
	}
}

func TestWorkflowOrchestrator_Run_BinaryPathOverride(t *testing.T) {
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
		},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID:      "test-run-789",
		Tests:      []string{"idle_latency"},
		BinaryPath: "/custom/path/mlc",
	}

	_, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	// Verify custom binary path was used
	if len(runner.cmds) != 1 {
		t.Fatalf("expected 1 command, got %d", len(runner.cmds))
	}

	if !strings.HasPrefix(runner.cmds[0], "/custom/path/mlc") {
		t.Errorf("expected command to use custom binary path, got: %s", runner.cmds[0])
	}
}

func TestWorkflowOrchestrator_Run_UnknownTest(t *testing.T) {
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID: "test-run-unknown",
		Tests: []string{"nonexistent_test"},
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Status != model.BenchmarkStatusFail {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusFail)
	}

	if !strings.Contains(result.ErrorMessage, "Unknown test") {
		t.Errorf("expected 'Unknown test' in error message, got: %s", result.ErrorMessage)
	}
}

func TestWorkflowOrchestrator_Run_UnknownProfile(t *testing.T) {
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID:   "test-run-unknown-profile",
		Profile: "nonexistent_profile",
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Status != model.BenchmarkStatusFail {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusFail)
	}

	if !strings.Contains(result.ErrorMessage, "unknown profile") {
		t.Errorf("expected 'unknown profile' in error message, got: %s", result.ErrorMessage)
	}
}

func TestWorkflowOrchestrator_Run_DefaultProfile(t *testing.T) {
	defer skipHugepagesCheck()()

	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
			"--peak_injection_bandwidth": `Intel(R) Memory Latency Checker - v3.12
Measuring Peak Injection Memory Bandwidths for various Read/Write Ratios
ALL Reads        :	298450.0`,
		},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	// Empty profile should default to "quick"
	params := &RunParams{
		RunID: "test-run-default",
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	if result.Status != model.BenchmarkStatusPass {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusPass)
	}

	// Quick profile has 2 tests: idle_latency and peak_injection_bandwidth
	if len(runner.cmds) != 2 {
		t.Errorf("expected 2 commands for default (quick) profile, got %d: %v", len(runner.cmds), runner.cmds)
	}
}

func TestWorkflowOrchestrator_Run_HugepagesCheckFails(t *testing.T) {
	// Create temp file with insufficient hugepages (0)
	tmpDir := t.TempDir()
	tmpFile := tmpDir + "/nr_hugepages"
	if err := os.WriteFile(tmpFile, []byte("0\n"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}

	// Override hugepages path for testing
	oldPath := hugepagesPath
	hugepagesPath = tmpFile
	defer func() { hugepagesPath = oldPath }()

	runner := &mockRunner{
		outputs: map[string]string{
			"--idle_latency": `Intel(R) Memory Latency Checker - v3.12
Each iteration took 186.5 core clocks ( 78.2    ns)`,
		},
	}

	w := &WorkflowOrchestrator{
		Runner:     runner,
		BinaryPath: "/opt/intel/mlc/mlc",
	}

	params := &RunParams{
		RunID: "test-run-hugepages-fail",
		Tests: []string{"idle_latency"},
	}

	result, err := w.Run(context.Background(), params)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify workflow returns failed run
	if result.Status != model.BenchmarkStatusFail {
		t.Errorf("Status = %s, want %s", result.Status, model.BenchmarkStatusFail)
	}

	// Verify error message mentions hugepages
	if !strings.Contains(result.ErrorMessage, "Hugepages") {
		t.Errorf("expected error message to mention 'Hugepages', got: %s", result.ErrorMessage)
	}

	// Verify no commands were executed (pre-flight failed before tests)
	if len(runner.cmds) != 0 {
		t.Errorf("expected 0 commands (pre-flight should fail first), got %d: %v", len(runner.cmds), runner.cmds)
	}
}
