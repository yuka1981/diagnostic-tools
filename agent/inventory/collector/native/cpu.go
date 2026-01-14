//go:build linux

package native

import (
	"context"

	"github.com/jaypipes/ghw/pkg/cpu"
	"github.com/jaypipes/ghw/pkg/option"
	"github.com/jaypipes/ghw/pkg/topology"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// CPUProvider abstracts ghw CPU and Topology functions for testability.
type CPUProvider interface {
	CPU(opts ...*option.Option) (*cpu.Info, error)
	Topology(opts ...*option.Option) (*topology.Info, error)
}

// RealCPUProvider is the production implementation using ghw.
type RealCPUProvider struct{}

func (r *RealCPUProvider) CPU(opts ...*option.Option) (*cpu.Info, error) {
	return cpu.New(opts...)
}

func (r *RealCPUProvider) Topology(opts ...*option.Option) (*topology.Info, error) {
	return topology.New(opts...)
}

// NativeCPUCollector collects CPU information using the ghw library.
type NativeCPUCollector struct {
	provider CPUProvider
	opts     []*option.Option
}

// NewNativeCPUCollector creates a new NativeCPUCollector.
// If provider is nil, a default RealCPUProvider is used.
func NewNativeCPUCollector(provider CPUProvider) *NativeCPUCollector {
	if provider == nil {
		provider = &RealCPUProvider{}
	}
	return &NativeCPUCollector{
		provider: provider,
	}
}

// Collect gathers CPU information using the ghw library.
func (c *NativeCPUCollector) Collect(_ context.Context) (*model.CPUInfo, error) {
	cpuInfo, err := c.provider.CPU(c.opts...)
	if err != nil {
		return nil, err
	}

	info := &model.CPUInfo{
		Cores:   int(cpuInfo.TotalCores),
		Threads: int(cpuInfo.TotalThreads),
		Sockets: len(cpuInfo.Processors),
	}

	// Extract info from first processor (model, vendor, flags)
	if len(cpuInfo.Processors) > 0 {
		proc := cpuInfo.Processors[0]
		info.VendorID = proc.Vendor
		info.ModelName = proc.Model
		info.Flags = proc.Capabilities
		info.CoresPerSocket = int(proc.NumCores)

		if proc.NumCores > 0 {
			info.ThreadsPerCore = int(proc.NumThreads) / int(proc.NumCores)
		}
	}

	// Try to get topology for NUMA info (graceful degradation if fails)
	topoInfo, err := c.provider.Topology(c.opts...)
	if err == nil && topoInfo != nil {
		info.NUMANodes = len(topoInfo.Nodes)

		// Build NUMA node to CPU mapping
		if len(topoInfo.Nodes) > 0 {
			info.NUMAInfo = make(map[string]string)
			for _, node := range topoInfo.Nodes {
				if node.Cores == nil {
					continue
				}
				cpuList := ""
				for i, core := range node.Cores {
					for j, lp := range core.LogicalProcessors {
						if i > 0 || j > 0 {
							cpuList += ","
						}
						cpuList += string(rune('0' + lp))
					}
				}
				// Use a proper string conversion for node ID
				nodeIDStr := ""
				if node.ID < 10 {
					nodeIDStr = string(rune('0' + node.ID))
				} else {
					nodeIDStr = intToString(node.ID)
				}
				info.NUMAInfo[nodeIDStr] = cpuList
			}
		}
	}

	return info, nil
}

// intToString converts an int to string without importing strconv.
func intToString(n int) string {
	if n == 0 {
		return "0"
	}
	result := ""
	for n > 0 {
		result = string(rune('0'+n%10)) + result
		n /= 10
	}
	return result
}
