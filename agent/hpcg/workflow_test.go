package hpcg

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

const testLogName = "HPCG-Benchmark_test.txt"

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

func TestWorkflowOrchestrator_Run_BuildFail(t *testing.T) {
	orchestrator := &WorkflowOrchestrator{
		Runner:  &mockCommandRunner{err: errors.New("build failed")},
		WorkDir: t.TempDir(),
	}
	params := RunParams{BuildCmd: "make"}
	_, err := orchestrator.Run(context.Background(), &params)
	if err == nil {
		t.Error("expected error, got nil")
	}
}

func TestWorkflowOrchestrator_SetupEnvironment_NilLoader(t *testing.T) {
	orchestrator := &WorkflowOrchestrator{ModuleLoader: nil}
	err := orchestrator.setupEnvironment(context.Background(), []string{"mod1"})
	if err != nil {
		t.Errorf("expected nil error when loader is nil, got %v", err)
	}
}

func TestWorkflowOrchestrator_Build_EmptyCmd(t *testing.T) {
	orchestrator := &WorkflowOrchestrator{}
	err := orchestrator.build(context.Background(), "")
	if err != nil {
		t.Errorf("expected nil error for empty build cmd, got %v", err)
	}
}

func TestWorkflowOrchestrator_WriteConfig_Fail(t *testing.T) {
	// Point to a non-existent directory to make WriteFile fail
	orchestrator := &WorkflowOrchestrator{WorkDir: "/non-existent-dir"}
	err := orchestrator.writeConfig(ConfigParams{})
	if err == nil {
		t.Error("expected error when writing config to non-existent dir, got nil")
	}
}

func TestWorkflowOrchestrator_FindLatestLog(t *testing.T) {
	tmpDir := t.TempDir()
	orchestrator := &WorkflowOrchestrator{WorkDir: tmpDir}

	// Create some dummy log files
	startTime := time.Now()
	log1 := filepath.Join(tmpDir, "HPCG-Benchmark_1.txt")
	log2 := filepath.Join(tmpDir, "HPCG-Benchmark_2.txt")

	_ = os.WriteFile(log1, []byte("log1"), 0644)
	time.Sleep(10 * time.Millisecond)
	_ = os.WriteFile(log2, []byte("log2"), 0644)

	t.Run("Success", func(t *testing.T) {
		latest, err := orchestrator.findLatestLog(startTime)
		if err != nil {
			t.Fatalf("findLatestLog failed: %v", err)
		}
		if filepath.Base(latest) != "HPCG-Benchmark_2.txt" {
			t.Errorf("expected HPCG-Benchmark_2.txt, got %s", filepath.Base(latest))
		}
	})

	t.Run("NotFound", func(t *testing.T) {
		futureTime := time.Now().Add(1 * time.Hour)
		_, err := orchestrator.findLatestLog(futureTime)
		if err == nil {
			t.Error("expected error, got nil")
		}
	})
}

func TestWorkflowOrchestrator_ParseResults(t *testing.T) {
	orchestrator := &WorkflowOrchestrator{}
	startTime := time.Now()

	t.Run("FromStdout", func(t *testing.T) {
		output := []byte("Final Summary::HPCG result is VALID with a GFLOP/s rating of= 50.0")
		metrics, status := orchestrator.parseResults(output, startTime, model.BenchmarkStatusPass, "")
		if status != model.BenchmarkStatusPass {
			t.Errorf("expected PASS, got %s", status)
		}
		if metrics.GFLOPS != 50.0 {
			t.Errorf("expected 50.0 GFLOPS, got %f", metrics.GFLOPS)
		}
	})

	t.Run("FromLogFile", func(t *testing.T) {
		tmpDir := t.TempDir()
		orchestrator.WorkDir = tmpDir
		logPath := filepath.Join(tmpDir, "HPCG-Benchmark_test.txt")
		_ = os.WriteFile(logPath, []byte("Final Summary::HPCG result is VALID with a GFLOP/s rating of= 75.0"), 0644)

		metrics, status := orchestrator.parseResults([]byte("no metrics here"), startTime, model.BenchmarkStatusPass, logPath)
		if status != model.BenchmarkStatusPass {
			t.Errorf("expected PASS, got %s", status)
		}
		if metrics.GFLOPS != 75.0 {
			t.Errorf("expected 75.0 GFLOPS, got %f", metrics.GFLOPS)
		}
	})
}

func TestWorkflowOrchestrator_HandleLogStorage(t *testing.T) {
	tmpDir := t.TempDir()
	orchestrator := &WorkflowOrchestrator{WorkDir: tmpDir}
	startTime := time.Now()

	// Create a dummy log in workdir
	sourcePath := filepath.Join(tmpDir, testLogName)
	_ = os.WriteFile(sourcePath, []byte("log content"), 0644)

	t.Run("CustomLogPath", func(t *testing.T) {
		destPath := filepath.Join(t.TempDir(), "custom_log.txt")
		params := &RunParams{LogPath: destPath}

		resultPath := orchestrator.handleLogStorage(params, startTime)
		if resultPath != destPath {
			t.Errorf("expected %s, got %s", destPath, resultPath)
		}
		if _, err := os.Stat(destPath); os.IsNotExist(err) {
			t.Error("dest file was not created")
		}
	})

	t.Run("LogDir", func(t *testing.T) {
		// Re-create source log because it might have been moved
		_ = os.WriteFile(sourcePath, []byte("log content"), 0644)

		logDir := filepath.Join(tmpDir, "logs")
		params := &RunParams{LogDir: logDir}

		resultPath := orchestrator.handleLogStorage(params, startTime)
		expectedPath := filepath.Join(logDir, testLogName)
		if resultPath != expectedPath {
			t.Errorf("expected %s, got %s", expectedPath, resultPath)
		}
		if _, err := os.Stat(expectedPath); os.IsNotExist(err) {
			t.Error("file was not moved to log dir")
		}
	})

	t.Run("FindLatestLogFail", func(t *testing.T) {
		emptyOrchestrator := &WorkflowOrchestrator{WorkDir: t.TempDir()}
		params := &RunParams{LogDir: t.TempDir()}
		resultPath := emptyOrchestrator.handleLogStorage(params, time.Now())
		if resultPath != "" {
			t.Errorf("expected empty result path when no log found, got %s", resultPath)
		}
	})

	t.Run("LogDirMkdirFail", func(t *testing.T) {
		tmpDir := t.TempDir()
		// Create a file where we want a directory
		logDirFile := filepath.Join(tmpDir, "logdir_file")
		_ = os.WriteFile(logDirFile, []byte("data"), 0644)

		orchestrator := &WorkflowOrchestrator{WorkDir: tmpDir}
		params := &RunParams{LogDir: logDirFile}

		// This should not crash, just log warning and return empty path
		resultPath := orchestrator.handleLogStorage(params, time.Now())
		if resultPath != "" {
			t.Errorf("expected empty result path, got %s", resultPath)
		}
	})

	t.Run("LogPathMkdirFail", func(t *testing.T) {
		tmpDir := t.TempDir()
		// Create a file where we want a directory for LogPath
		parentFile := filepath.Join(tmpDir, "parent_file")
		_ = os.WriteFile(parentFile, []byte("data"), 0644)

		logPath := filepath.Join(parentFile, "log.txt")
		orchestrator := &WorkflowOrchestrator{WorkDir: tmpDir}

		// Create a dummy log to trigger the move logic
		_ = os.WriteFile(filepath.Join(tmpDir, testLogName), []byte("log content"), 0644)

		params := &RunParams{LogPath: logPath}
		resultPath := orchestrator.handleLogStorage(params, time.Now())
		if resultPath != logPath {
			t.Errorf("expected %s, got %s", logPath, resultPath)
		}
	})
}

func TestWorkflowOrchestrator_MoveFile_Fallback(t *testing.T) {
	// To test the copy+delete fallback, we can try moving a file to a non-existent dir first,
	// but moveFile handles cross-device links by catching os.Rename error.
	// We can't easily force cross-device link in a unit test, but we can test the fallback logic
	// if we mock os.Rename. But we are using real os package.

	// Let's just test that it works when dest dir exists.
	tmpDir := t.TempDir()
	src := filepath.Join(tmpDir, "src.txt")
	dst := filepath.Join(tmpDir, "dst.txt")
	_ = os.WriteFile(src, []byte("data"), 0644)

	w := &WorkflowOrchestrator{}
	err := w.moveFile(src, dst)
	if err != nil {
		t.Fatalf("moveFile failed: %v", err)
	}

	data, _ := os.ReadFile(dst)
	if string(data) != "data" {
		t.Errorf("expected data, got %s", string(data))
	}
}

func TestWorkflowOrchestrator_MoveFile_RenameFail(t *testing.T) {
	tmpDir := t.TempDir()
	src := filepath.Join(tmpDir, "src.txt")
	_ = os.WriteFile(src, []byte("data"), 0644)

	// Create a directory at destPath. os.Rename(file, dir) should fail.
	dstDir := filepath.Join(tmpDir, "dst_dir")
	_ = os.Mkdir(dstDir, 0755)

	w := &WorkflowOrchestrator{}
	err := w.moveFile(src, dstDir)
	// moveFile fallback will try to os.Open(src) [ok] then os.Create(dstDir) [fail]
	if err == nil {
		t.Error("expected error when destination is a directory, got nil")
	}
}

func TestWorkflowOrchestrator_ParseResults_Error(t *testing.T) {
	orchestrator := &WorkflowOrchestrator{}
	startTime := time.Now()

	t.Run("StdoutParseError", func(t *testing.T) {
		// Output that reValid matches but has malformed number
		output := []byte("Final Summary::HPCG result is VALID with a GFLOP/s rating of= not-a-number")
		metrics, status := orchestrator.parseResults(output, startTime, model.BenchmarkStatusPass, "")

		if status != model.BenchmarkStatusError {
			t.Errorf("expected ERROR, got %s", status)
		}
		if metrics != nil {
			t.Errorf("expected nil metrics on parse error, got %v", metrics)
		}
	})

	t.Run("LogFileParseError", func(t *testing.T) {
		tmpDir := t.TempDir()
		orchestrator.WorkDir = tmpDir
		logPath := filepath.Join(tmpDir, "HPCG-Benchmark_error.txt")
		_ = os.WriteFile(logPath, []byte("Final Summary::HPCG result is VALID with a GFLOP/s rating of= not-a-number"), 0644)

		metrics, status := orchestrator.parseResults([]byte("no metrics"), startTime, model.BenchmarkStatusPass, logPath)
		if status != model.BenchmarkStatusError {
			t.Errorf("expected ERROR, got %s", status)
		}
		if metrics != nil {
			t.Errorf("expected nil metrics, got %v", metrics)
		}
	})
}
