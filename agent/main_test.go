package main

import (
	"os"
	"testing"
)

func TestMainFunc(t *testing.T) {
	t.Log("Testing main function")
	// Execute main with --help to avoid long running or destructive actions
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"hpc-agent", "--help"}
	main()
}
