package cmd

import (
	"bytes"
	"testing"
)

func TestExecute(t *testing.T) {
	// Execute just calls rootCmd.Execute()
	// We can't easily test the os.Exit(1) case.
	// But we can test a successful help command.
	buf := new(bytes.Buffer)
	rootCmd.SetOut(buf)
	rootCmd.SetArgs([]string{"--help"})
	Execute()
	if !bytes.Contains(buf.Bytes(), []byte("HPC System Detection")) {
		t.Error("expected help output")
	}
}
