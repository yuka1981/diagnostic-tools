# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HPC System Detection & Benchmark Tool - A hybrid system for monitoring HPC cluster nodes and managing HPCG benchmark runs.

- **Web Application**: Ruby on Rails 7.2.3 monolith with Hotwire (Turbo + Stimulus) and Tailwind CSS
- **Agent**: Go 1.22+ CLI tool deployed on compute nodes for system info collection
- **Database**: PostgreSQL 16+
- **Communication**: ActionCable WebSocket for bidirectional agent-server messaging

## Common Commands

### Rails Development
```bash
bin/dev                              # Start dev server (Rails + Tailwind watcher)
bin/rspec                            # Run all tests
bin/rspec spec/models/node_spec.rb   # Run single test file
COVERAGE=true bin/rspec              # Run tests with coverage
bin/rubocop                          # Check Ruby style
bin/rubocop -a                       # Auto-fix Ruby style issues
bin/brakeman                         # Security scan
```

### Go Agent Development
```bash
cd agent
go build -o hpc-agent .              # Build agent binary
go test ./...                        # Run all tests
go test -v ./...                     # Verbose test output
golangci-lint run ./...              # Lint Go code
CGO_ENABLED=0 go build -o hpc-agent . # Static binary build
```

### Database
```bash
bin/rails db:migrate                 # Run migrations
bin/rails db:rollback                # Rollback last migration
```

## Architecture

### Hybrid Push/Pull Execution Model
- **Pull (SSH via Gateway)**: Web server triggers `hpc-agent collect` on nodes via SSH through Admin/Bastion host
- **Push (Agent API)**: Agents can proactively push inventory via `hpc-agent inventory push`
- **WebSocket**: Online nodes communicate via ActionCable for real-time operations

### Rails Service Objects Pattern
All complex business logic lives in `app/services/`, keeping controllers skinny:
- `Inventory::TriggerCollectService` - SSH/WebSocket-based node data collection
- `Inventory::ProcessStateService` - State versioning with change detection
- `Inventory::ImportCsvService` - CSV parsing and node import
- `Dashboard::MetricsService` - Dashboard metrics calculations
- `Agent::RemoteInstallService` / `Agent::RemoteUninstallService` - Remote agent management

### Node State Versioning
- `NodeState` records are immutable snapshots of hardware info
- Each collection that detects changes creates a new `NodeState` record (no overwrites)
- Content hash comparison determines if new state should be created

### Go Agent Hexagonal Architecture
- **Core Interfaces** (`agent/core/ports/`): Define boundaries for collectors, uploaders, command runners
- **Models** (`agent/core/model/`): Data structures (HostInfo, CPUInfo, MemoryInfo, etc.)
- **Native Collectors** (`agent/inventory/collector/`): Hardware collection using ghw, gopsutil, dmidecode
- **Stream Client** (`agent/core/stream/`): ActionCable WebSocket implementation

### Agent CLI Commands
- `hpc-agent start` - Daemon mode with WebSocket connection
- `hpc-agent collect` - Output system info as JSON to stdout
- `hpc-agent inventory push` - Collect and upload to server API
- `hpc-agent hpcg` - Run HPCG benchmark workflow (build, configure, run, parse)

## Testing

### Rails (RSpec)
- Model specs: `spec/models/`
- Request specs: `spec/requests/`
- Service specs: `spec/services/`
- System specs: `spec/system/` (Capybara + Playwright)
- Factories: `spec/factories/`

### Go
- Unit tests with stdlib `testing` package
- Interface-based mocking (hand-written mocks)
- Tests in `*_test.go` files alongside source

## Key Patterns

### Hotwire-First Frontend
- Turbo Drive for SPA-like navigation
- Turbo Frames for component isolation
- Turbo Streams for real-time ActionCable updates
- Stimulus.js only when Turbo isn't sufficient
- ViewComponent for reusable UI components

### NetBox-Inspired UI Theme
- Data-dense layouts with slate headers
- Bold uppercase titles, square corners
- Component: `card-netbox` for standardized cards
