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

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/your-org/diagnostic-tools.git
cd diagnostic-tools
```

### 2. Install Ruby dependencies

```bash
bundle install
```

### 3. Setup PostgreSQL (Ubuntu/WSL2)

If PostgreSQL is not installed, follow these steps:

```bash
# Install PostgreSQL 16
sudo apt update
sudo apt install -y postgresql-16 postgresql-contrib-16 libpq-dev

# Start PostgreSQL service
sudo service postgresql start

# Create a PostgreSQL role for your user (run once)
sudo -u postgres createuser -s $USER
```

To ensure PostgreSQL starts automatically on WSL2:

```bash
# Add to your ~/.bashrc or ~/.zshrc
echo 'sudo service postgresql start' >> ~/.bashrc
```

### 4. Setup database

```bash
bin/rails db:create
bin/rails db:migrate
```

### 5. Start the development server

```bash
bin/dev
```

The application will be available at `http://localhost:3000`.

## Configuration

### SSH & Agent Collection

To enable the application to collect data from nodes via SSH, you need to configure SSH credentials and ensure the agent is installed on the target nodes.

#### 1. Credentials

You can configure SSH settings using Rails credentials (`bin/rails credentials:edit`) or Environment Variables.

| Setting | Rails Credential (`ssh:`) | Environment Variable | Description |
|---------|---------------------------|----------------------|-------------|
| User | `user` | `SSH_USER` | SSH username to connect as |
| Key Path | `key_path` | `SSH_KEY_PATH` | Path to the private key file |
| Timeout | `timeout` | `SSH_TIMEOUT` | Connection timeout in seconds (default: 30) |
| Host Key Verification | `verify_host_key` | `SSH_VERIFY_HOST_KEY` | Host key verification strategy (default: strict) |

**Example `config/credentials.yml.enc`:**

```yaml
ssh:
  user: "hpc-admin"
  key_path: "/home/app/.ssh/id_rsa"
  timeout: 10
```

#### 2. Agent Installation

The `agent` binary must be available on the target nodes. By default, the service expects the binary to be named `agent` and available in the system PATH.

## Usage

### Importing Nodes via CSV

You can bulk import nodes using a CSV file. A sample file is provided at `examples/nodes.csv`.

**CSV Format Requirements:**

- **hostname** (Required): Unique hostname for the node
- **ip** (Optional): Valid IP address
- **role** (Optional): One of `compute`, `login`, `admin` (defaults to `compute`)
- **arch** (Optional): CPU architecture (e.g., `x86_64`, `aarch64`)

**Example CSV Content:**

```csv
hostname,ip,role,arch
compute-001,10.0.1.1,compute,x86_64
login-01,192.168.1.10,login,x86_64
admin-node,,admin,aarch64
```

To import nodes via the UI:

1. Navigate to the **Nodes** page in the dashboard.
2. Click the **Import CSV** button.
3. Upload your CSV file using the form.

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
