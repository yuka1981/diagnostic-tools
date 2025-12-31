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

type cpuParsingContext struct {
	info           *model.CPUInfo
	physicalIDs    map[string]bool
	coresPerSocket map[string]int
	processorCount int

	currentPhysicalID string
	currentCores      int
	currentModelName  string
	currentFlags      []string
}

func newParsingContext() *cpuParsingContext {
	return &cpuParsingContext{
		info:           &model.CPUInfo{},
		physicalIDs:    make(map[string]bool),
		coresPerSocket: make(map[string]int),
	}
}

// ParseCPUInfo parses the content of /proc/cpuinfo and returns a CPUInfo model.
func ParseCPUInfo(r io.Reader) (*model.CPUInfo, error) {
	scanner := bufio.NewScanner(r)
	ctx := newParsingContext()

	for scanner.Scan() {
		processLine(scanner.Text(), ctx)
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return finalizeCPUInfo(ctx), nil
}

func processLine(line string, ctx *cpuParsingContext) {
	parts := strings.SplitN(line, ":", 2)
	if len(parts) != 2 {
		return
	}

	key := strings.TrimSpace(parts[0])
	value := strings.TrimSpace(parts[1])

	switch key {
	case "processor":
		ctx.processorCount++
		ctx.currentPhysicalID = ""
		ctx.currentCores = 0
	case "model name":
		if ctx.info.ModelName == "" {
			ctx.info.ModelName = value
		}
		ctx.currentModelName = value
	case "physical id":
		ctx.currentPhysicalID = value
		ctx.physicalIDs[value] = true
	case "cpu cores":
		cores, err := strconv.Atoi(value)
		if err == nil {
			ctx.currentCores = cores
		}
	case "flags":
		if len(ctx.info.Flags) == 0 {
			ctx.info.Flags = strings.Fields(value)
		}
		ctx.currentFlags = strings.Fields(value)
	}

	if ctx.currentPhysicalID != "" && ctx.currentCores > 0 {
		ctx.coresPerSocket[ctx.currentPhysicalID] = ctx.currentCores
	}
}

func finalizeCPUInfo(ctx *cpuParsingContext) *model.CPUInfo {
	info := ctx.info
	info.Threads = ctx.processorCount
	info.Sockets = len(ctx.physicalIDs)

	if info.Sockets == 0 {
		info.Sockets = 1
	}

	totalCores := 0
	for _, cores := range ctx.coresPerSocket {
		totalCores += cores
	}
	info.Cores = totalCores

	if info.Cores == 0 {
		info.Cores = info.Threads
	}

	if info.ModelName == "" && ctx.currentModelName != "" {
		info.ModelName = ctx.currentModelName
	}
	if len(info.Flags) == 0 && len(ctx.currentFlags) > 0 {
		info.Flags = ctx.currentFlags
	}

	return info
}
