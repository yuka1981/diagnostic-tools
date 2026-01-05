package linux

import (
	"bufio"
	"context"
	"fmt"
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
func (c *LinuxCPUCollector) Collect(ctx context.Context) (*model.CPUInfo, error) {
	// In a real implementation with heavy I/O, we should check ctx.Done().
	// For now, just keeping the signature consistent.
	file, err := os.Open(c.Path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	info, err := ParseCPUInfo(file)
	if err != nil {
		return nil, err
	}

	// Supplement with info from /sys
	c.collectSysInfo(info)

	return info, nil
}

func (c *LinuxCPUCollector) collectSysInfo(info *model.CPUInfo) {
	// CPU Frequency
	if max, err := os.ReadFile("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"); err == nil {
		if freq, err := strconv.ParseFloat(strings.TrimSpace(string(max)), 64); err == nil {
			info.CPUMaxMHz = fmt.Sprintf("%.4f", freq/1000.0)
		}
	}
	if min, err := os.ReadFile("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq"); err == nil {
		if freq, err := strconv.ParseFloat(strings.TrimSpace(string(min)), 64); err == nil {
			info.CPUMinMHz = fmt.Sprintf("%.4f", freq/1000.0)
		}
	}

	// NUMA Nodes
	if files, err := os.ReadDir("/sys/devices/system/node"); err == nil {
		count := 0
		info.NUMAInfo = make(map[string]string)
		for _, f := range files {
			if strings.HasPrefix(f.Name(), "node") {
				count++
				nodeID := strings.TrimPrefix(f.Name(), "node")
				cpuListPath := "/sys/devices/system/node/" + f.Name() + "/cpulist"
				if content, err := os.ReadFile(cpuListPath); err == nil {
					info.NUMAInfo[nodeID] = strings.TrimSpace(string(content))
				}
			}
		}
		info.NUMANodes = count
	}

	// Caches
	c.collectCacheInfo(info)
}

func (c *LinuxCPUCollector) collectCacheInfo(info *model.CPUInfo) {
	// Maps to store unique caches: key = "level:type:shared_cpu_list" -> value = size in bytes
	caches := make(map[string]uint64)
	// Maps to store count of unique caches per level/type: key = "level:type" -> count
	cacheCounts := make(map[string]int)

	cpuDirs, err := os.ReadDir("/sys/devices/system/cpu")
	if err != nil {
		return
	}

	for _, cpuDir := range cpuDirs {
		if !strings.HasPrefix(cpuDir.Name(), "cpu") || !strings.ContainsAny(cpuDir.Name(), "0123456789") {
			continue
		}

		cacheIndices, err := os.ReadDir("/sys/devices/system/cpu/" + cpuDir.Name() + "/cache")
		if err != nil {
			continue
		}

		for _, idx := range cacheIndices {
			if !strings.HasPrefix(idx.Name(), "index") {
				continue
			}
			path := "/sys/devices/system/cpu/" + cpuDir.Name() + "/cache/" + idx.Name()

			level, _ := os.ReadFile(path + "/level")
			type_, _ := os.ReadFile(path + "/type")
			sizeStr, _ := os.ReadFile(path + "/size")
			sharedList, _ := os.ReadFile(path + "/shared_cpu_list")

			l := strings.TrimSpace(string(level))
			t := strings.TrimSpace(string(type_))
			s := strings.TrimSpace(string(sizeStr))
			sl := strings.TrimSpace(string(sharedList))

			// Unique key for this cache instance
			key := fmt.Sprintf("%s:%s:%s", l, t, sl)
			
			if _, exists := caches[key]; !exists {
				// Parse size (e.g., "32K", "1M")
				var sizeBytes uint64
				var multiplier uint64 = 1
				if strings.HasSuffix(s, "K") {
					multiplier = 1024
					s = strings.TrimSuffix(s, "K")
				} else if strings.HasSuffix(s, "M") {
					multiplier = 1024 * 1024
					s = strings.TrimSuffix(s, "M")
				} else if strings.HasSuffix(s, "G") {
					multiplier = 1024 * 1024 * 1024
					s = strings.TrimSuffix(s, "G")
				}

				if val, err := strconv.ParseUint(s, 10, 64); err == nil {
					sizeBytes = val * multiplier
					caches[key] = sizeBytes
					
					// Increment instance count
					countKey := fmt.Sprintf("%s:%s", l, t)
					cacheCounts[countKey]++
				}
			}
		}
	}

	// Aggregate and format results
	aggregate := func(targetLevel, targetType string) (uint64, int) {
		var total uint64
		var count int
		
		// For L1, we specifically look for Data/Instruction/Unified
		// For L2/L3, usually Unified
		
		targetKey := fmt.Sprintf("%s:%s", targetLevel, targetType)
		if c, ok := cacheCounts[targetKey]; ok {
			count = c
		}

		for key, size := range caches {
			parts := strings.Split(key, ":")
			if parts[0] == targetLevel && parts[1] == targetType {
				total += size
			}
		}
		return total, count
	}

	format := func(bytes uint64, count int) string {
		if count == 0 {
			return ""
		}
		
		var sizeStr string
		if bytes >= 1024*1024*1024 {
			sizeStr = fmt.Sprintf("%.1f GiB", float64(bytes)/1024.0/1024.0/1024.0)
		} else if bytes >= 1024*1024 {
			sizeStr = fmt.Sprintf("%.1f MiB", float64(bytes)/1024.0/1024.0)
		} else if bytes >= 1024 {
			sizeStr = fmt.Sprintf("%.1f KiB", float64(bytes)/1024.0)
		} else {
			sizeStr = fmt.Sprintf("%d B", bytes)
		}
		
		instanceStr := "instance"
		if count > 1 {
			instanceStr = "instances"
		}
		return fmt.Sprintf("%s (%d %s)", sizeStr, count, instanceStr)
	}

	// L1d
	if size, count := aggregate("1", "Data"); count > 0 {
		info.L1dCache = format(size, count)
	}
	// L1i
	if size, count := aggregate("1", "Instruction"); count > 0 {
		info.L1iCache = format(size, count)
	}
	// L2 (Usually Unified)
	if size, count := aggregate("2", "Unified"); count > 0 {
		info.L2Cache = format(size, count)
	} else if size, count := aggregate("2", "Data"); count > 0 { // Fallback if L2 is separated
		info.L2Cache = format(size, count)
	}
	// L3
	if size, count := aggregate("3", "Unified"); count > 0 {
		info.L3Cache = format(size, count)
	}
}

type cpuParseState struct {
	physicalIDs    map[string]bool
	coresPerSocket map[string]int
	threadsPerCore map[string]int
	currentPhysID  string
	currentCoreID  string
	processorCount int
	currentCores   int
	implementer    string
	part           string
	revision       string
	vendorID       string
	architecture   string
	bogomips       string
}

func newCPUParseState() *cpuParseState {
	return &cpuParseState{
		physicalIDs:    make(map[string]bool),
		coresPerSocket: make(map[string]int),
		threadsPerCore: make(map[string]int),
	}
}

func (s *cpuParseState) processLine(key, value string, info *model.CPUInfo) {
	switch key {
	case "processor":
		s.processorCount++
		s.currentPhysID = ""
		s.currentCoreID = ""
		s.currentCores = 0
	case "model name":
		if info.ModelName == "" {
			info.ModelName = value
		}
	case "vendor_id", "CPU implementer":
		if s.vendorID == "" {
			s.vendorID = value
		}
	case "physical id":
		s.currentPhysID = value
		s.physicalIDs[value] = true
	case "core id":
		s.currentCoreID = value
	case "cpu cores":
		if cores, err := strconv.Atoi(value); err == nil {
			s.currentCores = cores
		}
	case "flags", "Features":
		if len(info.Flags) == 0 {
			info.Flags = strings.Fields(value)
		}
	case "CPU architecture":
		s.architecture = value
	case "CPU part":
		if s.part == "" {
			s.part = value
		}
	case "CPU revision":
		if s.revision == "" {
			s.revision = value
		}
	case "bogomips", "BogoMIPS":
		if s.bogomips == "" {
			s.bogomips = value
		}
	}

	if s.currentPhysID != "" && s.currentCores > 0 {
		s.coresPerSocket[s.currentPhysID] = s.currentCores
	}
}

func (s *cpuParseState) finalizeCPUInfo(info *model.CPUInfo) {
	info.Threads = s.processorCount
	info.CPUs = s.processorCount
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

	// Calculate topology details
	if info.Sockets > 0 {
		info.CoresPerSocket = info.Cores / info.Sockets
	}
	if info.Cores > 0 {
		info.ThreadsPerCore = info.Threads / info.Cores
	}

	// Vendor, Architecture, Stepping, BogoMIPS
	info.VendorID = s.vendorID
	if s.architecture != "" {
		info.Architecture = s.architecture
	}
	info.Stepping = s.revision
	info.BogoMIPS = s.bogomips

	// Fallback for ModelName on ARM systems
	if info.ModelName == "" && (s.vendorID != "" || s.part != "") {
		info.ModelName = "AArch64 Processor"
		if s.vendorID != "" && s.part != "" {
			info.ModelName = "AArch64 Processor (" + s.vendorID + ":" + s.part + ")"
		}
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
