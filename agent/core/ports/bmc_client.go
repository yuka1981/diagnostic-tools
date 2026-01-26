package ports

import (
	"context"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// BMCClient defines the interface for BMC communication.
type BMCClient interface {
	// Connect establishes connection to BMC.
	Connect(ctx context.Context) error

	// Close closes the connection.
	Close() error

	// GetInventory retrieves complete hardware inventory.
	GetInventory(ctx context.Context) (*model.BMCInventory, error)

	// GetProcessors retrieves CPU information.
	GetProcessors(ctx context.Context) ([]model.BMCProcessor, error)

	// GetMemory retrieves memory module information.
	GetMemory(ctx context.Context) ([]model.BMCMemoryModule, error)

	// GetStorage retrieves storage device information.
	GetStorage(ctx context.Context) ([]model.BMCStorageDrive, error)

	// GetNetwork retrieves network adapter information.
	GetNetwork(ctx context.Context) ([]model.BMCNetworkAdapter, error)

	// GetInfiniband retrieves Infiniband adapter information.
	GetInfiniband(ctx context.Context) ([]model.BMCInfinibandAdapter, error)

	// GetBIOS retrieves BIOS information.
	GetBIOS(ctx context.Context) (*model.BMCBIOSInfo, error)

	// GetBMCInfo retrieves BMC controller information.
	GetBMCInfo(ctx context.Context) (*model.BMCControllerInfo, error)

	// GetSensors retrieves all sensor readings.
	GetSensors(ctx context.Context) ([]model.BMCSensorReading, error)

	// GetHealth retrieves system health summary.
	GetHealth(ctx context.Context) (*model.BMCHealthSummary, error)
}

// BMCConfig holds configuration for BMC connection.
type BMCConfig struct {
	Address   string `json:"address"`
	Username  string `json:"username"`
	Password  string `json:"password"`
	Protocol  string `json:"protocol"` // "auto", "redfish", "ipmi"
	Port      int    `json:"port"`
	VerifySSL bool   `json:"verify_ssl"`
}
