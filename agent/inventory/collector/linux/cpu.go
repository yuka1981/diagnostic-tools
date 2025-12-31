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

type cpuParseState struct {
	physicalIDs    map[string]bool
	coresPerSocket map[string]int
	processorCount int
	currentPhysID  string
	currentCores   int
}

func newCPUParseState() *cpuParseState {
	return &cpuParseState{
		physicalIDs:    make(map[string]bool),
		coresPerSocket: make(map[string]int),
	}
}

func (s *cpuParseState) processLine(key, value string, info *model.CPUInfo) {
	switch key {
	case "processor":
		s.processorCount++
		s.currentPhysID = ""
		s.currentCores = 0
	case "model name":
		if info.ModelName == "" {
			info.ModelName = value
		}
	case "physical id":
		s.currentPhysID = value
		s.physicalIDs[value] = true
	case "cpu cores":
		if cores, err := strconv.Atoi(value); err == nil {
			s.currentCores = cores
		}
	case "flags":
		if len(info.Flags) == 0 {
			info.Flags = strings.Fields(value)
		}
	}

	if s.currentPhysID != "" && s.currentCores > 0 {
		s.coresPerSocket[s.currentPhysID] = s.currentCores
	}
}

func (s *cpuParseState) finalizeCPUInfo(info *model.CPUInfo) {
	info.Threads = s.processorCount
	info.Sockets = len(s.physicalIDs)

	if info.Sockets == 0 {
		info.Sockets = 1
	}

	totalCores := 0
	for _, cores := range s.coresPerSocket {
		totalCores += cores
	}
	info.Cores = totalCores

	if info.Cores == 0 {
		info.Cores = info.Threads
	}
}

// ParseCPUInfo parses the content of /proc/cpuinfo and returns a CPUInfo model.
// It extracts model name, flags, and calculates the number of sockets, cores, and threads.
func ParseCPUInfo(r io.Reader) (*model.CPUInfo, error) {
	scanner := bufio.NewScanner(r)
	info := &model.CPUInfo{}
	state := newCPUParseState()

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])
		state.processLine(key, value, info)
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	state.finalizeCPUInfo(info)
	return info, nil
}

