package hpcg

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

type mockCommandRunner struct {
	output []byte
	err    error
	cmds   []string
}

func (m *mockCommandRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	cmdStr := name
	if len(args) > 0 {
		cmdStr += " " + strings.Join(args, " ")
	}
	m.cmds = append(m.cmds, cmdStr)
	return m.output, m.err
}

type mockModuleLoader struct {
	loaded []string
}

func (m *mockModuleLoader) Load(ctx context.Context, modules []string) error {
	m.loaded = append(m.loaded, modules...)
	return nil
}

func TestWorkflowOrchestrator_Run(t *testing.T) {
	tmpDir := t.TempDir()

	validLog := `
HPCG-Benchmark
Final Summary::HPCG result is VALID with a GFLOP/s rating of= 100.0
`
	runner := &mockCommandRunner{
		output: []byte(validLog),
	}
	loader := &mockModuleLoader{}

	orchestrator := &WorkflowOrchestrator{
		Runner:       runner,
		ModuleLoader: loader,
		WorkDir:      tmpDir,
	}

	params := RunParams{
		RunID:    "test-run",
		Modules:  []string{"mpi/openmpi"},
		BuildCmd: "make",
		RunCmd:   "./xhpcg",
		Config: ConfigParams{
			NX: 104, NY: 104, NZ: 104, RunTimeSeconds: 60,
		},
	}

	result, err := orchestrator.Run(context.Background(), &params)
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	// Verify hpcg.dat created
	datPath := filepath.Join(tmpDir, "hpcg.dat")
	if _, err := os.Stat(datPath); os.IsNotExist(err) {
		t.Error("hpcg.dat was not created")
	}

	// Verify modules loaded
	if len(loader.loaded) != 1 || loader.loaded[0] != "mpi/openmpi" {
		t.Errorf("expected module loaded, got %v", loader.loaded)
	}

	// Verify commands
	// 1. Build: bash -c make
	// 2. Run: bash -c ./xhpcg
	if len(runner.cmds) != 2 {
		t.Errorf("expected 2 commands, got %d: %v", len(runner.cmds), runner.cmds)
	}
	if runner.cmds[0] != "bash -c make" {
		t.Errorf("expected build command 'bash -c make', got %q", runner.cmds[0])
	}
	if runner.cmds[1] != "bash -c ./xhpcg" {
		t.Errorf("expected run command 'bash -c ./xhpcg', got %q", runner.cmds[1])
	}

	// Verify Result
	if result.Status != model.BenchmarkStatusPass {
		t.Errorf("expected status PASS, got %s", result.Status)
	}

	var metrics model.HPCGMetrics
	if err := json.Unmarshal(result.Metrics, &metrics); err != nil {
		t.Fatalf("failed to unmarshal metrics: %v", err)
	}
	if metrics.GFLOPS != 100.0 {
		t.Errorf("expected 100.0 GFLOPS, got %f", metrics.GFLOPS)
	}
}
