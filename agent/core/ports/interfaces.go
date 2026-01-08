package ports

import (
	"context"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// InventoryCollector defines the interface for collecting node inventory data.
type InventoryCollector interface {
	// Collect gathers information about the host and returns a NodeState.
	Collect(ctx context.Context) (*model.NodeState, error)
}

// SystemCollector defines the interface for collecting specific system metrics.
type SystemCollector interface {
	GetHostInfo(ctx context.Context) (*model.HostInfo, error)
	GetCPUInfo(ctx context.Context) (*model.CPUInfo, error)
	GetMemInfo(ctx context.Context) (*model.MemoryInfo, error)
	GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error)
	GetNetInfo(ctx context.Context) ([]model.NetInfo, error)
	GetDMIInfo(ctx context.Context) (*model.HostDMIInfo, error)
}

// Uploader defines the interface for sending data to a remote server.
type Uploader interface {
	// Upload sends the given payload to the configured endpoint.
	// The payload can be NodeState or BenchmarkRun.
	Upload(ctx context.Context, payload interface{}) error

	// CheckAuth verifies if the configured credentials are valid.
	CheckAuth(ctx context.Context) error
}

// CommandRunner defines the interface for executing system commands.
// This abstraction allows for mocking command execution in tests.
type CommandRunner interface {
	// Run executes a command with the given arguments and returns the combined stdout/stderr output.
	// dir specifies the working directory. If empty, uses the current directory.
	Run(ctx context.Context, dir, name string, args ...string) ([]byte, error)
}
