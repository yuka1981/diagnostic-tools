package hpcg

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

var (
	// reValid matches lines like "Final Summary::HPCG result is VALID with a GFLOP/s rating of= 123.456"
	// and "Final Summary::This result is VALID..."
	reValid   = regexp.MustCompile(`^Final Summary::.*is VALID with a GFLOP/s rating of=\s*([\d\.]+)`)
	reInvalid = regexp.MustCompile(`^Final Summary::HPCG result is INVALID\.?`)
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
			gflops, err := strconv.ParseFloat(matches[1], 64)
			if err != nil {
				return nil, model.BenchmarkStatusError, fmt.Errorf("failed to parse GFLOPS value '%s': %w", matches[1], err)
			}
			metrics.GFLOPS = gflops
			break
		} else if reInvalid.MatchString(line) {
			status = model.BenchmarkStatusFail
			break
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

// ParseHPCGLogFile opens and parses the specified HPCG log file.
func ParseHPCGLogFile(path string) (*model.HPCGMetrics, model.BenchmarkStatus, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, model.BenchmarkStatusError, err
	}
	defer f.Close()
	return ParseHPCGLog(f)
}

