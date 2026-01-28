package mlc

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInstallWorkflow_ValidateTarball(t *testing.T) {
	w := &InstallWorkflow{}

	t.Run("missing tarball returns error", func(t *testing.T) {
		err := w.validateTarball("/nonexistent/path.tgz")
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "not found")
	})

	t.Run("existing tarball passes", func(t *testing.T) {
		tmpfile, err := os.CreateTemp("", "test*.tgz")
		require.NoError(t, err)
		defer os.Remove(tmpfile.Name())
		tmpfile.Close()

		err = w.validateTarball(tmpfile.Name())
		assert.NoError(t, err)
	})

	t.Run("directory fails validation", func(t *testing.T) {
		tmpDir, err := os.MkdirTemp("", "test-dir")
		require.NoError(t, err)
		defer os.RemoveAll(tmpDir)

		err = w.validateTarball(tmpDir)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "directory")
	})
}

func TestInstallWorkflow_ParseVersion(t *testing.T) {
	w := &InstallWorkflow{}

	t.Run("parses version from output", func(t *testing.T) {
		output := "Intel(R) Memory Latency Checker - v3.11"
		version := w.parseVersion(output)
		assert.Equal(t, "3.11", version)
	})

	t.Run("handles version with patch", func(t *testing.T) {
		output := "Intel(R) Memory Latency Checker - v3.11.2"
		version := w.parseVersion(output)
		assert.Equal(t, "3.11.2", version)
	})

	t.Run("returns empty for no match", func(t *testing.T) {
		output := "no version here"
		version := w.parseVersion(output)
		assert.Empty(t, version)
	})

	t.Run("handles version without v prefix", func(t *testing.T) {
		output := "MLC version 3.11"
		version := w.parseVersion(output)
		assert.Equal(t, "3.11", version)
	})
}

func TestInstallWorkflow_GenerateModulefile(t *testing.T) {
	w := &InstallWorkflow{}

	content := w.generateModulefile("3.11", "/opt/qct/utils/qis/software/mlc-3.11")

	assert.Contains(t, content, "help([[Intel Memory Latency Checker")
	assert.Contains(t, content, "v3.11")
	assert.Contains(t, content, `prepend_path("PATH"`)
	assert.Contains(t, content, "mlc-3.11")
}

func TestInstallWorkflow_InstallBinary(t *testing.T) {
	// Create source file
	tmpDir, err := os.MkdirTemp("", "mlc-install-test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	srcBinary := filepath.Join(tmpDir, "src", "mlc")
	require.NoError(t, os.MkdirAll(filepath.Dir(srcBinary), 0755))
	require.NoError(t, os.WriteFile(srcBinary, []byte("binary content"), 0755))

	installDir := filepath.Join(tmpDir, "install", "mlc-3.11")

	w := &InstallWorkflow{}
	err = w.installBinary(srcBinary, installDir)

	assert.NoError(t, err)
	assert.FileExists(t, filepath.Join(installDir, "mlc"))

	// Verify content
	content, err := os.ReadFile(filepath.Join(installDir, "mlc"))
	require.NoError(t, err)
	assert.Equal(t, "binary content", string(content))
}

func TestInstallWorkflow_WriteModulefile(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "mlc-module-test")
	require.NoError(t, err)
	defer os.RemoveAll(tmpDir)

	modulePath := filepath.Join(tmpDir, "modulefiles", "mlc", "3.11")

	w := &InstallWorkflow{}
	err = w.writeModulefile("3.11", "/opt/software/mlc-3.11", modulePath)

	assert.NoError(t, err)
	assert.FileExists(t, modulePath)

	content, err := os.ReadFile(modulePath)
	require.NoError(t, err)
	assert.Contains(t, string(content), "3.11")
}

func TestNewInstallWorkflow(t *testing.T) {
	w := NewInstallWorkflow(nil)
	assert.NotNil(t, w)
}
