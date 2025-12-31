package linux

import (
	"bufio"
	"context"
	"os"
	"runtime"
	"strings"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

const (
	defaultPlatform = "linux"
	familyDebian    = "debian"
	familyRhel      = "rhel"
)

// LinuxHostCollector collects host information on Linux systems.
type LinuxHostCollector struct {
	Runner        ports.CommandRunner
	OSReleasePath string
}

// NewLinuxHostCollector creates a new host collector.
func NewLinuxHostCollector(runner ports.CommandRunner) *LinuxHostCollector {
	return &LinuxHostCollector{
		Runner:        runner,
		OSReleasePath: "/etc/os-release",
	}
}

// Collect collects host information.
func (c *LinuxHostCollector) Collect(ctx context.Context) (*model.HostInfo, error) {
	hostname, err := os.Hostname()
	if err != nil {
		return nil, err
	}
	kernel, err := c.getKernelVersion(ctx)
	if err != nil {
		return nil, err
	}
	platform, version, family := c.getOSRelease()

	return &model.HostInfo{
		Hostname:        hostname,
		OS:              runtime.GOOS,
		Platform:        platform,
		PlatformFamily:  family,
		PlatformVersion: version,
		Kernel:          kernel,
		Arch:            runtime.GOARCH,
	}, nil
}

func (c *LinuxHostCollector) getKernelVersion(ctx context.Context) (string, error) {
	out, err := c.Runner.Run(ctx, "uname", "-r")
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func (c *LinuxHostCollector) getOSRelease() (platform, version, family string) {
	f, err := os.Open(c.OSReleasePath)
	if err != nil {
		return defaultPlatform, "", ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	vals := make(map[string]string)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		val := strings.Trim(parts[1], "\"")
		vals[key] = val
	}

	platform = vals["ID"]
	version = vals["VERSION_ID"]
	family = vals["ID_LIKE"]

	if family == "" {
		// Fallback simple heuristics if ID_LIKE is missing
		if _, err := os.Stat("/etc/debian_version"); err == nil {
			family = familyDebian
		} else if _, err := os.Stat("/etc/redhat-release"); err == nil {
			family = familyRhel
		}
	}

	return platform, version, family
}
