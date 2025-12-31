package linux

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// LinuxMemoryCollector collects memory information on Linux systems.
type LinuxMemoryCollector struct {
	Path string
}

// NewLinuxMemoryCollector creates a new collector with default path.
func NewLinuxMemoryCollector() *LinuxMemoryCollector {
	return &LinuxMemoryCollector{Path: "/proc/meminfo"}
}

// Collect reads and parses the memory info.
func (c *LinuxMemoryCollector) Collect() (*model.MemoryInfo, error) {
	file, err := os.Open(c.Path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	return ParseMemInfo(file)
}

// ParseMemInfo parses the content of /proc/meminfo and returns a MemoryInfo model.
func ParseMemInfo(r io.Reader) (*model.MemoryInfo, error) {
	scanner := bufio.NewScanner(r)
	info := &model.MemoryInfo{}

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])

		var target *uint64
		switch key {
		case "MemTotal":
			target = &info.Total
		case "MemFree":
			target = &info.Free
		case "MemAvailable":
			target = &info.Available
		case "Buffers":
			target = &info.Buffers
		case "Cached":
			target = &info.Cached
		case "SwapTotal":
			target = &info.SwapTotal
		case "SwapFree":
			target = &info.SwapFree
		default:
			continue // Not a key we are interested in.
		}

		valueParts := strings.Fields(strings.TrimSpace(parts[1]))
		if len(valueParts) < 1 {
			continue
		}

		valKB, err := strconv.ParseUint(valueParts[0], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("failed to parse value for key %q: %w", key, err)
		}

		// Convert kB to Bytes (1 kB = 1024 bytes in Linux meminfo context generally)
		*target = valKB * 1024
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return info, nil
}
