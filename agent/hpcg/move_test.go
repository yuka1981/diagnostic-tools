package hpcg

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWorkflowOrchestrator_MoveFile(t *testing.T) {
	tmpDir := t.TempDir()
	source := filepath.Join(tmpDir, "source.txt")
	dest := filepath.Join(tmpDir, "dest.txt")

	content := "test content"
	err := os.WriteFile(source, []byte(content), 0644)
	if err != nil {
		t.Fatalf("failed to create source file: %v", err)
	}

	w := &WorkflowOrchestrator{}
	err = w.moveFile(source, dest)
	if err != nil {
		t.Fatalf("moveFile failed: %v", err)
	}

	// Verify dest exists and content matches
	gotContent, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("failed to read dest file: %v", err)
	}
	if string(gotContent) != content {
		t.Errorf("expected content %q, got %q", content, string(gotContent))
	}

	// Verify source is gone
	if _, err := os.Stat(source); !os.IsNotExist(err) {
		t.Error("source file still exists")
	}
}
