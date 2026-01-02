package hpcg

import (
	"bufio"
	"fmt"
	"io"
	"regexp"
	"strconv"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	reValid   = regexp.MustCompile(`Final Summary::HPCG result is VALID with a GFLOP/s rating of=\s*([\d\.]+)`)
	reInvalid = regexp.MustCompile(`Final Summary::HPCG result is INVALID`)
)

// ParseHPCGLog parses the HPCG output log to extract metrics and status.
func ParseHPCGLog(r io.Reader) (*model.HPCGMetrics, model.BenchmarkStatus, error) {
	scanner := bufio.NewScanner(r)
	metrics := &model.HPCGMetrics{}
	status := model.BenchmarkStatusUnknown

	for scanner.Scan() {
		line := scanner.Text()

		if matches := reValid.FindStringSubmatch(line); len(matches) > 1 {
			status = model.BenchmarkStatusPass
			if gflops, err := strconv.ParseFloat(matches[1], 64); err == nil {
				metrics.GFLOPS = gflops
			}
			// We could break here if we only care about GFLOPS, but there might be other info.
			// The log might contain multiple "VALID" lines, usually they are consistent.
		}

		if reInvalid.MatchString(line) {
			status = model.BenchmarkStatusFail
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, model.BenchmarkStatusError, err
	}

	if status == model.BenchmarkStatusUnknown {
		return nil, model.BenchmarkStatusError, fmt.Errorf("failed to parse HPCG result from log")
	}

	return metrics, status, nil
}
