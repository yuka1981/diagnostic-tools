package cmd

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestCheckKeyCmd(t *testing.T) {
	t.Run("Valid", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer server.Close()

		buf := new(bytes.Buffer)
		rootCmd.SetOut(buf)
		rootCmd.SetArgs([]string{"check-key", "--server", server.URL, "--token", "test-token"})

		if err := rootCmd.Execute(); err != nil {
			t.Fatalf("Execute() failed: %v", err)
		}

		if !bytes.Contains(buf.Bytes(), []byte("API key is valid")) {
			t.Errorf("expected success message, got %q", buf.String())
		}
	})

	t.Run("Invalid", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
		}))
		defer server.Close()

		rootCmd.SetArgs([]string{"check-key", "--server", server.URL, "--token", "invalid-token"})

		if err := rootCmd.Execute(); err == nil {
			t.Error("expected error, got nil")
		}
	})

	t.Run("MissingToken", func(t *testing.T) {
		// Ensure AGENT_TOKEN is not set
		oldToken := os.Getenv("AGENT_TOKEN")
		os.Unsetenv("AGENT_TOKEN")
		defer os.Setenv("AGENT_TOKEN", oldToken)

		rootCmd.SetArgs([]string{"check-key", "--token", ""})
		if err := rootCmd.Execute(); err == nil {
			t.Error("expected error for missing token, got nil")
		}
	})

	t.Run("EnvToken", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
		}))
		defer server.Close()

		os.Setenv("AGENT_TOKEN", "env-token")
		defer os.Unsetenv("AGENT_TOKEN")

		buf := new(bytes.Buffer)
		rootCmd.SetOut(buf)
		rootCmd.SetArgs([]string{"check-key", "--server", server.URL, "--token", ""})

		if err := rootCmd.Execute(); err != nil {
			t.Fatalf("Execute() failed: %v", err)
		}
	})
}
