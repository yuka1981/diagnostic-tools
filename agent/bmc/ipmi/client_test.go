//nolint:govet // fieldalignment: test structs don't need optimal alignment
package ipmi

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/ports"
)

// Test constants for IPMI commands and values.
const (
	testCmdMC        = "mc"
	testCmdSensor    = "sensor"
	testCmdChassis   = "chassis"
	testCmdFRU       = "fru"
	testCmdLAN       = "lan"
	testSubcmdInfo   = "info"
	testSubcmdList   = "list"
	testSubcmdPrint  = "print"
	testSubcmdStatus = "status"
	testFirmware     = "2.60"
	testFRUOutput    = "Board Mfg : Supermicro\n"
)

// MockCommandExecutor implements CommandExecutor for testing.
type MockCommandExecutor struct {
	LookPathFunc   func(file string) (string, error)
	CommandFunc    func(ctx context.Context, name string, args ...string) (string, error)
	CommandHistory [][]string // Records all commands executed
}

func (m *MockCommandExecutor) LookPath(file string) (string, error) {
	if m.LookPathFunc != nil {
		return m.LookPathFunc(file)
	}
	return "/usr/bin/" + file, nil
}

func (m *MockCommandExecutor) CommandContext(ctx context.Context, name string, args ...string) (string, error) {
	m.CommandHistory = append(m.CommandHistory, append([]string{name}, args...))
	if m.CommandFunc != nil {
		return m.CommandFunc(ctx, name, args...)
	}
	return "", nil
}

func TestNewClient(t *testing.T) {
	config := ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
		Port:     623,
	}

	client := NewClient(&config)

	if client.config.Address != config.Address {
		t.Errorf("expected Address %q, got %q", config.Address, client.config.Address)
	}
	if client.config.Username != config.Username {
		t.Errorf("expected Username %q, got %q", config.Username, client.config.Username)
	}
	if client.ipmitool != "ipmitool" {
		t.Errorf("expected ipmitool path %q, got %q", "ipmitool", client.ipmitool)
	}
}

func TestClient_Connect(t *testing.T) {
	tests := []struct {
		name        string
		lookPathErr error
		commandErr  error
		commandOut  string
		expectErr   bool
		errContains string
	}{
		{
			name:       "successful connection",
			commandOut: "Device ID : 32\nFirmware Revision : 2.60\n",
			expectErr:  false,
		},
		{
			name:        "ipmitool not found",
			lookPathErr: errors.New("executable file not found in $PATH"),
			expectErr:   true,
			errContains: "ipmitool not found",
		},
		{
			name:        "connection failed",
			commandErr:  errors.New("Unable to establish IPMI v2 / RMCP+ session"),
			expectErr:   true,
			errContains: "failed to connect to BMC",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mock := &MockCommandExecutor{
				LookPathFunc: func(file string) (string, error) {
					if tt.lookPathErr != nil {
						return "", tt.lookPathErr
					}
					return "/usr/bin/ipmitool", nil
				},
				CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
					if tt.commandErr != nil {
						return "", tt.commandErr
					}
					return tt.commandOut, nil
				},
			}

			client := NewClientWithExecutor(&ports.BMCConfig{
				Address:  "192.168.1.100",
				Username: "admin",
				Password: "password",
			}, mock)

			err := client.Connect(context.Background())

			if tt.expectErr {
				if err == nil {
					t.Error("expected error, got nil")
				} else if !strings.Contains(err.Error(), tt.errContains) {
					t.Errorf("expected error containing %q, got %q", tt.errContains, err.Error())
				}
			} else {
				if err != nil {
					t.Errorf("unexpected error: %v", err)
				}
			}
		})
	}
}

func TestClient_Close(t *testing.T) {
	client := NewClient(&ports.BMCConfig{})
	err := client.Close()
	if err != nil {
		t.Errorf("Close() should always return nil, got %v", err)
	}
}

func TestClient_SetIPMIToolPath(t *testing.T) {
	client := NewClient(&ports.BMCConfig{})
	customPath := "/custom/path/ipmitool"
	client.SetIPMIToolPath(customPath)

	if client.ipmitool != customPath {
		t.Errorf("expected ipmitool path %q, got %q", customPath, client.ipmitool)
	}
}

func TestClient_buildBaseArgs(t *testing.T) {
	tests := []struct {
		name     string
		config   ports.BMCConfig
		expected []string
	}{
		{
			name: "without port",
			config: ports.BMCConfig{
				Address:  "192.168.1.100",
				Username: "admin",
				Password: "secret",
			},
			expected: []string{"-I", "lanplus", "-H", "192.168.1.100", "-U", "admin", "-P", "secret"},
		},
		{
			name: "with port",
			config: ports.BMCConfig{
				Address:  "192.168.1.100",
				Username: "admin",
				Password: "secret",
				Port:     623,
			},
			expected: []string{"-I", "lanplus", "-H", "192.168.1.100", "-U", "admin", "-P", "secret", "-p", "623"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client := NewClient(&tt.config)
			args := client.buildBaseArgs()

			if len(args) != len(tt.expected) {
				t.Fatalf("expected %d args, got %d", len(tt.expected), len(args))
			}

			for i, exp := range tt.expected {
				if args[i] != exp {
					t.Errorf("arg %d: expected %q, got %q", i, exp, args[i])
				}
			}
		})
	}
}

func TestClient_GetBMCInfo(t *testing.T) {
	mcInfoOutput := `Device ID                 : 32
Device Revision           : 1
Firmware Revision         : 2.60
IPMI Version              : 2.0
Manufacturer ID           : 10876
Manufacturer Name         : Supermicro
Product ID                : 2379 (0x094b)
Product Name              : Super Server`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			// Check that we're calling mc info
			for i, arg := range args {
				if arg == testCmdMC && i < len(args)-1 && args[i+1] == testSubcmdInfo {
					return mcInfoOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	info, err := client.GetBMCInfo(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if info.Firmware != testFirmware {
		t.Errorf("expected Firmware %q, got %q", "2.60", info.Firmware)
	}
	if info.Model != "Supermicro Super Server" {
		t.Errorf("expected Model %q, got %q", "Supermicro Super Server", info.Model)
	}
	if info.IP != "192.168.1.100" {
		t.Errorf("expected IP %q, got %q", "192.168.1.100", info.IP)
	}
}

func TestClient_GetSensors(t *testing.T) {
	sensorOutput := `CPU0 Temp        | 45.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
CPU1 Temp        | 47.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
Fan1             | 3500.000   | RPM        | ok    | na        | 500.000   | 1000.000  | na        | na        | na`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdSensor && i < len(args)-1 && args[i+1] == testSubcmdList {
					return sensorOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	sensors, err := client.GetSensors(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(sensors) != 3 {
		t.Fatalf("expected 3 sensors, got %d", len(sensors))
	}

	if sensors[0].Name != "CPU0 Temp" {
		t.Errorf("expected sensor name %q, got %q", "CPU0 Temp", sensors[0].Name)
	}
	if sensors[0].Value != 45.0 {
		t.Errorf("expected sensor value %f, got %f", 45.0, sensors[0].Value)
	}
	if sensors[0].Unit != "Celsius" {
		t.Errorf("expected sensor unit %q, got %q", "Celsius", sensors[0].Unit)
	}
}

func TestClient_GetSensors_FallbackToSDR(t *testing.T) {
	sdrOutput := `CPU0 Temp        | 45 degrees C      | ok
Fan1             | 3500 RPM          | ok`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdSensor && i < len(args)-1 && args[i+1] == testSubcmdList {
					return "", errors.New("sensor list failed")
				}
				if arg == "sdr" {
					return sdrOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	sensors, err := client.GetSensors(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(sensors) != 2 {
		t.Fatalf("expected 2 sensors, got %d", len(sensors))
	}
}

func TestClient_GetHealth(t *testing.T) {
	sensorOutput := `CPU0 Temp        | 45.000     | degrees C  | ok    | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
Fan1             | 3500.000   | RPM        | ok    | na        | 500.000   | 1000.000  | na        | na        | na
PSU Power        | 450.000    | Watts      | ok    | na        | na        | na        | 600.000   | 650.000   | na`

	chassisOutput := `System Power         : on
Power Overload       : false
Main Power Fault     : false
Cooling/Fan Fault    : false
Drive Fault          : false
Chassis Intrusion    : inactive`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdSensor && i < len(args)-1 && args[i+1] == testSubcmdList {
					return sensorOutput, nil
				}
				if arg == testCmdChassis && i < len(args)-1 && args[i+1] == testSubcmdStatus {
					return chassisOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	health, err := client.GetHealth(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if health.Overall != statusOK {
		t.Errorf("expected Overall %q, got %q", "OK", health.Overall)
	}

	if health.Components["CPU"] != "OK" {
		t.Errorf("expected CPU status %q, got %q", "OK", health.Components["CPU"])
	}
}

func TestClient_GetHealth_WithWarning(t *testing.T) {
	sensorOutput := `CPU0 Temp        | 92.000     | degrees C  | unc   | na        | 0.000     | 5.000     | 90.000    | 95.000    | na
Fan1             | 3500.000   | RPM        | ok    | na        | 500.000   | 1000.000  | na        | na        | na`

	chassisOutput := `System Power         : on
Main Power Fault     : false
Cooling/Fan Fault    : false`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdSensor && i < len(args)-1 && args[i+1] == testSubcmdList {
					return sensorOutput, nil
				}
				if arg == testCmdChassis && i < len(args)-1 && args[i+1] == testSubcmdStatus {
					return chassisOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	health, err := client.GetHealth(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if health.Overall != "Warning" {
		t.Errorf("expected Overall %q, got %q", "Warning", health.Overall)
	}
}

func TestClient_GetNetwork(t *testing.T) {
	lanOutput := `Set in Progress         : Set Complete
IP Address Source       : Static Address
IP Address              : 192.168.1.100
Subnet Mask             : 255.255.255.0
MAC Address             : 3c:ec:ef:12:34:56
Default Gateway IP      : 192.168.1.1`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdLAN && i < len(args)-1 && args[i+1] == testSubcmdPrint {
					return lanOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	adapters, err := client.GetNetwork(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(adapters) != 1 {
		t.Fatalf("expected 1 adapter, got %d", len(adapters))
	}

	if adapters[0].MAC != "3c:ec:ef:12:34:56" {
		t.Errorf("expected MAC %q, got %q", "3c:ec:ef:12:34:56", adapters[0].MAC)
	}
	if adapters[0].Name != "BMC LAN" {
		t.Errorf("expected Name %q, got %q", "BMC LAN", adapters[0].Name)
	}
}

func TestClient_GetBIOS(t *testing.T) {
	fruOutput := `FRU Device Description : Builtin FRU Device (ID 0)
 Board Mfg             : Supermicro
 Board Product         : X11SPL-F
 Product Manufacturer  : Supermicro
 Product Name          : Super Server`

	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdFRU && i < len(args)-1 && args[i+1] == testSubcmdPrint {
					return fruOutput, nil
				}
			}
			return "", errors.New("unexpected command")
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	bios, err := client.GetBIOS(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Since FRU doesn't have explicit BIOS fields, it falls back to manufacturer
	if bios.Vendor != "Supermicro" {
		t.Errorf("expected Vendor %q, got %q", "Supermicro", bios.Vendor)
	}
}

func TestClient_GetInventory(t *testing.T) {
	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			for i, arg := range args {
				if arg == testCmdFRU && i < len(args)-1 && args[i+1] == testSubcmdPrint {
					return testFRUOutput, nil
				}
				if arg == testCmdMC && i < len(args)-1 && args[i+1] == testSubcmdInfo {
					return "Firmware Revision : 2.60\nManufacturer Name : Supermicro\n", nil
				}
				if arg == testCmdLAN && i < len(args)-1 && args[i+1] == testSubcmdPrint {
					return "MAC Address : 3c:ec:ef:12:34:56\n", nil
				}
			}
			return "", nil
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	inventory, err := client.GetInventory(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if inventory.BMCInfo.Firmware != "2.60" {
		t.Errorf("expected BMCInfo.Firmware %q, got %q", "2.60", inventory.BMCInfo.Firmware)
	}

	if len(inventory.Network) != 1 {
		t.Errorf("expected 1 network adapter, got %d", len(inventory.Network))
	}
}

func TestClient_GetProcessors(t *testing.T) {
	// IPMI typically doesn't return processor info, so this should return empty
	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			return testFRUOutput, nil
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	processors, err := client.GetProcessors(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// IPMI typically doesn't have detailed CPU info, expect empty slice
	if len(processors) != 0 {
		t.Errorf("expected 0 processors, got %d", len(processors))
	}
}

func TestClient_GetStorage(t *testing.T) {
	mock := &MockCommandExecutor{}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	storage, err := client.GetStorage(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// IPMI doesn't provide storage info
	if len(storage) != 0 {
		t.Errorf("expected 0 storage devices, got %d", len(storage))
	}
}

func TestClient_GetInfiniband(t *testing.T) {
	mock := &MockCommandExecutor{}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	ib, err := client.GetInfiniband(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// IPMI doesn't provide InfiniBand info
	if len(ib) != 0 {
		t.Errorf("expected 0 InfiniBand adapters, got %d", len(ib))
	}
}

func TestClient_GetMemory(t *testing.T) {
	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			return testFRUOutput, nil
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "192.168.1.100",
		Username: "admin",
		Password: "password",
	}, mock)

	memory, err := client.GetMemory(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// IPMI typically has limited memory info, expect empty slice
	if len(memory) != 0 {
		t.Errorf("expected 0 memory modules, got %d", len(memory))
	}
}

func TestClient_InterfaceCompliance(t *testing.T) {
	// Verify that Client implements BMCClient interface
	var _ ports.BMCClient = (*Client)(nil)
}

func TestClient_CommandArgsPassedCorrectly(t *testing.T) {
	mock := &MockCommandExecutor{
		CommandFunc: func(ctx context.Context, name string, args ...string) (string, error) {
			return "", nil
		},
	}

	client := NewClientWithExecutor(&ports.BMCConfig{
		Address:  "10.0.0.1",
		Username: "testuser",
		Password: "testpass",
		Port:     9623,
	}, mock)

	_ = client.Connect(context.Background())

	if len(mock.CommandHistory) < 1 {
		t.Fatal("expected at least one command to be executed")
	}

	// Check the last command (mc info from Connect)
	cmd := mock.CommandHistory[len(mock.CommandHistory)-1]

	// Verify command structure: ipmitool -I lanplus -H <addr> -U <user> -P <pass> -p <port> mc info
	expectedArgs := []string{"ipmitool", "-I", "lanplus", "-H", "10.0.0.1", "-U", "testuser", "-P", "testpass", "-p", "9623", "mc", "info"}

	if len(cmd) != len(expectedArgs) {
		t.Fatalf("expected %d args, got %d: %v", len(expectedArgs), len(cmd), cmd)
	}

	for i, exp := range expectedArgs {
		if cmd[i] != exp {
			t.Errorf("arg %d: expected %q, got %q", i, exp, cmd[i])
		}
	}
}
