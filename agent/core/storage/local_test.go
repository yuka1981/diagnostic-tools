package storage

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLocalArtifactManager_AtomicWrite(t *testing.T) {
	baseDir := t.TempDir()
	manager := NewLocalArtifactManager(baseDir)
	runID := "run-123"

	// 1. Prepare
	tmpDir, err := manager.Prepare(runID)
	if err != nil {
		t.Fatalf("Prepare failed: %v", err)
	}

	expectedTmp := filepath.Join(baseDir, "run-123.tmp")
	if tmpDir != expectedTmp {
		t.Errorf("expected tmp dir %s, got %s", expectedTmp, tmpDir)
	}

	// Verify tmp dir exists
	if _, err := os.Stat(tmpDir); os.IsNotExist(err) {
		t.Fatal("tmp dir does not exist")
	}

	// Create a file in tmp dir
	testFile := filepath.Join(tmpDir, "test.txt")
	if err := os.WriteFile(testFile, []byte("data"), 0600); err != nil {
		t.Fatalf("failed to write test file: %v", err)
	}

	// 2. Commit
	if err := manager.Commit(runID); err != nil {
		t.Fatalf("Commit failed: %v", err)
	}

	// Verify tmp dir gone
	if _, err := os.Stat(tmpDir); !os.IsNotExist(err) {
		t.Error("tmp dir should usually be gone (renamed)")
	}

	// Verify final dir exists
	finalDir := filepath.Join(baseDir, "run-123")
	if _, err := os.Stat(finalDir); os.IsNotExist(err) {
		t.Fatal("final dir does not exist")
	}

	// Verify file exists in final dir
	finalFile := filepath.Join(finalDir, "test.txt")
	if _, err := os.Stat(finalFile); os.IsNotExist(err) {
		t.Error("test file missing in final dir")
	}
}
