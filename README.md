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

To enable the application to collect data from nodes via SSH, you need to configure SSH credentials and ensure qis-agent is installed on the target nodes.

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

The `qis-agent` binary must be available on the target nodes. By default, the service expects the binary to be named `qis-agent` and available in the system PATH.

### Ansible & Profiling Configuration

The application uses Ansible to execute Intel PerfSPECT profiling commands on compute nodes. The architecture follows a three-tier approach:

```
Rails App → SSH to Admin Node → Ansible Playbooks → Target Compute Nodes
```

#### Prerequisites

1. **Admin/Jump Node**: A node with Ansible installed that can reach compute nodes
2. **SSH Access**: The Rails application must be able to SSH to the admin node
3. **Intel PerfSPECT**: The `perfspect` Lmod module must be available on compute nodes
4. **Shared Filesystem**: NFS or Lustre mount accessible from both admin and compute nodes

#### Step-by-Step Setup

**Step 1: Install Ansible on the Admin Node**

```bash
# On the admin node (not the Rails server)
sudo apt update
sudo apt install -y ansible

# Verify installation
ansible --version
```

**Step 2: Configure SSH Key Authentication**

```bash
# On the Rails server, generate an SSH key if not exists
ssh-keygen -t ed25519 -C "diagnostic-tools"

# Copy the public key to the admin node
ssh-copy-id ansible@admin-node.example.com

# Test the connection
ssh ansible@admin-node.example.com "echo 'SSH connection successful'"
```

**Step 3: Deploy Ansible Playbooks to Admin Node**

```bash
# Copy the ansible directory to the admin node
scp -r ansible/ ansible@admin-node.example.com:/opt/diagnostic-tools/

# Or use rsync for incremental updates
rsync -avz ansible/ ansible@admin-node.example.com:/opt/diagnostic-tools/ansible/
```

**Step 4: Configure Ansible Inventory on Admin Node**

```bash
# On the admin node, create inventory file
cat > /opt/diagnostic-tools/ansible/inventory/hosts.yml << 'EOF'
all:
  children:
    compute_nodes:
      hosts:
        compute-001:
          ansible_host: 10.0.1.1
        compute-002:
          ansible_host: 10.0.1.2
EOF
```

**Step 5: Set Environment Variables**

Create a `.env` file or export the following environment variables:

```bash
# Ansible Admin Node Configuration
export ANSIBLE_ADMIN_HOST="admin-node.example.com"
export ANSIBLE_ADMIN_USER="ansible"
export ANSIBLE_PLAYBOOKS_PATH="/opt/diagnostic-tools/ansible"

# Profiling Configuration
export PROFILING_ARTIFACTS_PATH="/shared/profiling_artifacts"
export DEFAULT_PERFSPECT_MODULE="perfspect/3.13.0"

# SSH Configuration (if not using Rails credentials)
export SSH_USER="ansible"
export SSH_KEY_PATH="/home/app/.ssh/id_ed25519"
export SSH_TIMEOUT="30"
```

**Step 6: Create Shared Artifacts Directory**

```bash
# On the shared filesystem (accessible by admin and compute nodes)
sudo mkdir -p /shared/profiling_artifacts
sudo chown ansible:ansible /shared/profiling_artifacts
sudo chmod 755 /shared/profiling_artifacts
```

**Step 7: Verify PerfSPECT Module Availability**

```bash
# On a compute node, verify the module is available
module avail perfspect

# Load and test
module load perfspect/3.13.0
perfspect --version
```

**Step 8: Test Ansible Connectivity**

```bash
# On the admin node, test connectivity to compute nodes
cd /opt/diagnostic-tools/ansible
ansible all -i inventory/hosts.yml -m ping
```

#### Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `ANSIBLE_ADMIN_HOST` | Hostname/IP of the admin node | `localhost` |
| `ANSIBLE_ADMIN_USER` | SSH user on admin node | `ansible` |
| `ANSIBLE_PLAYBOOKS_PATH` | Path to playbooks on admin node | `Rails.root/ansible` |
| `PROFILING_ARTIFACTS_PATH` | Shared filesystem path for results | `/shared/profiling_artifacts` |
| `DEFAULT_PERFSPECT_MODULE` | Lmod module name for PerfSPECT | `perfspect/3.13.0` |

#### Rails Credentials (Alternative)

Instead of environment variables, you can use Rails credentials:

```bash
bin/rails credentials:edit
```

Add the following:

```yaml
ssh:
  user: "ansible"
  key_path: "/home/app/.ssh/id_ed25519"
  timeout: 30

ansible:
  admin_host: "admin-node.example.com"
  admin_user: "ansible"
  playbooks_path: "/opt/diagnostic-tools/ansible"

profiling:
  artifacts_path: "/shared/profiling_artifacts"
  default_module: "perfspect/3.13.0"
```

#### Available Profiling Commands

The following PerfSPECT subcommands are supported:

| Command | Playbook | Description |
|---------|----------|-------------|
| `report` | `perfspect/report.yml` | System configuration report (CPU, memory, BIOS) |
| `telemetry` | `perfspect/telemetry.yml` | Performance metrics collection (default: 60s) |
| `flame` | `perfspect/flame.yml` | CPU flame graph generation (default: 30s) |

#### Troubleshooting

**SSH Connection Failed**
```bash
# Check SSH key permissions
chmod 600 ~/.ssh/id_ed25519

# Test direct SSH connection
ssh -v ansible@admin-node.example.com
```

**Ansible Playbook Not Found**
```bash
# Verify playbook path on admin node
ls -la /opt/diagnostic-tools/ansible/playbooks/perfspect/
```

**PerfSPECT Module Not Available**
```bash
# On compute node, check module paths
echo $MODULEPATH
module spider perfspect
```

### Salt Module Deployment (via Ansible + GitFS)

The Salt custom modules and states in this repository are deployed to the Salt Master using Salt's GitFS backend. Ansible manages the Salt Master and Minion configuration.

#### Ansible Vault Variables

Sensitive credentials are encrypted using Ansible Vault. There are two recommended approaches:

**Option A: Separate vault file for secrets only (Recommended)**

Create a plain variables file and an encrypted vault file:

```bash
# Non-secret variables (plain YAML)
# ansible/group_vars/salt_master.yml
```

```yaml
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# References to vault-encrypted values
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

```bash
# Secrets only (encrypted with Ansible Vault)
ansible-vault create ansible/group_vars/salt_master/vault.yml
```

```yaml
vault_salt_gitfs_token: "ghp_xxxxxxxxxxxxxxxxxxxx"
vault_salt_api_password: "your-secure-password"
```

**Option B: Encrypt individual variables inline**

```bash
ansible-vault encrypt_string 'ghp_xxxxxxxxxxxxxxxxxxxx' --name 'vault_salt_gitfs_token'
```

Then paste the encrypted block directly into `ansible/group_vars/salt_master.yml`.

Run the Salt playbook:

```bash
# Deploy Salt Master and Minions
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/salt.yml --ask-vault-pass

# Or with a vault password file
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/salt.yml --vault-password-file ~/.vault_pass
```

For full details on the Salt module deployment architecture, see [docs/plans/2026-01-30-salt-module-deployment-design.md](docs/plans/2026-01-30-salt-module-deployment-design.md).

---

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

## Agent CLI Guide

The HPC Agent is a Go-based CLI tool that runs on cluster nodes to collect system information and execute benchmarks.

### Building the Agent

To build the qis-agent binary (requires Go 1.22+):

```bash
cd agent
go build -o qis-agent .
```

### Commands

#### `qis-agent collect`
Collects the current node's detailed system information (CPU architecture/topology/cache, Memory, Disk, Network, Host) and outputs it as JSON to stdout.

```bash
./qis-agent collect
```

#### `qis-agent inventory push`
Collects system information and pushes it directly to the web application's API.

```bash
./qis-agent inventory push --server http://your-app-url --token your-api-token
```

**Flags:**
- `--server`: The URL of the web application (default: `http://localhost:3000`).
- `--token`: Authentication token (required). Can also be set via `AGENT_TOKEN` environment variable.

#### `qis-agent hpcg`
Runs the HPCG (High Performance Conjugate Gradients) benchmark workflow. This includes environment setup, native compilation, configuration generation, execution, and result parsing.

```bash
./qis-agent hpcg --id run-001 --module mpi/openmpi --rt 120 --log-path /var/log/hpcg/run-001.txt
```

**Flags:**
- `--id`: Unique Run ID (default: `manual-run`).
- `--module`: Comma-separated list of modules to load.
- `--build`: Custom build command (e.g., `make`).
- `--run`: Custom run command (default: `./xhpcg`).
- `--nx`, `--ny`, `--nz`: Problem dimensions (default: `104`).
- `--rt`: Runtime in seconds (default: `60`).
- `--log-path`: Custom path to save the benchmark log file.
- `--server`: Server URL for uploading results.
- `--token`: API token for uploading results.

**Upload**: Sends results to the web application if `--server` and `--token` are provided.

### Building from Source

A helper script is provided to automate cloning the HPCG repository and running the benchmark using qis-agent:

```bash
./scripts/run_hpcg_from_source.sh
```

This script:
1. Builds the `qis-agent` binary.
2. Clones the official HPCG repository.
3. Uses the `qis-agent hpcg` command to compile (`make`) and run (`mpirun`) the benchmark.

## Development

### Troubleshooting

**CSS Styles Missing / Tailwind Classes Not Working**

If CSS styles appear broken or Tailwind classes like `bg-neutral-2` don't apply, the precompiled assets in `public/assets/` may be stale. This happens when `tailwind.config.js` is updated but assets aren't recompiled.

```bash
# Recompile assets
bin/rails assets:precompile

# Then restart the dev server and hard refresh (Ctrl+Shift+R)
```

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
