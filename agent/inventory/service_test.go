package inventory

import (
	"context"
	"errors"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

type mockSystemCollector struct {
	host *model.HostInfo
	cpu  *model.CPUInfo
	mem  *model.MemoryInfo
	dmi  *model.HostDMIInfo
	err  error
	disk []model.DiskInfo
	net  []model.NetInfo
}

func (m *mockSystemCollector) GetHostInfo(ctx context.Context) (*model.HostInfo, error) {
	return m.host, m.err
}
func (m *mockSystemCollector) GetCPUInfo(ctx context.Context) (*model.CPUInfo, error) {
	return m.cpu, m.err
}
func (m *mockSystemCollector) GetMemInfo(ctx context.Context) (*model.MemoryInfo, error) {
	return m.mem, m.err
}
func (m *mockSystemCollector) GetDiskInfo(ctx context.Context) ([]model.DiskInfo, error) {
	return m.disk, m.err
}
func (m *mockSystemCollector) GetNetInfo(ctx context.Context) ([]model.NetInfo, error) {
	return m.net, m.err
}
func (m *mockSystemCollector) GetDMIInfo(ctx context.Context) (*model.HostDMIInfo, error) {
	return m.dmi, m.err
}

func TestInventoryService_Collect(t *testing.T) {
	t.Run("Success", func(t *testing.T) {
		mock := &mockSystemCollector{
			host: &model.HostInfo{Hostname: "test-host"},
			cpu:  &model.CPUInfo{ModelName: "test-cpu"},
			mem:  &model.MemoryInfo{Total: 1024},
			disk: []model.DiskInfo{{Device: "/dev/sda"}},
			net:  []model.NetInfo{{Name: "eth0"}},
			dmi:  &model.HostDMIInfo{System: model.SystemInfo{ProductName: "test-product"}},
		}
		service := NewInventoryService(mock)
		state, err := service.Collect(context.Background())

		if err != nil {
			t.Fatalf("expected no error, got %v", err)
		}
		if state.Host.Hostname != "test-host" {
			t.Errorf("expected hostname test-host, got %s", state.Host.Hostname)
		}
		if state.CPU.ModelName != "test-cpu" {
			t.Errorf("expected cpu test-cpu, got %s", state.CPU.ModelName)
		}
		if state.DMI.System.ProductName != "test-product" {
			t.Errorf("expected dmi test-product, got %s", state.DMI.System.ProductName)
		}
	})

	t.Run("Error", func(t *testing.T) {
		expectedErr := errors.New("collection failed")
		mock := &mockSystemCollector{err: expectedErr}
		service := NewInventoryService(mock)
		_, err := service.Collect(context.Background())

		if err == nil {
			t.Fatal("expected error, got nil")
		}
		if !errors.Is(err, expectedErr) {
			t.Errorf("expected error %v, got %v", expectedErr, err)
		}
	})
}
