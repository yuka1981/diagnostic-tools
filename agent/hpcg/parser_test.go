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
		expectError    bool
	}{
		{
			name: "Valid Result",
			logContent: `
HPCG-Benchmark
version 3.1
...
Final Summary::HPCG result is VALID with a GFLOP/s rating of= 123.456
Final Summary::HPCG 2.4 rating for historical reasons is= 130.000
Final Summary::Reference version of ComputeDotProduct used= 0.000000e+00 time(s)
Final Summary::This result is VALID with a GFLOP/s rating of= 123.456
Final Summary::Please send the .yaml file to ...
`,
			expectedStatus: model.BenchmarkStatusPass,
			expectedGFLOPS: 123.456,
			expectError:    false,
		},
		{
			name: "Invalid Result",
			logContent: `
HPCG-Benchmark
...
Final Summary::HPCG result is INVALID.
Final Summary::Please send the .yaml file to ...
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
(Crash or incomplete)
`,
			expectedStatus: model.BenchmarkStatusError,
			expectError:    true,
		},
		{
			name: "Malformed GFLOPS",
			logContent: `
HPCG-Benchmark
Final Summary::HPCG result is VALID with a GFLOP/s rating of= not-a-number
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
				// Verify status is Error if that's what we return on error
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

			if metrics != nil && metrics.GFLOPS != tc.expectedGFLOPS {
				t.Errorf("expected GFLOPS %f, got %f", tc.expectedGFLOPS, metrics.GFLOPS)
			}
		})
	}
}
