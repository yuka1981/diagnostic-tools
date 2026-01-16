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

	// Create setup directory to simulate HPCG source already present
	// This skips the auto-clone step
	setupDir := filepath.Join(tmpDir, "setup")
	if err := os.MkdirAll(setupDir, 0755); err != nil {
		t.Fatalf("failed to create setup dir: %v", err)
	}

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

func TestWorkflowOrchestrator_Run_UploadsHpcgDatAsArtifact(t *testing.T) {
	tmpDir := t.TempDir()

	// Create setup directory to simulate HPCG source already present
	setupDir := filepath.Join(tmpDir, "setup")
	if err := os.MkdirAll(setupDir, 0755); err != nil {
		t.Fatalf("failed to create setup dir: %v", err)
	}

	// Create a mock log file that will be found
	logFileName := "HPCG-Benchmark_test.txt"
	logContent := "HPCG-Benchmark\nFinal Summary::HPCG result is VALID with a GFLOP/s rating of= 50.0\n"
	if err := os.WriteFile(filepath.Join(tmpDir, logFileName), []byte(logContent), 0644); err != nil {
		t.Fatalf("failed to create log file: %v", err)
	}

	runner := &mockCommandRunner{
		output: []byte(logContent),
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

	// Verify hpcg.dat is uploaded as an artifact
	var foundHpcgDat bool
	for _, upload := range result.ArtifactUploads {
		if upload.Filename != "hpcg.dat" {
			continue
		}
		foundHpcgDat = true

		// Verify file type
		if upload.FileType != "dat" {
			t.Errorf("expected file type 'dat', got %q", upload.FileType)
		}

		// Verify content is not empty
		if upload.Content == "" {
			t.Error("expected non-empty content for hpcg.dat")
		}

		// Verify size is set
		if upload.Size == 0 {
			t.Error("expected non-zero size for hpcg.dat")
		}

		break
	}

	if !foundHpcgDat {
		t.Errorf("expected hpcg.dat in ArtifactUploads, got filenames: %v", getUploadFilenames(result.ArtifactUploads))
	}
}

func getUploadFilenames(uploads []model.ArtifactUpload) []string {
	names := make([]string, len(uploads))
	for i, u := range uploads {
		names[i] = u.Filename
	}
	return names
}

func TestWorkflowOrchestrator_EnsureHPCGSource(t *testing.T) {
	t.Run("skips clone when setup dir exists", func(t *testing.T) {
		tmpDir := t.TempDir()

		// Create setup directory
		setupDir := filepath.Join(tmpDir, "setup")
		if err := os.MkdirAll(setupDir, 0755); err != nil {
			t.Fatalf("failed to create setup dir: %v", err)
		}

		runner := &mockCommandRunner{}
		orchestrator := &WorkflowOrchestrator{
			Runner:  runner,
			WorkDir: tmpDir,
		}

		err := orchestrator.ensureHPCGSource(context.Background())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}

		// Should not run any commands since setup dir exists
		if len(runner.cmds) != 0 {
			t.Errorf("expected no commands, got %v", runner.cmds)
		}
	})

	t.Run("clones when setup dir missing", func(t *testing.T) {
		tmpDir := t.TempDir()

		// Use a mock that creates the temp directory when clone is called
		runner := &cloningMockRunner{
			workDir: tmpDir,
		}

		orchestrator := &WorkflowOrchestrator{
			Runner:  runner,
			WorkDir: tmpDir,
		}

		err := orchestrator.ensureHPCGSource(context.Background())
		if err != nil {
			t.Errorf("unexpected error: %v", err)
		}

		// Should have run git clone command
		foundClone := false
		for _, cmd := range runner.cmds {
			if strings.Contains(cmd, "git clone") {
				foundClone = true
				break
			}
		}
		if !foundClone {
			t.Errorf("expected git clone command, got %v", runner.cmds)
		}

		// Verify setup directory was created (moved from temp)
		if _, err := os.Stat(filepath.Join(tmpDir, "setup")); os.IsNotExist(err) {
			t.Error("setup directory was not created")
		}
	})
}

// cloningMockRunner simulates git clone by creating temp directory with setup/
type cloningMockRunner struct {
	workDir string
	cmds    []string
}

func (m *cloningMockRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	cmdStr := name
	if len(args) > 0 {
		cmdStr += " " + strings.Join(args, " ")
	}
	m.cmds = append(m.cmds, cmdStr)

	// If this is the git clone command, create the temp directory with setup/
	if strings.Contains(cmdStr, "git clone") {
		tempDir := m.workDir + ".tmp"
		os.MkdirAll(filepath.Join(tempDir, "setup"), 0755)
		os.WriteFile(filepath.Join(tempDir, "README.md"), []byte("test"), 0644)
	}

	return nil, nil
}
