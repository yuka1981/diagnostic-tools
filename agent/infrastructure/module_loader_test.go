package infrastructure

import (
	"context"
	"os"
	"testing"
)

type mockRunner struct {
	output   []byte
	err      error
	lastCmd  string
	lastArgs []string
}

func (m *mockRunner) Run(ctx context.Context, dir, name string, args ...string) ([]byte, error) {
	m.lastCmd = name
	m.lastArgs = args
	return m.output, m.err
}

func TestRealModuleLoader_Load(t *testing.T) {
	runner := &mockRunner{
		output: []byte("export TEST_VAR=test_val; export PATH=/new/path:$PATH;"),
	}
	loader := NewRealModuleLoader(runner)

	const loadKeyword = "load"

	t.Run("MultipleModules", func(t *testing.T) {
		modules := []string{"mod1", "mod2", "mod3"}
		err := loader.Load(context.Background(), modules)
		if err != nil {
			t.Fatalf("Load failed: %v", err)
		}

		// Verify args passed to modulecmd
		// expected: bash load mod1 mod2 mod3
		foundLoad := false
		modCount := 0
		for i, arg := range runner.lastArgs {
			if arg == loadKeyword {
				foundLoad = true
				// Count modules after "load"
				modCount = len(runner.lastArgs) - i - 1
				break
			}
		}

		if !foundLoad {
			t.Error("expected 'load' in modulecmd args")
		}
		if modCount != 3 {
			t.Errorf("expected 3 modules passed to modulecmd, got %d: %v", modCount, runner.lastArgs)
		}
	})

	t.Run("SpaceSeparatedAndPrefix", func(t *testing.T) {
		// Test the case user mentioned: "ml load compiler/2025.3.0 mkl/2025.3 mpi/2021.17"
		modules := []string{"ml load compiler/2025.3.0 mkl/2025.3 mpi/2021.17"}

		err := loader.Load(context.Background(), modules)
		if err != nil {
			t.Fatalf("Load failed: %v", err)
		}

		modCount := 0
		for i, arg := range runner.lastArgs {
			if arg == loadKeyword {
				modCount = len(runner.lastArgs) - i - 1
				break
			}
		}

		if modCount != 3 {
			t.Errorf("expected 3 modules extracted, got %d: %v", modCount, runner.lastArgs)
		}
	})

	t.Run("ManyModules", func(t *testing.T) {
		modules := []string{"m1", "m2", "m3", "m4", "m5", "m6"}
		err := loader.Load(context.Background(), modules)
		if err != nil {
			t.Fatalf("Load failed: %v", err)
		}

		modCount := 0
		for i, arg := range runner.lastArgs {
			if arg == loadKeyword {
				modCount = len(runner.lastArgs) - i - 1
				break
			}
		}

		if modCount != 6 {
			t.Errorf("expected 6 modules passed, got %d", modCount)
		}
	})
}

func TestRealModuleLoader_ParseAndApply(t *testing.T) {
	loader := NewRealModuleLoader(nil)

	t.Run("SimpleExport", func(t *testing.T) {
		output := "export AGENT_TEST_VAR=hello;"
		err := loader.parseAndApply(output)
		if err != nil {
			t.Fatalf("parseAndApply failed: %v", err)
		}

		val := os.Getenv("AGENT_TEST_VAR")
		if val != "hello" {
			t.Errorf("expected hello, got %q", val)
		}
		os.Unsetenv("AGENT_TEST_VAR")
	})

	t.Run("QuotedExport", func(t *testing.T) {
		output := "export AGENT_TEST_QUOTED=\"world\";"
		err := loader.parseAndApply(output)
		if err != nil {
			t.Fatalf("parseAndApply failed: %v", err)
		}

		val := os.Getenv("AGENT_TEST_QUOTED")
		if val != "world" {
			t.Errorf("expected world, got %q", val)
		}
		os.Unsetenv("AGENT_TEST_QUOTED")
	})

	t.Run("MultiplePathExports", func(t *testing.T) {
		os.Setenv("AGENT_TEST_PATH", "/original")
		defer os.Unsetenv("AGENT_TEST_PATH")

		output := "export AGENT_TEST_PATH=/foo:$AGENT_TEST_PATH; export AGENT_TEST_PATH=/bar:$AGENT_TEST_PATH;"
		err := loader.parseAndApply(output)
		if err != nil {
			t.Fatalf("parseAndApply failed: %v", err)
		}

		val := os.Getenv("AGENT_TEST_PATH")
		// Expected: /bar:/foo:/original
		expected := "/bar:/foo:/original"
		if val != expected {
			t.Errorf("expected %q, got %q", expected, val)
		}
	})
}
