package identity

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGetOrGenerateNodeID(t *testing.T) {
	tempDir := t.TempDir()

	// 1. Initial generation
	id1, err := GetOrGenerateNodeID(tempDir)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if id1 == "" {
		t.Fatal("Expected non-empty ID")
	}

	// 2. Persistence check
	id2, err := GetOrGenerateNodeID(tempDir)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if id1 != id2 {
		t.Errorf("Expected ID to be persisted, got %s then %s", id1, id2)
	}

	// 3. Regeneration check (same fingerprint)
	err = os.Remove(filepath.Join(tempDir, DefaultIDPath))
	if err != nil {
		t.Fatalf("Failed to remove ID file: %v", err)
	}

	id3, err := GetOrGenerateNodeID(tempDir)
	if err != nil {
		t.Fatalf("Expected no error, got %v", err)
	}
	if id1 != id3 {
		t.Errorf("Expected ID from fingerprint to be stable, got %s then %s", id1, id3)
	}
}

func TestGetOrGenerateNodeID_Error(t *testing.T) {
	// Try a path that is a file, so MkdirAll fails
	tmpDir := t.TempDir()
	filePath := filepath.Join(tmpDir, "file")
	_ = os.WriteFile(filePath, []byte("not-a-dir"), 0644)

	_, err := GetOrGenerateNodeID(filePath)
	if err == nil {
		t.Error("expected error when configDir is a file, got nil")
	}
}

func TestGenerateFingerprint(t *testing.T) {
	fp := GenerateFingerprint()
	if len(fp) != 64 { // SHA-256 hex string length
		t.Errorf("Expected 64 char hex string, got %d", len(fp))
	}
}
