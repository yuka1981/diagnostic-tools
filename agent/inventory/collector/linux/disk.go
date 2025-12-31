package linux

import (
	"context"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
	"strconv"
)

// LinuxDiskCollector collects disk information using the 'df' command.
type LinuxDiskCollector struct {
	Runner ports.CommandRunner
}

// NewLinuxDiskCollector creates a new disk collector.
func NewLinuxDiskCollector(runner ports.CommandRunner) *LinuxDiskCollector {
	return &LinuxDiskCollector{Runner: runner}
}

// Collect executes 'df -B1' and parses the output.
func (c *LinuxDiskCollector) Collect(ctx context.Context) ([]model.DiskInfo, error) {
	output, err := c.Runner.Run(ctx, "df", "-B1")
	if err != nil {
		return nil, err
	}
	return ParseDiskInfo(string(output))
}

// ParseDiskInfo parses the output of 'df -B1'.
func ParseDiskInfo(output string) ([]model.DiskInfo, error) {
	lines := strings.Split(output, "\n")
	var disks []model.DiskInfo

	for i, line := range lines {
		if i == 0 { // Skip header
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 6 {
			continue
		}

		device := fields[0]
		mountpoint := fields[5]

		// Filter out tmpfs, overlay, etc. if desired. For now, we can keep them or filter.
		// Let's filter out typical pseudo-filesystems to keep it clean.
		if strings.HasPrefix(device, "tmpfs") || strings.HasPrefix(device, "overlay") || strings.HasPrefix(device, "shm") {
			continue
		}

		total, _ := strconv.ParseUint(fields[1], 10, 64)
		used, _ := strconv.ParseUint(fields[2], 10, 64)
		free, _ := strconv.ParseUint(fields[3], 10, 64)

		disks = append(disks, model.DiskInfo{
			Device:     device,
			Mountpoint: mountpoint,
			// Fstype is not available in standard df output without -T.
			// We could add -T to args but sticking to simpler parsing for now or assume -T was passed if we change args.
			// Let's stick to simple df -B1 for now.
			Total: total,
			Used:  used,
			Free:  free,
		})
	}
	return disks, nil
}
