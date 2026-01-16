package main

import "github.com/yuka1981/diagnostic-tools/agent/cmd"

// Version is set at build time via ldflags
// e.g., go build -ldflags "-X main.Version=v1.0.0"
var Version = "dev"

func main() {
	cmd.SetVersion(Version)
	cmd.Execute()
}
