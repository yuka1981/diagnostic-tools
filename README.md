# HPC System Detection & Benchmark Tool

A web application for monitoring HPC (High Performance Computing) cluster nodes and managing benchmark runs.

## Overview

This tool provides:
- **Node Inventory Management**: View and manage HPC cluster nodes with versioned configuration history
- **Benchmark Execution**: Run and track HPCG benchmarks on cluster nodes
- **Dashboard Visualization**: Real-time metrics and node status heatmaps
- **Artifact Management**: Store and retrieve benchmark results and logs

## Tech Stack

- **Framework**: Ruby on Rails 7.2.3
- **Database**: PostgreSQL 16+
- **Frontend**: Hotwire (Turbo + Stimulus) + Tailwind CSS
- **Testing**: RSpec, FactoryBot, Capybara
- **Linting**: Rubocop (Rails Omakase)
- **CI/CD**: GitHub Actions

## Requirements

- Ruby 3.4.8
- PostgreSQL 16+
- Node.js (for asset compilation)

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/your-org/diagnostic-tools.git
cd diagnostic-tools
```

### 2. Install dependencies

```bash
bundle install
```

### 3. Setup database

```bash
bin/rails db:create
bin/rails db:migrate
```

### 4. Start the development server

```bash
bin/dev
```

The application will be available at `http://localhost:3000`.

## Development

### Running Tests

```bash
# Run all tests
bin/rspec

# Run specific test file
bin/rspec spec/models/node_spec.rb

# Run tests with coverage report
COVERAGE=true bin/rspec
```

### Code Linting

```bash
# Check code style
bin/rubocop

# Auto-fix issues
bin/rubocop -a

# Security scan
bin/brakeman
```

### Database Commands

```bash
# Create migration
bin/rails generate migration AddColumnToTable

# Run migrations
bin/rails db:migrate

# Rollback migration
bin/rails db:rollback
```

## Architecture

See [docs/PRD.md](docs/PRD.md) for the full Product Requirements Document.

### Key Components

- **Web Application**: Rails monolith with Hotwire for SPA-like interactions
- **Agent (Go)**: CLI tool deployed on compute nodes for system information collection
- **Shared Storage**: NFS/Lustre for artifact storage
- **Slurm Integration**: Job scheduling for benchmark execution

## CI/CD

This project uses GitHub Actions for continuous integration:

- **Lint**: Rubocop code style checks
- **Security**: Brakeman security scanning
- **Test**: RSpec test suite with PostgreSQL

## License

[Add license information here]
