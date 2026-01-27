package mlc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseMLCOutput(t *testing.T) {
	// Load test data for valid input test
	validData, err := os.ReadFile(filepath.Join("testdata", "idle_latency.txt"))
	if err != nil {
		t.Fatalf("failed to read test data: %v", err)
	}

	tests := []struct {
		name              string
		input             string
		errContains       string
		wantIdleLatencyNs float64
		wantErr           bool
	}{
		{
			name:              "empty input returns empty metrics",
			input:             "",
			wantIdleLatencyNs: 0,
			wantErr:           false,
		},
		{
			name:              "missing pattern returns empty metrics",
			input:             "Some unrelated MLC output\nwithout idle latency data",
			wantIdleLatencyNs: 0,
			wantErr:           false,
		},
		{
			name:              "valid idle latency output",
			input:             string(validData),
			wantIdleLatencyNs: 78.2,
			wantErr:           false,
		},
		{
			name:              "malformed latency value returns error",
			input:             "Each iteration took 186.5 core clocks ( 78.2.3    ns)",
			wantIdleLatencyNs: 0,
			wantErr:           true,
			errContains:       "failed to parse idle latency value",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			metrics, err := ParseMLCOutput(tt.input)

			if tt.wantErr {
				if err == nil {
					t.Errorf("ParseMLCOutput() expected error, got nil")
					return
				}
				if tt.errContains != "" && !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("ParseMLCOutput() error = %v, want error containing %q", err, tt.errContains)
				}
				return
			}

			if err != nil {
				t.Errorf("ParseMLCOutput() unexpected error: %v", err)
				return
			}

			if metrics.IdleLatencyNs != tt.wantIdleLatencyNs {
				t.Errorf("IdleLatencyNs = %v, want %v", metrics.IdleLatencyNs, tt.wantIdleLatencyNs)
			}
		})
	}
}
