package redfish

import (
	"context"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

func TestNewClient(t *testing.T) {
	config := ports.BMCConfig{
		Address:   "192.168.1.100",
		Username:  "admin",
		Password:  "password",
		Port:      443,
		VerifySSL: false,
	}

	client := NewClient(config)
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	if client.config.Address != config.Address {
		t.Errorf("expected Address %q, got %q", config.Address, client.config.Address)
	}
	if client.config.Username != config.Username {
		t.Errorf("expected Username %q, got %q", config.Username, client.config.Username)
	}
	if client.config.Port != config.Port {
		t.Errorf("expected Port %d, got %d", config.Port, client.config.Port)
	}
	if client.config.VerifySSL != config.VerifySSL {
		t.Errorf("expected VerifySSL %v, got %v", config.VerifySSL, client.config.VerifySSL)
	}
}

func TestClient_Close(t *testing.T) {
	t.Run("CloseNotConnected", func(t *testing.T) {
		config := ports.BMCConfig{
			Address:  "192.168.1.100",
			Username: "admin",
			Password: "password",
		}

		client := NewClient(config)
		err := client.Close()
		if err != nil {
			t.Errorf("expected no error from Close on unconnected client, got %v", err)
		}
	})

	t.Run("CloseNilClient", func(t *testing.T) {
		client := &Client{
			config: ports.BMCConfig{
				Address: "192.168.1.100",
			},
			client: nil,
		}
		err := client.Close()
		if err != nil {
			t.Errorf("expected no error from Close on nil client, got %v", err)
		}
	})
}

func TestClient_Connect_InvalidEndpoint(t *testing.T) {
	config := ports.BMCConfig{
		Address:   "invalid-host-that-does-not-exist.local:9999",
		Username:  "admin",
		Password:  "password",
		VerifySSL: false,
	}

	client := NewClient(config)
	err := client.Connect(context.Background())
	if err == nil {
		t.Error("expected error for invalid endpoint")
		client.Close()
	}
}

func TestClient_GetProcessors_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetProcessors(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetMemory_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetMemory(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetStorage_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetStorage(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetNetwork_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetNetwork(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetInfiniband_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetInfiniband(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetBIOS_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetBIOS(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetBMCInfo_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetBMCInfo(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetSensors_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetSensors(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetHealth_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	_, err := client.GetHealth(context.Background())
	if err == nil {
		t.Error("expected error when not connected")
	}
}

func TestClient_GetInventory_NotConnected(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := NewClient(config)
	// GetInventory should not return error even when not connected,
	// it should return empty inventory with partial data
	inventory, err := client.GetInventory(context.Background())
	if err != nil {
		t.Errorf("GetInventory should not return error, got %v", err)
	}
	if inventory == nil {
		t.Error("expected non-nil inventory")
	}
}

// Test interface compliance
func TestClient_ImplementsBMCClient(t *testing.T) {
	var _ ports.BMCClient = (*Client)(nil)
}

// Test helper functions
func TestFormatSpeed(t *testing.T) {
	tests := []struct {
		expected string
		input    int
	}{
		{"", 0},
		{"100Mbps", 100},
		{"1Gbps", 1000},
		{"10Gbps", 10000},
		{"25Gbps", 25000},
		{"100Gbps", 100000},
	}

	for _, tc := range tests {
		result := formatSpeed(tc.input)
		if result != tc.expected {
			t.Errorf("formatSpeed(%d) = %q, expected %q", tc.input, result, tc.expected)
		}
	}
}

func TestIsInfinibandAdapter(t *testing.T) {
	tests := []struct {
		name     string
		model    string
		expected bool
	}{
		{"Ethernet Adapter", "Intel X710", false},
		{"Infiniband HCA", "Mellanox ConnectX-6", true},
		{"mlx5_0", "ConnectX-5", true},
		{"Network Adapter", "Mellanox Technologies", true},
		{"IB HCA 0", "ConnectX", true},
		{"Regular NIC", "Broadcom BCM", false},
	}

	for _, tc := range tests {
		result := isInfinibandAdapter(tc.name, tc.model)
		if result != tc.expected {
			t.Errorf("isInfinibandAdapter(%q, %q) = %v, expected %v",
				tc.name, tc.model, result, tc.expected)
		}
	}
}

// Test with direct gofish client injection for specific scenarios
func TestClient_WithNilClient(t *testing.T) {
	client := &Client{
		config: ports.BMCConfig{
			Address: "192.168.1.100",
		},
		client: nil,
	}

	ctx := context.Background()

	// All methods should return error when client is nil
	_, err := client.GetProcessors(ctx)
	if err == nil {
		t.Error("expected error from GetProcessors with nil client")
	}

	_, err = client.GetMemory(ctx)
	if err == nil {
		t.Error("expected error from GetMemory with nil client")
	}

	_, err = client.GetStorage(ctx)
	if err == nil {
		t.Error("expected error from GetStorage with nil client")
	}

	_, err = client.GetNetwork(ctx)
	if err == nil {
		t.Error("expected error from GetNetwork with nil client")
	}

	_, err = client.GetInfiniband(ctx)
	if err == nil {
		t.Error("expected error from GetInfiniband with nil client")
	}

	_, err = client.GetBIOS(ctx)
	if err == nil {
		t.Error("expected error from GetBIOS with nil client")
	}

	_, err = client.GetBMCInfo(ctx)
	if err == nil {
		t.Error("expected error from GetBMCInfo with nil client")
	}

	_, err = client.GetSensors(ctx)
	if err == nil {
		t.Error("expected error from GetSensors with nil client")
	}

	_, err = client.GetHealth(ctx)
	if err == nil {
		t.Error("expected error from GetHealth with nil client")
	}
}

// Test endpoint URL building
func TestClient_EndpointBuilding(t *testing.T) {
	t.Run("DefaultPort", func(t *testing.T) {
		config := ports.BMCConfig{
			Address:  "192.168.1.100",
			Username: "admin",
			Password: "password",
		}
		client := NewClient(config)
		// Port is 0, so no port in URL
		if client.config.Port != 0 {
			t.Error("expected Port 0")
		}
	})

	t.Run("CustomPort", func(t *testing.T) {
		config := ports.BMCConfig{
			Address:  "192.168.1.100",
			Username: "admin",
			Password: "password",
			Port:     8443,
		}
		client := NewClient(config)
		if client.config.Port != 8443 {
			t.Errorf("expected Port 8443, got %d", client.config.Port)
		}
	})

	t.Run("SSLVerification", func(t *testing.T) {
		configWithSSL := ports.BMCConfig{
			Address:   "192.168.1.100",
			Username:  "admin",
			Password:  "password",
			VerifySSL: true,
		}
		client := NewClient(configWithSSL)
		if !client.config.VerifySSL {
			t.Error("expected VerifySSL true")
		}

		configWithoutSSL := ports.BMCConfig{
			Address:   "192.168.1.100",
			Username:  "admin",
			Password:  "password",
			VerifySSL: false,
		}
		client = NewClient(configWithoutSSL)
		if client.config.VerifySSL {
			t.Error("expected VerifySSL false")
		}
	})
}

func TestClient_ConfigProtocol(t *testing.T) {
	tests := []struct {
		name     string
		protocol string
	}{
		{"Auto", "auto"},
		{"Redfish", "redfish"},
		{"IPMI", "ipmi"},
		{"Empty", ""},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			config := ports.BMCConfig{
				Address:  "192.168.1.100",
				Username: "admin",
				Password: "password",
				Protocol: tc.protocol,
			}
			client := NewClient(config)
			if client.config.Protocol != tc.protocol {
				t.Errorf("expected Protocol %q, got %q", tc.protocol, client.config.Protocol)
			}
		})
	}
}
