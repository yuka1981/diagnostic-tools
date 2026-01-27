package mlc

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckHugepages_Sufficient(t *testing.T) {
	// Create temp file with sufficient hugepages (4000)
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "nr_hugepages")
	if err := os.WriteFile(tmpFile, []byte("4000\n"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}

	// Override path for testing
	oldPath := hugepagesPath
	hugepagesPath = tmpFile
	defer func() { hugepagesPath = oldPath }()

	err := CheckHugepages(MinHugepages)
	if err != nil {
		t.Errorf("expected nil error for sufficient hugepages (4000), got: %v", err)
	}
}

func TestCheckHugepages_Insufficient(t *testing.T) {
	// Create temp file with insufficient hugepages (500)
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "nr_hugepages")
	if err := os.WriteFile(tmpFile, []byte("500\n"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}

	// Override path for testing
	oldPath := hugepagesPath
	hugepagesPath = tmpFile
	defer func() { hugepagesPath = oldPath }()

	err := CheckHugepages(MinHugepages)
	if err == nil {
		t.Fatal("expected error for insufficient hugepages (500), got nil")
	}

	// Verify error message contains guidance
	errMsg := err.Error()
	if !strings.Contains(errMsg, "found: 500") {
		t.Errorf("expected error to contain 'found: 500', got: %s", errMsg)
	}
	if !strings.Contains(errMsg, "required: 1000") {
		t.Errorf("expected error to contain 'required: 1000', got: %s", errMsg)
	}
	if !strings.Contains(errMsg, "echo 4000") {
		t.Errorf("expected error to contain fix guidance 'echo 4000', got: %s", errMsg)
	}
}

func TestCheckHugepages_Zero(t *testing.T) {
	// Create temp file with zero hugepages
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "nr_hugepages")
	if err := os.WriteFile(tmpFile, []byte("0\n"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}

	// Override path for testing
	oldPath := hugepagesPath
	hugepagesPath = tmpFile
	defer func() { hugepagesPath = oldPath }()

	err := CheckHugepages(MinHugepages)
	if err == nil {
		t.Fatal("expected error for zero hugepages, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "found: 0") {
		t.Errorf("expected error to contain 'found: 0', got: %s", errMsg)
	}
}

func TestCheckHugepages_MissingFile(t *testing.T) {
	// Point to non-existent file (simulates non-Linux or missing procfs)
	oldPath := hugepagesPath
	hugepagesPath = "/nonexistent/path/nr_hugepages"
	defer func() { hugepagesPath = oldPath }()

	err := CheckHugepages(MinHugepages)
	if err != nil {
		t.Errorf("expected nil error for missing file (graceful skip), got: %v", err)
	}
}

func TestCheckHugepages_MalformedContent(t *testing.T) {
	// Create temp file with malformed content
	tmpDir := t.TempDir()
	tmpFile := filepath.Join(tmpDir, "nr_hugepages")
	if err := os.WriteFile(tmpFile, []byte("not-a-number\n"), 0644); err != nil {
		t.Fatalf("failed to create temp file: %v", err)
	}

	// Override path for testing
	oldPath := hugepagesPath
	hugepagesPath = tmpFile
	defer func() { hugepagesPath = oldPath }()

	err := CheckHugepages(MinHugepages)
	if err == nil {
		t.Fatal("expected error for malformed content, got nil")
	}

	errMsg := err.Error()
	if !strings.Contains(errMsg, "parse") {
		t.Errorf("expected error to mention parse failure, got: %s", errMsg)
	}
}
