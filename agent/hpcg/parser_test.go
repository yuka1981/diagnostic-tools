package hpcg

import (
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestParseHPCGLog_Valid(t *testing.T) {
	logContent := `
HPCG-Benchmark
version 3.1
...
Final Summary::HPCG result is VALID with a GFLOP/s rating of= 123.456
Final Summary::HPCG 2.4 rating for historical reasons is= 130.000
Final Summary::Reference version of ComputeDotProduct used= 0.000000e+00 time(s)
Final Summary::This result is VALID with a GFLOP/s rating of= 123.456
Final Summary::Please send the .yaml file to ...
`
	metrics, status, err := ParseHPCGLog(strings.NewReader(logContent))
	if err != nil {
		t.Fatalf("ParseHPCGLog failed: %v", err)
	}

	if status != model.BenchmarkStatusPass {
		t.Errorf("expected PASS, got %s", status)
	}
	if metrics.GFLOPS != 123.456 {
		t.Errorf("expected GFLOPS 123.456, got %f", metrics.GFLOPS)
	}
}

func TestParseHPCGLog_Invalid(t *testing.T) {
	logContent := `
HPCG-Benchmark
...
Final Summary::HPCG result is INVALID.
Final Summary::Please send the .yaml file to ...
`
	metrics, status, err := ParseHPCGLog(strings.NewReader(logContent))
	if err != nil {
		t.Fatalf("ParseHPCGLog failed: %v", err)
	}

	if status != model.BenchmarkStatusFail {
		t.Errorf("expected FAIL, got %s", status)
	}
	if metrics.GFLOPS != 0 {
		t.Errorf("expected GFLOPS 0, got %f", metrics.GFLOPS)
	}
}

func TestParseHPCGLog_NoResult(t *testing.T) {
	logContent := `
HPCG-Benchmark
...
(Crash or incomplete)
`
	_, status, err := ParseHPCGLog(strings.NewReader(logContent))
	if err == nil {
		t.Fatal("expected error for incomplete log, got nil")
	}
	if status != model.BenchmarkStatusError {
		t.Errorf("expected ERROR status, got %s", status)
	}
}
