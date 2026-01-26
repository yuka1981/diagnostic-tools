package bmc

import (
	"context"
	"errors"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/bmc/ipmi"
	"github.com/yuka1981/diagnostic-tools/agent/bmc/redfish"
	"github.com/yuka1981/diagnostic-tools/agent/core/model"
	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// MockBMCClient is a mock implementation of ports.BMCClient for testing.
type MockBMCClient struct {
	ConnectFunc       func(ctx context.Context) error
	CloseFunc         func() error
	GetInventoryFunc  func(ctx context.Context) (*model.BMCInventory, error)
	GetProcessorsFunc func(ctx context.Context) ([]model.BMCProcessor, error)
	GetMemoryFunc     func(ctx context.Context) ([]model.BMCMemoryModule, error)
	GetStorageFunc    func(ctx context.Context) ([]model.BMCStorageDrive, error)
	GetNetworkFunc    func(ctx context.Context) ([]model.BMCNetworkAdapter, error)
	GetInfinibandFunc func(ctx context.Context) ([]model.BMCInfinibandAdapter, error)
	GetBIOSFunc       func(ctx context.Context) (*model.BMCBIOSInfo, error)
	GetBMCInfoFunc    func(ctx context.Context) (*model.BMCControllerInfo, error)
	GetSensorsFunc    func(ctx context.Context) ([]model.BMCSensorReading, error)
	GetHealthFunc     func(ctx context.Context) (*model.BMCHealthSummary, error)
	ProtocolType      string // "redfish" or "ipmi" for testing DetectedProtocol
}

func (m *MockBMCClient) Connect(ctx context.Context) error {
	if m.ConnectFunc != nil {
		return m.ConnectFunc(ctx)
	}
	return nil
}

func (m *MockBMCClient) Close() error {
	if m.CloseFunc != nil {
		return m.CloseFunc()
	}
	return nil
}

func (m *MockBMCClient) GetInventory(ctx context.Context) (*model.BMCInventory, error) {
	if m.GetInventoryFunc != nil {
		return m.GetInventoryFunc(ctx)
	}
	return &model.BMCInventory{}, nil
}

func (m *MockBMCClient) GetProcessors(ctx context.Context) ([]model.BMCProcessor, error) {
	if m.GetProcessorsFunc != nil {
		return m.GetProcessorsFunc(ctx)
	}
	return []model.BMCProcessor{}, nil
}

func (m *MockBMCClient) GetMemory(ctx context.Context) ([]model.BMCMemoryModule, error) {
	if m.GetMemoryFunc != nil {
		return m.GetMemoryFunc(ctx)
	}
	return []model.BMCMemoryModule{}, nil
}

func (m *MockBMCClient) GetStorage(ctx context.Context) ([]model.BMCStorageDrive, error) {
	if m.GetStorageFunc != nil {
		return m.GetStorageFunc(ctx)
	}
	return []model.BMCStorageDrive{}, nil
}

func (m *MockBMCClient) GetNetwork(ctx context.Context) ([]model.BMCNetworkAdapter, error) {
	if m.GetNetworkFunc != nil {
		return m.GetNetworkFunc(ctx)
	}
	return []model.BMCNetworkAdapter{}, nil
}

func (m *MockBMCClient) GetInfiniband(ctx context.Context) ([]model.BMCInfinibandAdapter, error) {
	if m.GetInfinibandFunc != nil {
		return m.GetInfinibandFunc(ctx)
	}
	return []model.BMCInfinibandAdapter{}, nil
}

func (m *MockBMCClient) GetBIOS(ctx context.Context) (*model.BMCBIOSInfo, error) {
	if m.GetBIOSFunc != nil {
		return m.GetBIOSFunc(ctx)
	}
	return &model.BMCBIOSInfo{}, nil
}

func (m *MockBMCClient) GetBMCInfo(ctx context.Context) (*model.BMCControllerInfo, error) {
	if m.GetBMCInfoFunc != nil {
		return m.GetBMCInfoFunc(ctx)
	}
	return &model.BMCControllerInfo{}, nil
}

func (m *MockBMCClient) GetSensors(ctx context.Context) ([]model.BMCSensorReading, error) {
	if m.GetSensorsFunc != nil {
		return m.GetSensorsFunc(ctx)
	}
	return []model.BMCSensorReading{}, nil
}

func (m *MockBMCClient) GetHealth(ctx context.Context) (*model.BMCHealthSummary, error) {
	if m.GetHealthFunc != nil {
		return m.GetHealthFunc(ctx)
	}
	return &model.BMCHealthSummary{}, nil
}

// MockClientFactory is a mock implementation of ClientFactory for testing.
type MockClientFactory struct {
	RedfishConnectErr error
	IPMIConnectErr    error
	RedfishClient     *MockBMCClient
	IPMIClient        *MockBMCClient
	RedfishCallCount  int
	IPMICallCount     int
}

//nolint:gocritic // config passed by value to match interface
func (f *MockClientFactory) NewRedfishClient(config ports.BMCConfig) ports.BMCClient {
	_ = config // config used to satisfy interface
	f.RedfishCallCount++
	if f.RedfishClient != nil {
		if f.RedfishConnectErr != nil {
			f.RedfishClient.ConnectFunc = func(ctx context.Context) error {
				return f.RedfishConnectErr
			}
		}
		return f.RedfishClient
	}
	// Return a default mock that succeeds or fails based on RedfishConnectErr
	return &MockBMCClient{
		ConnectFunc: func(ctx context.Context) error {
			return f.RedfishConnectErr
		},
		ProtocolType: "redfish",
	}
}

//nolint:gocritic // config passed by value to match interface
func (f *MockClientFactory) NewIPMIClient(config ports.BMCConfig) ports.BMCClient {
	_ = config // config used to satisfy interface
	f.IPMICallCount++
	if f.IPMIClient != nil {
		if f.IPMIConnectErr != nil {
			f.IPMIClient.ConnectFunc = func(ctx context.Context) error {
				return f.IPMIConnectErr
			}
		}
		return f.IPMIClient
	}
	// Return a default mock that succeeds or fails based on IPMIConnectErr
	return &MockBMCClient{
		ConnectFunc: func(ctx context.Context) error {
			return f.IPMIConnectErr
		},
		ProtocolType: "ipmi",
	}
}

func TestNewClient_ExplicitRedfish(t *testing.T) {
	factory := &MockClientFactory{
		RedfishClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				return nil
			},
			ProtocolType: "redfish",
		},
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolRedfish,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	if factory.RedfishCallCount != 1 {
		t.Errorf("expected Redfish factory called once, got %d", factory.RedfishCallCount)
	}
	if factory.IPMICallCount != 0 {
		t.Errorf("expected IPMI factory not called, got %d", factory.IPMICallCount)
	}
}

func TestNewClient_ExplicitIPMI(t *testing.T) {
	factory := &MockClientFactory{
		IPMIClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				return nil
			},
			ProtocolType: "ipmi",
		},
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolIPMI,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	if factory.IPMICallCount != 1 {
		t.Errorf("expected IPMI factory called once, got %d", factory.IPMICallCount)
	}
	if factory.RedfishCallCount != 0 {
		t.Errorf("expected Redfish factory not called, got %d", factory.RedfishCallCount)
	}
}

func TestNewClient_AutoRedfishSucceeds(t *testing.T) {
	factory := &MockClientFactory{
		RedfishClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				return nil
			},
			ProtocolType: "redfish",
		},
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolAuto,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	// In auto mode, Redfish should be tried first and succeed
	if factory.RedfishCallCount != 1 {
		t.Errorf("expected Redfish factory called once, got %d", factory.RedfishCallCount)
	}
	if factory.IPMICallCount != 0 {
		t.Errorf("expected IPMI factory not called when Redfish succeeds, got %d", factory.IPMICallCount)
	}
}

func TestNewClient_AutoRedfishFailsFallbackToIPMI(t *testing.T) {
	factory := &MockClientFactory{
		RedfishConnectErr: errors.New("Redfish connection failed"),
		IPMIClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				return nil
			},
			ProtocolType: "ipmi",
		},
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolAuto,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err != nil {
		t.Fatalf("expected no error (IPMI fallback), got %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	// Redfish should be tried first
	if factory.RedfishCallCount != 1 {
		t.Errorf("expected Redfish factory called once, got %d", factory.RedfishCallCount)
	}
	// IPMI should be tried as fallback
	if factory.IPMICallCount != 1 {
		t.Errorf("expected IPMI factory called once as fallback, got %d", factory.IPMICallCount)
	}
}

func TestNewClient_AutoEmptyProtocol(t *testing.T) {
	factory := &MockClientFactory{
		RedfishClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				return nil
			},
			ProtocolType: "redfish",
		},
	}

	// Empty protocol should behave like "auto"
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: "",
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if client == nil {
		t.Fatal("expected non-nil client")
	}
	if factory.RedfishCallCount != 1 {
		t.Errorf("expected Redfish factory called once, got %d", factory.RedfishCallCount)
	}
}

func TestNewClient_AutoBothFail(t *testing.T) {
	factory := &MockClientFactory{
		RedfishConnectErr: errors.New("Redfish connection failed"),
		IPMIConnectErr:    errors.New("IPMI connection failed"),
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolAuto,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err == nil {
		t.Fatal("expected error when both protocols fail")
	}
	if client != nil {
		t.Error("expected nil client when both protocols fail")
	}
	// Both should be tried
	if factory.RedfishCallCount != 1 {
		t.Errorf("expected Redfish factory called once, got %d", factory.RedfishCallCount)
	}
	if factory.IPMICallCount != 1 {
		t.Errorf("expected IPMI factory called once, got %d", factory.IPMICallCount)
	}
	// Error should be from IPMI (last attempted)
	if err.Error() != "IPMI connection failed" {
		t.Errorf("expected IPMI error message, got %v", err)
	}
}

func TestNewClient_InvalidProtocol(t *testing.T) {
	factory := &MockClientFactory{}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: "invalid-protocol",
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err == nil {
		t.Fatal("expected error for invalid protocol")
	}
	if client != nil {
		t.Error("expected nil client for invalid protocol")
	}
	expectedErr := "unsupported protocol: invalid-protocol"
	if err.Error() != expectedErr {
		t.Errorf("expected error %q, got %q", expectedErr, err.Error())
	}
	// No clients should be created for invalid protocol
	if factory.RedfishCallCount != 0 {
		t.Errorf("expected Redfish factory not called, got %d", factory.RedfishCallCount)
	}
	if factory.IPMICallCount != 0 {
		t.Errorf("expected IPMI factory not called, got %d", factory.IPMICallCount)
	}
}

func TestNewClient_ExplicitRedfishFails(t *testing.T) {
	factory := &MockClientFactory{
		RedfishConnectErr: errors.New("Redfish service unavailable"),
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolRedfish,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err == nil {
		t.Fatal("expected error when Redfish fails")
	}
	if client != nil {
		t.Error("expected nil client when Redfish fails")
	}
	// Should not fall back to IPMI when explicit protocol is specified
	if factory.IPMICallCount != 0 {
		t.Errorf("expected no IPMI fallback for explicit Redfish, got %d", factory.IPMICallCount)
	}
}

func TestNewClient_ExplicitIPMIFails(t *testing.T) {
	factory := &MockClientFactory{
		IPMIConnectErr: errors.New("ipmitool not found"),
	}

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolIPMI,
	}

	client, err := NewClientWithFactory(context.Background(), config, factory)
	if err == nil {
		t.Fatal("expected error when IPMI fails")
	}
	if client != nil {
		t.Error("expected nil client when IPMI fails")
	}
	// Should not try Redfish when explicit IPMI is specified
	if factory.RedfishCallCount != 0 {
		t.Errorf("expected no Redfish attempt for explicit IPMI, got %d", factory.RedfishCallCount)
	}
}

func TestDetectedProtocol_Redfish(t *testing.T) {
	client := redfish.NewClient(ports.BMCConfig{Address: "192.168.1.100"})
	protocol := DetectedProtocol(client)
	if protocol != ProtocolRedfish {
		t.Errorf("expected %q, got %q", ProtocolRedfish, protocol)
	}
}

func TestDetectedProtocol_IPMI(t *testing.T) {
	client := ipmi.NewClient(ports.BMCConfig{Address: "192.168.1.100"})
	protocol := DetectedProtocol(client)
	if protocol != ProtocolIPMI {
		t.Errorf("expected %q, got %q", ProtocolIPMI, protocol)
	}
}

func TestDetectedProtocol_Unknown(t *testing.T) {
	// MockBMCClient is not a known type
	client := &MockBMCClient{}
	protocol := DetectedProtocol(client)
	if protocol != protocolUnknown {
		t.Errorf("expected %q, got %q", protocolUnknown, protocol)
	}
}

func TestProtocolConstants(t *testing.T) {
	// Ensure constants have expected values
	if ProtocolAuto != "auto" {
		t.Errorf("expected ProtocolAuto = %q, got %q", "auto", ProtocolAuto)
	}
	if ProtocolRedfish != "redfish" {
		t.Errorf("expected ProtocolRedfish = %q, got %q", "redfish", ProtocolRedfish)
	}
	if ProtocolIPMI != "ipmi" {
		t.Errorf("expected ProtocolIPMI = %q, got %q", "ipmi", ProtocolIPMI)
	}
}

func TestDefaultClientFactory_NewRedfishClient(t *testing.T) {
	factory := &DefaultClientFactory{}
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := factory.NewRedfishClient(config)
	if client == nil {
		t.Fatal("expected non-nil client")
	}

	// Verify it's actually a Redfish client
	_, ok := client.(*redfish.Client)
	if !ok {
		t.Error("expected *redfish.Client type")
	}
}

func TestDefaultClientFactory_NewIPMIClient(t *testing.T) {
	factory := &DefaultClientFactory{}
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}

	client := factory.NewIPMIClient(config)
	if client == nil {
		t.Fatal("expected non-nil client")
	}

	// Verify it's actually an IPMI client
	_, ok := client.(*ipmi.Client)
	if !ok {
		t.Error("expected *ipmi.Client type")
	}
}

func TestNewClient_UsesDefaultFactory(t *testing.T) {
	// This test verifies that NewClient uses the default factory
	// We can't fully test this without network access, but we can verify
	// it returns an error for an invalid address (which means it tried to connect)
	config := ports.BMCConfig{
		Address:  "invalid-host-that-does-not-exist.local:9999",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolRedfish,
	}

	client, err := NewClient(context.Background(), config)
	// We expect an error because the host doesn't exist
	if err == nil {
		if client != nil {
			client.Close()
		}
		t.Fatal("expected error for invalid host")
	}
}

func TestNewClientWithFactory_ContextPropagation(t *testing.T) {
	var capturedCtx context.Context

	factory := &MockClientFactory{
		RedfishClient: &MockBMCClient{
			ConnectFunc: func(ctx context.Context) error {
				capturedCtx = ctx
				return nil
			},
		},
	}

	ctx := context.WithValue(context.Background(), "testKey", "testValue") //nolint:staticcheck // test context key

	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Protocol: ProtocolRedfish,
	}

	_, err := NewClientWithFactory(ctx, config, factory)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify context was passed through
	if capturedCtx == nil {
		t.Fatal("context was not propagated to Connect")
	}
	if capturedCtx.Value("testKey") != "testValue" {
		t.Error("context value was not preserved")
	}
}

// Verify MockBMCClient implements ports.BMCClient.
var _ ports.BMCClient = (*MockBMCClient)(nil)
