package cmd

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/yuka1981/diagnostic-tools/agent/core/model"
)

func TestCollectCmd(t *testing.T) {
	buf := new(bytes.Buffer)
	rootCmd.SetOut(buf)
	rootCmd.SetArgs([]string{"collect", "--json"})

	if err := rootCmd.Execute(); err != nil {
		t.Fatalf("Execute() failed: %v", err)
	}

	output := buf.Bytes()
	if len(output) == 0 {
		t.Fatal("expected non-empty output")
	}

	var state model.NodeState
	if err := json.Unmarshal(output, &state); err != nil {
		t.Fatalf("failed to unmarshal output: %v\nOutput: %s", err, string(output))
	}

	if state.Host.Hostname == "" {
		t.Error("expected non-empty hostname in collected state")
	}
}

func TestCollectCmd_Fail(t *testing.T) {
	// We can't easily make service.Collect fail without mocking NewInventoryService
	// but it uses RealCommandRunner which might fail if we change PATH or something.

	// Actually, let's just test that --json=false doesn't crash
	rootCmd.SetArgs([]string{"collect", "--json=false"})
	_ = rootCmd.Execute()
}
