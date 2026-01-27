package mlc

import (
	"fmt"
	"regexp"
	"strconv"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	// Matches: "Each iteration took 186.5 core clocks ( 78.2    ns)"
	reIdleLatency = regexp.MustCompile(`Each iteration took[\s\d.]+core clocks\s*\(\s*([\d.]+)\s*ns\)`)
)

// ParseMLCOutput parses Intel MLC output and extracts metrics.
// Returns empty metrics (no error) if patterns are not found, since MLC output
// varies by test type. Returns an error only if a pattern matches but the
// value cannot be parsed (malformed output).
func ParseMLCOutput(output string) (*model.MLCMetrics, error) {
	metrics := &model.MLCMetrics{}

	// Parse idle latency
	if matches := reIdleLatency.FindStringSubmatch(output); len(matches) > 1 {
		val, err := strconv.ParseFloat(matches[1], 64)
		if err != nil {
			return nil, fmt.Errorf("failed to parse idle latency value '%s': %w", matches[1], err)
		}
		metrics.IdleLatencyNs = val
	}

	return metrics, nil
}
