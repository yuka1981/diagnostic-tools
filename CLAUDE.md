# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HPC System Detection & Benchmark Tool - A web application for monitoring HPC cluster nodes and managing benchmark runs. Consists of two main components:

1. **Web Application (Rails)**: Dashboard for node inventory, benchmark management, and visualization
2. **Agent (Go)**: CLI tool deployed on compute nodes for system info collection and benchmark execution

## Development Commands

### Rails Backend

```bash
# Start development server
bin/dev

# Run all tests
bin/rspec

# Run specific test
bin/rspec spec/models/node_spec.rb

# Lint
bin/rubocop -f github

# Auto-fix lint issues
bin/rubocop -a

# Security scan
bin/brakeman

# Database operations
bin/rails db:migrate
bin/rails db:rollback
```

### Go Agent (run from `agent/` directory)

```bash
cd agent

# Build
go build -o qis-agent .

# Run tests
go test ./...

# Lint
golangci-lint run
```

## Architecture

### Rails Application (Hotwire + Tailwind)

- **Framework**: Rails 7.2.3 with Hotwire (Turbo + Stimulus)
- **Database**: PostgreSQL 16+
- **Styling**: Tailwind CSS with NetBox-inspired design (slate sidebar, teal accents)
- **Testing**: RSpec with FactoryBot and Capybara

Key directories:
- `app/services/` - Business logic (SSH collection, inventory services)
- `app/jobs/` - Background jobs for async operations
- `app/components/` - ViewComponents
- `app/views/shared/` - Reusable partials including sidebar and modals

### Go Agent (Cobra CLI)

- **Framework**: Cobra for CLI
- **Module**: `github.com/yuka1981/diagnostic-tools/agent`

Key directories:
- `agent/cmd/` - CLI commands (collect, inventory push, hpcg)
- `agent/core/model/` - Data structures for inventory
- `agent/core/ports/` - Interface definitions
- `agent/inventory/collector/linux/` - System info collectors (CPU, memory, disk, network, DMI)
- `agent/hpcg/` - HPCG benchmark workflow

Agent commands:
- `qis-agent collect` - Output system info JSON to stdout
- `qis-agent inventory push --server URL --token TOKEN` - Push inventory to API
- `qis-agent hpcg` - Run HPCG benchmark workflow

### Data Flow

1. **Pull (Server-initiated)**: Rails SSH to Admin Node → Admin Node SSH to Compute Node → `qis-agent collect` → JSON returned → DB update
2. **Push (Agent-initiated)**: Agent runs `qis-agent inventory push` → POST to Rails API → DB update
3. **Benchmarks**: Slurm Job triggers Agent → Agent builds/runs benchmark → Results uploaded to API + artifacts to shared storage

### Node State Versioning

Each inventory collection creates a new `node_state` record (versioned history), not overwrites. The latest record represents current state.

## Quality Gates

Before committing, ensure:

**Rails**: `bin/rubocop -f github` (no offenses) AND `bin/rspec` (all green)

**Go**: `golangci-lint run` (no issues) AND `go test ./...` (all pass)

## Configuration

SSH settings via Rails credentials or environment variables:
- `SSH_USER`, `SSH_KEY_PATH`, `SSH_TIMEOUT`, `SSH_VERIFY_HOST_KEY`
- Jump host: `JUMP_HOST`, `JUMP_USER`, `JUMP_PORT`

Agent token via `AGENT_TOKEN` environment variable.
