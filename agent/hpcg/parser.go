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
	reValid = regexp.MustCompile(`^Final Summary::.*is VALID with a GFLOP/s rating of=\s*(\S+)`)
	// reInvalid matches "Final Summary::HPCG result is INVALID"
	reInvalid = regexp.MustCompile(`^Final Summary::HPCG result is INVALID\.?`)
	// reTime matches "Final Summary::Results are valid but execution time (sec) is=51.5755"
	// or "Benchmark Time Summary::Total=51.5755"
	reTime = regexp.MustCompile(`^(?:Final Summary::.*execution time \(sec\) is=|Benchmark Time Summary::Total=)\s*(\S+)`)
	// reResidual matches "Reproducibility Information::Scaled residual mean=4.99963e-08"
	reResidual = regexp.MustCompile(`^Reproducibility Information::Scaled residual mean=\s*(\S+)`)
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
		} else if reInvalid.MatchString(line) {
			status = model.BenchmarkStatusFail
		}

		if matches := reTime.FindStringSubmatch(line); len(matches) > 1 {
			timeVal, err := strconv.ParseFloat(matches[1], 64)
			if err != nil {
				return nil, model.BenchmarkStatusError, fmt.Errorf("failed to parse execution time value '%s': %w", matches[1], err)
			}
			metrics.ExecutionTime = timeVal
		}

		if matches := reResidual.FindStringSubmatch(line); len(matches) > 1 {
			resVal, err := strconv.ParseFloat(matches[1], 64)
			if err != nil {
				return nil, model.BenchmarkStatusError, fmt.Errorf("failed to parse residual value '%s': %w", matches[1], err)
			}
			metrics.Residual = resVal
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
