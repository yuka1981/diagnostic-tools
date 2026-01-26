# HPC Agent and BMC Collector Makefile

# Binary names
AGENT_BINARY := hpc-agent
BMC_COLLECTOR_BINARY := qis-bmc-collector

# Build directories
BUILD_DIR := build

# Go build flags
GO_BUILD_FLAGS := -ldflags="-s -w"

.PHONY: all build build-agent build-bmc-collector clean test lint deps

# Default target
all: build

# Build all binaries
build: build-agent build-bmc-collector

# Build main agent
build-agent:
	@mkdir -p $(BUILD_DIR)
	go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(AGENT_BINARY) .

# Build BMC collector
build-bmc-collector:
	@mkdir -p $(BUILD_DIR)
	go build $(GO_BUILD_FLAGS) -o $(BUILD_DIR)/$(BMC_COLLECTOR_BINARY) ./cmd/bmc-collector

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Run all tests
test:
	go test ./...

# Run linter
lint:
	golangci-lint run

# Install dependencies
deps:
	go mod download
	go mod tidy
