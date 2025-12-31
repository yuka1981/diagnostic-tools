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
// It extracts model name, flags, and calculates the number of sockets, cores, and threads.
func ParseCPUInfo(r io.Reader) (*model.CPUInfo, error) {
	scanner := bufio.NewScanner(r)
	info := &model.CPUInfo{}

	// Temporary storage to track unique sockets and cores
	physicalIDs := make(map[string]bool)
	coresPerSocket := make(map[string]int)
	processorCount := 0

	var currentPhysicalID string
	var currentCores int

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
			// Reset per-processor temporary vars
			currentPhysicalID = ""
			currentCores = 0

		case "model name":
			// Capture the first model name encountered
			if info.ModelName == "" {
				info.ModelName = value
			}

		case "physical id":
			currentPhysicalID = value
			physicalIDs[value] = true

		case "cpu cores":
			cores, err := strconv.Atoi(value)
			if err == nil {
				currentCores = cores
			}

		case "flags":
			// Capture the first flags encountered
			if len(info.Flags) == 0 {
				info.Flags = strings.Fields(value)
			}
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

	// Fallback for Cores: if 'cpu cores' field was missing, assume cores equal threads
	if info.Cores == 0 {
		info.Cores = info.Threads
	}

	return info, nil
}

