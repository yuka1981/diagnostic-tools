package ports

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

// Test constants.
const testStatusWarning = "Warning"

func TestBMCConfig_JSON(t *testing.T) {
	original := BMCConfig{
		Address:   "192.168.1.100",
		Username:  "admin",
		Password:  "secret",
		Protocol:  "redfish",
		Port:      443,
		VerifySSL: true,
	}

	t.Run("Marshal", func(t *testing.T) {
		data, err := json.Marshal(original)
		if err != nil {
			t.Fatalf("failed to marshal BMCConfig: %v", err)
		}
		if len(data) == 0 {
			t.Error("expected non-empty JSON data")
		}
	})

	t.Run("Unmarshal", func(t *testing.T) {
		data, _ := json.Marshal(original)
		var decoded BMCConfig
		err := json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCConfig: %v", err)
		}

		if decoded.Address != original.Address {
			t.Errorf("expected Address %q, got %q", original.Address, decoded.Address)
		}
		if decoded.Username != original.Username {
			t.Errorf("expected Username %q, got %q", original.Username, decoded.Username)
		}
		if decoded.Password != original.Password {
			t.Errorf("expected Password %q, got %q", original.Password, decoded.Password)
		}
		if decoded.Protocol != original.Protocol {
			t.Errorf("expected Protocol %q, got %q", original.Protocol, decoded.Protocol)
		}
		if decoded.Port != original.Port {
			t.Errorf("expected Port %d, got %d", original.Port, decoded.Port)
		}
		if decoded.VerifySSL != original.VerifySSL {
			t.Errorf("expected VerifySSL %v, got %v", original.VerifySSL, decoded.VerifySSL)
		}
	})

	t.Run("EmptyStruct", func(t *testing.T) {
		empty := BMCConfig{}
		data, err := json.Marshal(empty)
		if err != nil {
			t.Fatalf("failed to marshal empty BMCConfig: %v", err)
		}

		var decoded BMCConfig
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal empty BMCConfig: %v", err)
		}
	})

	t.Run("DefaultValues", func(t *testing.T) {
		config := BMCConfig{
			Address:  "192.168.1.100",
			Username: "admin",
			Password: "secret",
		}
		data, err := json.Marshal(config)
		if err != nil {
			t.Fatalf("failed to marshal BMCConfig with defaults: %v", err)
		}

		var decoded BMCConfig
		err = json.Unmarshal(data, &decoded)
		if err != nil {
			t.Fatalf("failed to unmarshal BMCConfig: %v", err)
		}

		// Port should be 0 (default int value)
		if decoded.Port != 0 {
			t.Errorf("expected Port 0, got %d", decoded.Port)
		}
		// VerifySSL should be false (default bool value)
		if decoded.VerifySSL != false {
			t.Errorf("expected VerifySSL false, got %v", decoded.VerifySSL)
		}
		// Protocol should be empty string
		if decoded.Protocol != "" {
			t.Errorf("expected Protocol empty, got %q", decoded.Protocol)
		}
	})

	t.Run("AllProtocols", func(t *testing.T) {
		protocols := []string{"auto", "redfish", "ipmi"}
		for _, protocol := range protocols {
			config := BMCConfig{
				Address:  "192.168.1.100",
				Protocol: protocol,
			}
			data, err := json.Marshal(config)
			if err != nil {
				t.Fatalf("failed to marshal BMCConfig with protocol %q: %v", protocol, err)
			}

			var decoded BMCConfig
			err = json.Unmarshal(data, &decoded)
			if err != nil {
				t.Fatalf("failed to unmarshal BMCConfig with protocol %q: %v", protocol, err)
			}

			if decoded.Protocol != protocol {
				t.Errorf("expected Protocol %q, got %q", protocol, decoded.Protocol)
			}
		}
	})
}

// mockBMCClient is a mock implementation of BMCClient for testing interface compliance.
type mockBMCClient struct {
	connectFunc       func(ctx context.Context) error
	closeFunc         func() error
	getInventoryFunc  func(ctx context.Context) (*model.BMCInventory, error)
	getProcessorsFunc func(ctx context.Context) ([]model.BMCProcessor, error)
	getMemoryFunc     func(ctx context.Context) ([]model.BMCMemoryModule, error)
	getStorageFunc    func(ctx context.Context) ([]model.BMCStorageDrive, error)
	getNetworkFunc    func(ctx context.Context) ([]model.BMCNetworkAdapter, error)
	getInfinibandFunc func(ctx context.Context) ([]model.BMCInfinibandAdapter, error)
	getBIOSFunc       func(ctx context.Context) (*model.BMCBIOSInfo, error)
	getBMCInfoFunc    func(ctx context.Context) (*model.BMCControllerInfo, error)
	getSensorsFunc    func(ctx context.Context) ([]model.BMCSensorReading, error)
	getHealthFunc     func(ctx context.Context) (*model.BMCHealthSummary, error)
}

func (m *mockBMCClient) Connect(ctx context.Context) error {
	if m.connectFunc != nil {
		return m.connectFunc(ctx)
	}
	return nil
}

func (m *mockBMCClient) Close() error {
	if m.closeFunc != nil {
		return m.closeFunc()
	}
	return nil
}

func (m *mockBMCClient) GetInventory(ctx context.Context) (*model.BMCInventory, error) {
	if m.getInventoryFunc != nil {
		return m.getInventoryFunc(ctx)
	}
	return &model.BMCInventory{}, nil
}

func (m *mockBMCClient) GetProcessors(ctx context.Context) ([]model.BMCProcessor, error) {
	if m.getProcessorsFunc != nil {
		return m.getProcessorsFunc(ctx)
	}
	return []model.BMCProcessor{}, nil
}

func (m *mockBMCClient) GetMemory(ctx context.Context) ([]model.BMCMemoryModule, error) {
	if m.getMemoryFunc != nil {
		return m.getMemoryFunc(ctx)
	}
	return []model.BMCMemoryModule{}, nil
}

func (m *mockBMCClient) GetStorage(ctx context.Context) ([]model.BMCStorageDrive, error) {
	if m.getStorageFunc != nil {
		return m.getStorageFunc(ctx)
	}
	return []model.BMCStorageDrive{}, nil
}

func (m *mockBMCClient) GetNetwork(ctx context.Context) ([]model.BMCNetworkAdapter, error) {
	if m.getNetworkFunc != nil {
		return m.getNetworkFunc(ctx)
	}
	return []model.BMCNetworkAdapter{}, nil
}

func (m *mockBMCClient) GetInfiniband(ctx context.Context) ([]model.BMCInfinibandAdapter, error) {
	if m.getInfinibandFunc != nil {
		return m.getInfinibandFunc(ctx)
	}
	return []model.BMCInfinibandAdapter{}, nil
}

func (m *mockBMCClient) GetBIOS(ctx context.Context) (*model.BMCBIOSInfo, error) {
	if m.getBIOSFunc != nil {
		return m.getBIOSFunc(ctx)
	}
	return &model.BMCBIOSInfo{}, nil
}

func (m *mockBMCClient) GetBMCInfo(ctx context.Context) (*model.BMCControllerInfo, error) {
	if m.getBMCInfoFunc != nil {
		return m.getBMCInfoFunc(ctx)
	}
	return &model.BMCControllerInfo{}, nil
}

func (m *mockBMCClient) GetSensors(ctx context.Context) ([]model.BMCSensorReading, error) {
	if m.getSensorsFunc != nil {
		return m.getSensorsFunc(ctx)
	}
	return []model.BMCSensorReading{}, nil
}

func (m *mockBMCClient) GetHealth(ctx context.Context) (*model.BMCHealthSummary, error) {
	if m.getHealthFunc != nil {
		return m.getHealthFunc(ctx)
	}
	return &model.BMCHealthSummary{}, nil
}

// Test that mock implementation satisfies the interface.
func TestBMCClientInterfaceCompliance(t *testing.T) {
	var _ BMCClient = &mockBMCClient{}
}

func TestMockBMCClient(t *testing.T) {
	ctx := context.Background()

	t.Run("DefaultBehavior", func(t *testing.T) {
		mock := &mockBMCClient{}

		if err := mock.Connect(ctx); err != nil {
			t.Errorf("expected no error from Connect, got %v", err)
		}
		if err := mock.Close(); err != nil {
			t.Errorf("expected no error from Close, got %v", err)
		}
		if _, err := mock.GetInventory(ctx); err != nil {
			t.Errorf("expected no error from GetInventory, got %v", err)
		}
		if _, err := mock.GetProcessors(ctx); err != nil {
			t.Errorf("expected no error from GetProcessors, got %v", err)
		}
		if _, err := mock.GetMemory(ctx); err != nil {
			t.Errorf("expected no error from GetMemory, got %v", err)
		}
		if _, err := mock.GetStorage(ctx); err != nil {
			t.Errorf("expected no error from GetStorage, got %v", err)
		}
		if _, err := mock.GetNetwork(ctx); err != nil {
			t.Errorf("expected no error from GetNetwork, got %v", err)
		}
		if _, err := mock.GetInfiniband(ctx); err != nil {
			t.Errorf("expected no error from GetInfiniband, got %v", err)
		}
		if _, err := mock.GetBIOS(ctx); err != nil {
			t.Errorf("expected no error from GetBIOS, got %v", err)
		}
		if _, err := mock.GetBMCInfo(ctx); err != nil {
			t.Errorf("expected no error from GetBMCInfo, got %v", err)
		}
		if _, err := mock.GetSensors(ctx); err != nil {
			t.Errorf("expected no error from GetSensors, got %v", err)
		}
		if _, err := mock.GetHealth(ctx); err != nil {
			t.Errorf("expected no error from GetHealth, got %v", err)
		}
	})

	t.Run("CustomInventory", func(t *testing.T) {
		expectedInventory := &model.BMCInventory{
			Processors: []model.BMCProcessor{
				{Socket: "CPU0", Model: "Intel Xeon", Cores: 20},
			},
		}

		mock := &mockBMCClient{
			getInventoryFunc: func(ctx context.Context) (*model.BMCInventory, error) {
				return expectedInventory, nil
			},
		}

		inventory, err := mock.GetInventory(ctx)
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if len(inventory.Processors) != 1 {
			t.Errorf("expected 1 processor, got %d", len(inventory.Processors))
		}
		if inventory.Processors[0].Socket != "CPU0" {
			t.Errorf("expected Socket 'CPU0', got %q", inventory.Processors[0].Socket)
		}
	})

	t.Run("CustomSensors", func(t *testing.T) {
		expectedSensors := []model.BMCSensorReading{
			{Name: "CPU0 Temp", Value: 45.5, Unit: "Celsius", Status: "OK"},
			{Name: "Fan1", Value: 3500, Unit: "RPM", Status: "OK"},
		}

		mock := &mockBMCClient{
			getSensorsFunc: func(ctx context.Context) ([]model.BMCSensorReading, error) {
				return expectedSensors, nil
			},
		}

		sensors, err := mock.GetSensors(ctx)
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if len(sensors) != 2 {
			t.Errorf("expected 2 sensors, got %d", len(sensors))
		}
		if sensors[0].Name != "CPU0 Temp" {
			t.Errorf("expected sensor name 'CPU0 Temp', got %q", sensors[0].Name)
		}
	})

	t.Run("CustomHealth", func(t *testing.T) {
		expectedHealth := &model.BMCHealthSummary{
			Overall: testStatusWarning,
			Components: map[string]string{
				"CPU":     "OK",
				"Memory":  "OK",
				"Storage": testStatusWarning,
			},
		}

		mock := &mockBMCClient{
			getHealthFunc: func(ctx context.Context) (*model.BMCHealthSummary, error) {
				return expectedHealth, nil
			},
		}

		health, err := mock.GetHealth(ctx)
		if err != nil {
			t.Errorf("expected no error, got %v", err)
		}
		if health.Overall != testStatusWarning {
			t.Errorf("expected Overall 'Warning', got %q", health.Overall)
		}
		if health.Components["Storage"] != testStatusWarning {
			t.Errorf("expected Storage 'Warning', got %q", health.Components["Storage"])
		}
	})
}
