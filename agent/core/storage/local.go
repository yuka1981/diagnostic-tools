package storage

import (
	"fmt"
	"os"
	"path/filepath"
)

// LocalArtifactManager manages artifact storage on the local filesystem.
type LocalArtifactManager struct {
	BaseDir string
}

// NewLocalArtifactManager creates a new manager.
func NewLocalArtifactManager(baseDir string) *LocalArtifactManager {
	return &LocalArtifactManager{BaseDir: baseDir}
}

// Prepare creates a temporary directory for the given run ID.
// It returns the path to the temporary directory.
func (m *LocalArtifactManager) Prepare(runID string) (string, error) {
	tmpDir := m.tmpDirPath(runID)
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create tmp dir: %w", err)
	}
	return tmpDir, nil
}

// Commit atomically renames the temporary directory to the final directory.
func (m *LocalArtifactManager) Commit(runID string) error {
	tmpDir := m.tmpDirPath(runID)
	finalDir := m.finalDirPath(runID)

	if err := os.Rename(tmpDir, finalDir); err != nil {
		return fmt.Errorf("failed to rename artifact dir: %w", err)
	}
	return nil
}

func (m *LocalArtifactManager) tmpDirPath(runID string) string {
	return filepath.Join(m.BaseDir, runID+".tmp")
}

func (m *LocalArtifactManager) finalDirPath(runID string) string {
	return filepath.Join(m.BaseDir, runID)
}
