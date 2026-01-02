package hpcg

import (
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestParseHPCGLog(t *testing.T) {
	testCases := []struct {
		name           string
		logContent     string
		expectedStatus model.BenchmarkStatus
		expectedGFLOPS float64
		expectedTime   float64
		expectedRes    float64
		expectError    bool
	}{
		{
			name: "Valid Result Full",
			logContent: `
HPCG-Benchmark
version 3.1
...
Benchmark Time Summary::Total=51.5755
Reproducibility Information::Scaled residual mean=4.99963e-08
Final Summary::HPCG result is VALID with a GFLOP/s rating of= 123.456
Final Summary::Results are valid but execution time (sec) is=51.5755
`,
			expectedStatus: model.BenchmarkStatusPass,
			expectedGFLOPS: 123.456,
			expectedTime:   51.5755,
			expectedRes:    4.99963e-08,
			expectError:    false,
		},
		{
			name: "Invalid Result",
			logContent: `
HPCG-Benchmark
...
Final Summary::HPCG result is INVALID.
`,
			expectedStatus: model.BenchmarkStatusFail,
			expectedGFLOPS: 0,
			expectError:    false,
		},
		{
			name: "Incomplete Log",
			logContent: `
HPCG-Benchmark
...
`,
			expectedStatus: model.BenchmarkStatusError,
			expectError:    true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			metrics, status, err := ParseHPCGLog(strings.NewReader(tc.logContent))

			if tc.expectError {
				if err == nil {
					t.Error("expected error, got nil")
				}
				if status != model.BenchmarkStatusError {
					t.Errorf("expected status ERROR, got %s", status)
				}
				return
			}

			if err != nil {
				t.Fatalf("ParseHPCGLog failed: %v", err)
			}

			if status != tc.expectedStatus {
				t.Errorf("expected status %s, got %s", tc.expectedStatus, status)
			}

			if metrics.GFLOPS != tc.expectedGFLOPS {
				t.Errorf("expected GFLOPS %f, got %f", tc.expectedGFLOPS, metrics.GFLOPS)
			}
			if metrics.ExecutionTime != tc.expectedTime {
				t.Errorf("expected Time %f, got %f", tc.expectedTime, metrics.ExecutionTime)
			}
			if metrics.Residual != tc.expectedRes {
				t.Errorf("expected Residual %e, got %e", tc.expectedRes, metrics.Residual)
			}
		})
	}
}
