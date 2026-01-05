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
