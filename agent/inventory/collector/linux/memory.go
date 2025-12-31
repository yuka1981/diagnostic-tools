package linux

import (
	"bufio"
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
		valueParts := strings.Fields(strings.TrimSpace(parts[1]))
		if len(valueParts) < 1 {
			continue
		}
		
		valKB, err := strconv.ParseUint(valueParts[0], 10, 64)
		if err != nil {
			continue
		}

		// Convert kB to Bytes (1 kB = 1024 bytes in Linux meminfo context generally)
		valBytes := valKB * 1024

		switch key {
		case "MemTotal":
			info.Total = valBytes
		case "MemFree":
			info.Free = valBytes
		case "MemAvailable":
			info.Available = valBytes
		case "Buffers":
			info.Buffers = valBytes
		case "Cached":
			info.Cached = valBytes
		case "SwapTotal":
			info.SwapTotal = valBytes
		case "SwapFree":
			info.SwapFree = valBytes
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return info, nil
}

