package linux

import (
	"bufio"
	"io"
	"os"
	"strconv"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// LinuxCPUCollector collects CPU information on Linux systems.
type LinuxCPUCollector struct {
	Path string
}

// NewLinuxCPUCollector creates a new collector with default path.
func NewLinuxCPUCollector() *LinuxCPUCollector {
	return &LinuxCPUCollector{Path: "/proc/cpuinfo"}
}

// Collect reads and parses the CPU info.
func (c *LinuxCPUCollector) Collect() (*model.CPUInfo, error) {
	file, err := os.Open(c.Path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	return ParseCPUInfo(file)
}

// ParseCPUInfo parses the content of /proc/cpuinfo and returns a CPUInfo model.
func ParseCPUInfo(r io.Reader) (*model.CPUInfo, error) {
	scanner := bufio.NewScanner(r)
	info := &model.CPUInfo{}

	// Temporary storage to track unique sockets and cores
	physicalIDs := make(map[string]bool)
	coresPerSocket := make(map[string]int)
	processorCount := 0

	var currentPhysicalID string
	var currentCores int
	var currentModelName string
	var currentFlags []string

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "processor":
			processorCount++
			// Reset per-processor temporary vars if needed
			currentPhysicalID = ""
			currentCores = 0

		case "model name":
			if info.ModelName == "" {
				info.ModelName = value
			}
			currentModelName = value

		case "physical id":
			currentPhysicalID = value
			physicalIDs[value] = true

		case "cpu cores":
			cores, err := strconv.Atoi(value)
			if err == nil {
				currentCores = cores
			}

		case "flags":
			if len(info.Flags) == 0 {
				info.Flags = strings.Fields(value)
			}
			currentFlags = strings.Fields(value)
		}

		// Update cores mapping if we have both physical ID and cores count for this block
		if currentPhysicalID != "" && currentCores > 0 {
			coresPerSocket[currentPhysicalID] = currentCores
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	info.Threads = processorCount
	info.Sockets = len(physicalIDs)

	// Fallback for Sockets if no physical id found (e.g. some VMs)
	if info.Sockets == 0 {
		info.Sockets = 1
	}

	// Calculate total cores
	totalCores := 0
	for _, cores := range coresPerSocket {
		totalCores += cores
	}
	info.Cores = totalCores

	// Fallback for Cores
	if info.Cores == 0 {
		// If 'cpu cores' field was missing, assume 1 core per thread or just equal to threads
		info.Cores = info.Threads
	}

	// Ensure we captured ModelName and Flags if they appeared later or simpler format
	if info.ModelName == "" && currentModelName != "" {
		info.ModelName = currentModelName
	}
	if len(info.Flags) == 0 && len(currentFlags) > 0 {
		info.Flags = currentFlags
	}

	return info, nil
}
