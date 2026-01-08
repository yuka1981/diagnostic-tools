package linux

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

// MockCommandRunner is already defined in disk_test.go in the same package

func TestLinuxHostCollector_Collect(t *testing.T) {
	// Setup temporary os-release file
	tmpDir := t.TempDir()
	osReleasePath := filepath.Join(tmpDir, "os-release")
	content := `PRETTY_NAME="Ubuntu 22.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04.4 LTS (Jammy Jellyfish)"
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=jammy
`
	if err := os.WriteFile(osReleasePath, []byte(content), 0644); err != nil {
		t.Fatalf("failed to write os-release: %v", err)
	}

	runner := &MockCommandRunner{
		Output: "5.15.0-101-generic\n",
	}

	collector := NewLinuxHostCollector(runner)
	collector.OSReleasePath = osReleasePath

	info, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect failed: %v", err)
	}

	if info.Kernel != "5.15.0-101-generic" {
		t.Errorf("expected kernel 5.15.0-101-generic, got %s", info.Kernel)
	}
	if info.Platform != "ubuntu" {
		t.Errorf("expected platform ubuntu, got %s", info.Platform)
	}
	if info.PlatformVersion != "22.04" {
		t.Errorf("expected version 22.04, got %s", info.PlatformVersion)
	}
	if info.PlatformFamily != "debian" {
		t.Errorf("expected family debian, got %s", info.PlatformFamily)
	}
	if info.Hostname == "" {
		t.Error("expected non-empty hostname")
	}
	if info.OS == "" {
		t.Error("expected non-empty OS")
	}
	if info.Arch == "" {
		t.Error("expected non-empty Arch")
	}
}

func TestLinuxHostCollector_Collect_Fallback(t *testing.T) {
	// Test without os-release
	tmpDir := t.TempDir()
	osReleasePath := filepath.Join(tmpDir, "os-release") // Does not exist

	runner := &MockCommandRunner{
		Output: "5.15.0-101-generic\n",
	}

	collector := NewLinuxHostCollector(runner)
	collector.OSReleasePath = osReleasePath

	info, err := collector.Collect(context.Background())
	if err != nil {
		t.Fatalf("Collect failed: %v", err)
	}

	if info.Platform != "linux" { // Default fallback
		t.Errorf("expected platform linux, got %s", info.Platform)
	}
}

func TestLinuxHostCollector_Collect_Error(t *testing.T) {
	runner := &MockCommandRunner{
		Err: context.DeadlineExceeded,
	}
	collector := NewLinuxHostCollector(runner)

	_, err := collector.Collect(context.Background())
	if err == nil {
		t.Error("expected error from Collect when runner fails, got nil")
	}
}

func TestLinuxHostCollector_getOSRelease_Fallback(t *testing.T) {
	// We can't easily mock /etc/debian_version without a fake filesystem.
	// But we can test the function with a file that doesn't have ID_LIKE.
	tmpDir := t.TempDir()
	osReleasePath := filepath.Join(tmpDir, "os-release")
	content := `ID=test-os
VERSION_ID=1.0
`
	_ = os.WriteFile(osReleasePath, []byte(content), 0644)

	runner := &MockCommandRunner{Output: "kernel\n"}
	collector := NewLinuxHostCollector(runner)
	collector.OSReleasePath = osReleasePath

	platform, version, family := collector.getOSRelease()
	if platform != "test-os" {
		t.Errorf("expected test-os, got %s", platform)
	}
	if version != "1.0" {
		t.Errorf("expected 1.0, got %s", version)
	}
	// family might be empty or detected from host depending on environment
	_ = family
}

func TestLinuxHostCollector_getOSRelease_NoFile(t *testing.T) {
	collector := &LinuxHostCollector{OSReleasePath: "/non-existent"}
	platform, version, family := collector.getOSRelease()
	if platform != defaultPlatform {
		t.Errorf("expected %s, got %s", defaultPlatform, platform)
	}
	if version != "" || family != "" {
		t.Errorf("expected empty version and family, got %s, %s", version, family)
	}
}
