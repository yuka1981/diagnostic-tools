package infrastructure

import (
	"context"
	"testing"
)

func TestRealCommandRunner_Run(t *testing.T) {
	runner := NewRealCommandRunner()
	ctx := context.Background()

	t.Run("Success", func(t *testing.T) {
		output, err := runner.Run(ctx, "", "echo", "hello")
		if err != nil {
			t.Fatalf("Run failed: %v", err)
		}
		if string(output) != "hello\n" {
			t.Errorf("expected hello\\n, got %q", string(output))
		}
	})

	t.Run("WithError", func(t *testing.T) {
		_, err := runner.Run(ctx, "", "ls", "/non-existent-directory")
		if err == nil {
			t.Fatal("expected error, got nil")
		}
	})

	t.Run("WithDir", func(t *testing.T) {
		// Just verify it doesn't crash and respects the dir if we can
		_, err := runner.Run(ctx, "/", "ls")
		if err != nil {
			t.Fatalf("Run with dir failed: %v", err)
		}
	})
}
