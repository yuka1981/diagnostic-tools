package cmd

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewMLCInstallCmd(t *testing.T) {
	cmd := NewMLCInstallCmd()
	assert.Equal(t, "mlc-install", cmd.Use)
	assert.NotEmpty(t, cmd.Short)
}

func TestMLCInstallCmd_RequiredFlags(t *testing.T) {
	cmd := NewMLCInstallCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)

	// Execute without required flags should fail
	err := cmd.Execute()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "required flag")
}

func TestMLCInstallCmd_DryRun(t *testing.T) {
	cmd := NewMLCInstallCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)

	cmd.SetArgs([]string{
		"--tarball", "/tmp/test.tgz",
		"--binary-path", "Linux/mlc",
		"--dry-run",
	})

	err := cmd.Execute()
	assert.NoError(t, err)
	assert.Contains(t, buf.String(), "Dry Run")
}
