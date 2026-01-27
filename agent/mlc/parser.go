package mlc

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	// Matches: "Each iteration took 186.5 core clocks ( 78.2    ns)"
	reIdleLatency = regexp.MustCompile(`Each iteration took[\s\d.]+core clocks\s*\(\s*([\d.]+)\s*ns\)`)

	// Matches latency matrix header: "Numa node      0     1     2     3"
	reMatrixHeader = regexp.MustCompile(`^Numa node\s+((?:\d+\s*)+)$`)

	// Matches latency matrix row: "       0   78.2  112.4  156.8  178.3"
	reMatrixRow = regexp.MustCompile(`^\s*(\d+)\s+([\d.\s]+)$`)
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

	// Parse latency matrix
	if err := parseLatencyMatrix(output, metrics); err != nil {
		return nil, err
	}

	return metrics, nil
}

// parseLatencyMatrix parses the NUMA latency matrix from MLC output.
// The matrix appears after "Measuring idle latencies" and has format:
//
//	Numa node      0     1     2     3
//	       0   78.2  112.4  156.8  178.3
//	       1  113.1   79.0  179.2  155.4
//	       ...
func parseLatencyMatrix(output string, metrics *model.MLCMetrics) error {
	// Check for the latency matrix marker
	if !strings.Contains(output, "Measuring idle latencies") {
		return nil
	}

	lines := strings.Split(output, "\n")
	var nodeCount int
	var matrix [][]float64
	parsingMatrix := false

	for _, line := range lines {
		// Look for header row to get node count
		if matches := reMatrixHeader.FindStringSubmatch(line); len(matches) > 1 {
			// Count the nodes in header
			fields := strings.Fields(matches[1])
			nodeCount = len(fields)
			parsingMatrix = true
			continue
		}

		// Parse data rows once we've seen the header
		if parsingMatrix {
			if matches := reMatrixRow.FindStringSubmatch(line); len(matches) > 2 {
				values := strings.Fields(matches[2])
				if len(values) != nodeCount {
					return fmt.Errorf("latency matrix row has %d values, expected %d", len(values), nodeCount)
				}

				row := make([]float64, nodeCount)
				for i, v := range values {
					val, err := strconv.ParseFloat(v, 64)
					if err != nil {
						return fmt.Errorf("failed to parse latency value '%s': %w", v, err)
					}
					row[i] = val
				}
				matrix = append(matrix, row)

				// Stop when we have all rows
				if len(matrix) == nodeCount {
					break
				}
			} else if strings.TrimSpace(line) != "" && !strings.HasPrefix(strings.TrimSpace(line), "Numa") {
				// Non-matching non-empty line after header means end of matrix
				break
			}
		}
	}

	if len(matrix) > 0 {
		metrics.LatencyMatrix = matrix
		metrics.NumaNodeCount = nodeCount
	}

	return nil
}
