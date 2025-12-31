package linux

import (
	"context"
	"testing"
)

// MockCommandRunner mocks the CommandRunner interface.
type MockCommandRunner struct {
	Err    error
	Output string
}

func (m *MockCommandRunner) Run(ctx context.Context, name string, args ...string) ([]byte, error) {
	return []byte(m.Output), m.Err
}

func TestParseDiskInfo(t *testing.T) {
	output := `Filesystem     1B-blocks      Used Available Use% Mounted on
/dev/sda2      263174213 100000000 163174213  38% /
tmpfs          817385472         0 817385472   0% /dev/shm
/dev/sdb1      524288000 200000000 324288000  38% /mnt/data
`
	disks, err := ParseDiskInfo(output)
	if err != nil {
		t.Fatalf("ParseDiskInfo returned error: %v", err)
	}

	if len(disks) != 2 {
		t.Errorf("expected 2 disks (ignoring tmpfs), got %d", len(disks))
	}

	// Check /dev/sda2
	foundRoot := false
	for _, d := range disks {
		if d.Mountpoint != "/" {
			continue
		}
		foundRoot = true
		if d.Device != "/dev/sda2" {
			t.Errorf("expected device /dev/sda2 for root, got %s", d.Device)
		}
		if d.Total != 263174213 {
			t.Errorf("expected total 263174213, got %d", d.Total)
		}
		if d.Used != 100000000 {
			t.Errorf("expected used 100000000, got %d", d.Used)
		}
		if d.Free != 163174213 {
			t.Errorf("expected free 163174213, got %d", d.Free)
		}
	}
	if !foundRoot {
		t.Error("expected to find root mountpoint")
	}
}

func TestLinuxDiskCollector_Collect(t *testing.T) {
	mockRunner := &MockCommandRunner{
		Output: `Filesystem     1B-blocks      Used Available Use% Mounted on
/dev/sda1      1000 500 500 50% /
`,
	}

	collector := NewLinuxDiskCollector(mockRunner)
	disks, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect returned error: %v", err)
	}

	if len(disks) != 1 {
		t.Errorf("expected 1 disk, got %d", len(disks))
	}
	if disks[0].Mountpoint != "/" {
		t.Errorf("expected mountpoint /, got %s", disks[0].Mountpoint)
	}
}
