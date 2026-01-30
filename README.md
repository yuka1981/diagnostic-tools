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

The Salt custom modules and states in this repository are deployed to the Salt Master using Salt's GitFS backend. Ansible manages the Salt Master and Minion installation and configuration.

#### Architecture

```
                    +-----------------+
                    |   GitHub Repo   |
                    | (diagnostic-    |
                    |  tools.git)     |
                    +--------+--------+
                             |
                      GitFS polling
                      (every 60s)
                             |
+-------------+     +--------v--------+     +-----------------+
|  Rails App  +---->|   Salt Master   +---->|  Compute Nodes  |
| (Cloud/VPS) | API |  (On-Premise)   | ZMQ | (Salt Minions)  |
+-------------+     +-----------------+     +-----------------+
```

**How it works:**

1. Salt Master polls this git repo via GitFS every 60 seconds
2. Custom modules (`salt/_modules/`) auto-sync to minions on `state.apply` or `saltutil.sync_modules`
3. State files (`salt/benchmark/`) are served directly from the repo
4. Reactor SLS files forward benchmark results and minion presence changes to the Rails webhook
5. No Ansible re-run is needed for module or state code changes -- just push to git

#### What Ansible Manages vs What GitFS Manages

| Component | Managed by | Location on Master | Why |
|-----------|------------|-------------------|-----|
| `_modules/*.py` | GitFS | auto-cached from git | Code changes frequently, no secrets |
| `benchmark/**/*.sls` | GitFS | auto-cached from git | State files, no secrets |
| `api.conf`, `gitfs.conf`, `auth.conf` | Ansible | `/etc/salt/master.d/` | Contains credentials and config |
| `reactor.conf`, `reactor/*.sls` | Ansible | `/etc/salt/master.d/` and `/srv/salt/reactor/` | Contains Rails webhook URL |

#### Prerequisites

Before starting, ensure you have:

- **A Salt Master server** (Ubuntu 22.04 or 24.04 recommended) with network access to compute nodes
- **Compute nodes** (Salt Minions) that the Salt Master can reach via ZeroMQ (ports 4505/4506)
- **Ansible 2.14+** installed on your local machine or a control node that can SSH to both the Salt Master and compute nodes
- **A GitHub personal access token** (classic, with `repo` scope) for GitFS to pull this repository
- **SSL certificates** for the Salt API (self-signed or CA-signed)

#### Step 1: Clone This Repository

```bash
git clone https://github.com/yuka1981/diagnostic-tools.git
cd diagnostic-tools
```

#### Step 2: Set Up Ansible Inventory

Create an inventory file that tells Ansible which servers to configure:

```bash
mkdir -p ansible/inventory
cat > ansible/inventory/hosts.yml << 'EOF'
all:
  children:
    salt_master:
      hosts:
        master-node:
          ansible_host: 10.0.0.1        # Replace with your Salt Master IP
          ansible_user: root              # Or a sudo-capable user
    salt_minions:
      hosts:
        compute-001:
          ansible_host: 10.0.1.1
        compute-002:
          ansible_host: 10.0.1.2
        compute-003:
          ansible_host: 10.0.1.3
        # Add more compute nodes as needed
EOF
```

> **Note:** The host group names `salt_master` and `salt_minions` must match exactly -- they are referenced in `ansible/playbooks/salt.yml`.

#### Step 3: Configure Variables

Edit the non-secret variables in `ansible/group_vars/salt_master.yml`:

```yaml
---
salt_version: "3006"

# GitFS -- how Salt Master pulls modules from this repo
salt_gitfs_user: "machine-account"           # GitHub username with repo access
salt_gitfs_branch: "develop"                 # Branch to track
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"
salt_gitfs_update_interval: 60               # Seconds between git polls

# Salt API -- how Rails talks to Salt
salt_api_port: 8000
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# Network
salt_master_address: "10.0.0.1"              # IP that minions use to reach the master
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# References to vault-encrypted secrets (do not change these lines)
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

#### Step 4: Set Up Ansible Vault for Secrets

Secrets are stored in an encrypted vault file. A template is provided at `ansible/group_vars/salt_master/vault.yml.example`.

```bash
# Copy the example to create your vault file
cp ansible/group_vars/salt_master/vault.yml.example \
   ansible/group_vars/salt_master/vault.yml

# Edit it with your real secrets
# Replace the placeholder values with actual credentials
nano ansible/group_vars/salt_master/vault.yml
```

The vault file contains two secrets:

```yaml
---
vault_salt_gitfs_token: "ghp_xxxxxxxxxxxxxxxxxxxx"    # GitHub personal access token
vault_salt_api_password: "your-secure-password-here"  # Password for the Salt API PAM user
```

Now encrypt the file:

```bash
ansible-vault encrypt ansible/group_vars/salt_master/vault.yml
```

You will be prompted to create a vault password. **Remember this password** -- you will need it every time you run the playbook.

> **Security:** The `vault.yml` file is in `.gitignore` and will never be committed. Only the `.example` template is tracked in git.

#### Step 5: Generate SSL Certificates for Salt API

The Salt API requires SSL certificates. On the Salt Master (or generate locally and copy):

```bash
# Create the directory
sudo mkdir -p /etc/salt/pki/api

# Generate a self-signed certificate (valid for 365 days)
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/salt/pki/api/key.key \
  -out /etc/salt/pki/api/cert.crt \
  -subj "/CN=salt-api/O=diagnostic-tools"

# Set permissions
sudo chmod 600 /etc/salt/pki/api/key.key
sudo chmod 644 /etc/salt/pki/api/cert.crt
```

> **Production:** Use proper CA-signed certificates instead of self-signed.

#### Step 6: Set Up SSH Key Authentication

Ansible needs passwordless SSH access to all target hosts:

```bash
# Generate an SSH key if you don't have one
ssh-keygen -t ed25519 -C "ansible-controller"

# Copy to the Salt Master
ssh-copy-id root@10.0.0.1

# Copy to each compute node
ssh-copy-id root@10.0.1.1
ssh-copy-id root@10.0.1.2
ssh-copy-id root@10.0.1.3

# Test connectivity
ansible -i ansible/inventory/hosts.yml all -m ping
```

Expected output:

```
master-node | SUCCESS => { "ping": "pong" }
compute-001 | SUCCESS => { "ping": "pong" }
compute-002 | SUCCESS => { "ping": "pong" }
compute-003 | SUCCESS => { "ping": "pong" }
```

#### Step 7: Run the Ansible Playbook

Deploy Salt Master and Minions:

```bash
# Dry run first (check mode -- no changes made)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/salt.yml \
  --ask-vault-pass \
  --check --diff

# If the dry run looks correct, apply for real
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/salt.yml \
  --ask-vault-pass
```

> **Tip:** To avoid typing the vault password every time, create a password file:
> ```bash
> echo 'your-vault-password' > ~/.vault_pass
> chmod 600 ~/.vault_pass
> ansible-playbook -i ansible/inventory/hosts.yml \
>   ansible/playbooks/salt.yml \
>   --vault-password-file ~/.vault_pass
> ```

**What the playbook does (in order):**

On the Salt Master (`salt_master` role):
1. Downloads the SaltStack GPG key and adds the APT repository
2. Installs `salt-master`, `salt-api`, and `python3-pygit2`
3. Creates a PAM system user for Rails API authentication
4. Deploys `api.conf` (CherryPy REST API configuration)
5. Deploys `gitfs.conf` (GitFS backend pointing to this repo)
6. Deploys `auth.conf` (PAM external_auth permissions)
7. Deploys reactor configuration and SLS files to `/srv/salt/reactor/`
8. Enables and starts `salt-master` and `salt-api` services

On each compute node (`salt_minion` role):
1. Downloads the SaltStack GPG key and adds the APT repository
2. Installs `salt-minion`
3. Deploys `master.conf` with the Salt Master address
4. Enables and starts `salt-minion` service

#### Step 8: Accept Minion Keys on the Salt Master

After the playbook completes, each minion sends a key to the master. You must accept these keys:

```bash
# SSH to the Salt Master
ssh root@10.0.0.1

# List pending keys
salt-key -L

# Accept all pending keys (or accept individually with -a <minion-id>)
salt-key -A -y

# Verify minions are connected
salt '*' test.ping
```

Expected output:

```
compute-001:
    True
compute-002:
    True
compute-003:
    True
```

#### Step 9: Sync Custom Modules

Force an initial sync of the custom modules from GitFS to all minions:

```bash
# On the Salt Master
salt '*' saltutil.sync_modules

# Verify modules are available
salt '*' sys.list_functions inventory
```

Expected output should list functions like `inventory.collect_dmi`, `inventory.collect_numa`, etc.

#### Step 10: Verify the Full Stack

Run these verification commands on the Salt Master:

```bash
# 1. Check Salt Master services are running
systemctl status salt-master salt-api

# 2. Check GitFS is serving files
salt-run fileserver.file_list | head -20
# Should show: _modules/inventory.py, _modules/benchmark.py, benchmark/mlc/init.sls, etc.

# 3. Test the Salt API (from the Rails server or locally)
curl -sk https://localhost:8000/login \
  -H 'Accept: application/json' \
  -d username=rails_salt_user \
  -d password='your-api-password' \
  -d eauth=pam
# Should return a JSON token

# 4. Test a module call via Salt API
TOKEN="<token-from-step-3>"
curl -sk https://localhost:8000/ \
  -H "Accept: application/json" \
  -H "X-Auth-Token: $TOKEN" \
  -d client=local \
  -d tgt='compute-001' \
  -d fun='test.ping'
# Should return: {"return": [{"compute-001": true}]}

# 5. Check reactor files are deployed
ls -la /srv/salt/reactor/
# Should show: job_return.sls, presence_change.sls
```

#### Updating Modules After Initial Deployment

Once deployed, you do **not** need to re-run Ansible to update Salt modules or states. Just push code changes to the tracked branch:

```bash
# Edit a module locally
vim salt/_modules/inventory.py

# Commit and push
git add salt/_modules/inventory.py
git commit -m "feat: add new inventory collector"
git push origin develop

# Salt Master will pick up changes within 60 seconds (gitfs_update_interval)
# To force an immediate update on the master:
ssh root@10.0.0.1 salt-run fileserver.update

# Then sync to minions:
ssh root@10.0.0.1 salt '*' saltutil.sync_modules
```

#### When to Re-run Ansible

Re-run the Ansible playbook only when you need to change **infrastructure configuration**:

- Changing the Salt API port, SSL certificates, or PAM user password
- Changing the GitFS repository URL, branch, or credentials
- Adding/removing minion permissions in `auth.conf`
- Changing the Rails webhook URL for reactors
- Adding new compute nodes (minions)
- Upgrading Salt version

```bash
# Re-run with the same command
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/salt.yml \
  --ask-vault-pass
```

#### Troubleshooting

**Minion cannot connect to master**
```bash
# On the minion, check the service logs
journalctl -u salt-minion -n 50

# Verify the master address is correct
cat /etc/salt/minion.d/master.conf

# Check firewall -- Salt uses ports 4505 (publish) and 4506 (return)
sudo ufw allow 4505/tcp
sudo ufw allow 4506/tcp
```

**GitFS not serving files**
```bash
# On the master, check GitFS status
salt-run fileserver.file_list

# Check pygit2 is installed
python3 -c "import pygit2; print(pygit2.__version__)"

# Check GitFS config
cat /etc/salt/master.d/gitfs.conf

# Force a GitFS update and check for errors
salt-run fileserver.update
journalctl -u salt-master -n 50 | grep -i gitfs
```

**Salt API returns 401 Unauthorized**
```bash
# Verify the PAM user exists
id rails_salt_user

# Test PAM authentication directly
salt -a pam --username=rails_salt_user --password='your-password' '*' test.ping

# Check auth config
cat /etc/salt/master.d/auth.conf
```

**Reactor not forwarding events**
```bash
# Check reactor config
cat /etc/salt/master.d/reactor.conf

# Watch the Salt event bus in real-time
salt-run state.event pretty=True

# Verify reactor files exist
ls -la /srv/salt/reactor/

# Test the webhook URL is reachable from the master
curl -s -o /dev/null -w "%{http_code}" https://your-rails-app.com/api/v1/salt/events
```

**Custom modules not syncing to minions**
```bash
# Force sync
salt '*' saltutil.sync_modules

# Check if modules are cached on the minion
ls /var/cache/salt/minion/extmods/modules/

# Check Salt Master logs for sync errors
journalctl -u salt-master | grep -i sync
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
- **Salt Integration**: Remote execution and inventory collection via SaltStack
- **Shared Storage**: NFS/Lustre for artifact storage
- **Slurm Integration**: Job scheduling for benchmark execution

## CI/CD

This project uses GitHub Actions for continuous integration:

- **Lint**: Rubocop code style checks
- **Security**: Brakeman security scanning
- **Test**: RSpec test suite with PostgreSQL

## License

[Add license information here]
