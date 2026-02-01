# Salt Module Deployment -- Operations Guide

This directory contains SaltStack custom modules, state files, and reactor
configurations for managing HPC cluster nodes. Salt is used to collect hardware
inventory from compute nodes and to run benchmarks (HPCG and MLC) remotely.

The Salt master is deployed and configured automatically using Ansible. Once
running, the master pulls this directory from Git (via GitFS) so that any
changes merged to the tracked branch are picked up automatically.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Directory Structure](#directory-structure)
3. [Setup Guide](#setup-guide)
4. [Testing](#testing)
5. [Custom Modules Reference](#custom-modules-reference)
6. [Benchmark Orchestration](#benchmark-orchestration)
7. [Reactor Events](#reactor-events)
8. [Troubleshooting](#troubleshooting)
9. [Security Notes](#security-notes)

---

## Prerequisites

Before you begin, make sure you have the following:

- **Ansible 2.14+** installed on your control machine (laptop or jump host).
- **SSH access** from the control machine to all target servers (master and
  minions) with a user that has sudo privileges.
- **Target servers** running Rocky Linux 9 / RHEL 9 / AlmaLinux 9, or
  Ubuntu 20.04+ / Debian 11+. The Ansible roles detect the OS family
  automatically and use `dnf` (RHEL) or `apt` (Debian) accordingly.
- **Network connectivity** between the Salt master and all minion nodes on
  ports **4505** and **4506** (Salt's ZeroMQ transport).
- **Port 8000** open on the Salt master for the Salt REST API (used by the
  Rails application).
- A **GitHub personal access token** (or machine account token) with read
  access to the repository, so the master can pull states via GitFS.
- **Python 3.8+** and **pytest** installed locally if you want to run the unit
  tests.

---

## Directory Structure

```
salt/
├── _modules/                    # Custom Salt execution modules
│   ├── benchmark.py             # Benchmark execution (HPCG, MLC)
│   └── inventory.py             # System inventory collection
├── _tests/                      # Unit tests for the custom modules
│   ├── __init__.py
│   ├── test_benchmark.py        # Tests for benchmark module
│   └── test_inventory.py        # Tests for inventory module
├── benchmark/                   # Salt state files for benchmark orchestration
│   ├── hpcg/
│   │   ├── init.sls             # Main HPCG orchestrator (includes prepare, execute, collect)
│   │   ├── prepare.sls          # Create work directory and verify hpcg binary
│   │   ├── execute.sls          # Run benchmark.run_hpcg via module.run
│   │   └── collect.sls          # Push artifacts back to the master via cp.push_dir
│   └── mlc/
│       ├── init.sls             # Main MLC orchestrator (includes prepare, execute, collect)
│       ├── prepare.sls          # Create work directory and verify mlc binary
│       ├── execute.sls          # Run benchmark.run_mlc via module.run
│       └── collect.sls          # Push artifacts back to the master via cp.push_dir
├── master.d/
│   └── api.conf                 # Reference copy of Salt API config (actual config deployed by Ansible)
└── reactor/
    ├── job_return.sls           # POST to Rails when benchmark jobs complete
    └── presence_change.sls      # POST to Rails when minions connect or disconnect
```

The Ansible files that deploy Salt live in the repository root under `ansible/`:

```
ansible/
├── ansible.cfg                          # Ansible config (roles path, inventory, vault)
├── playbooks/
│   └── salt.yml                         # Main playbook (two plays: master + minions)
├── inventory/
│   ├── hosts.yml                        # Inventory file (INI format)
│   └── group_vars/
│       ├── salt_minions.yml             # Minion group variables
│       └── salt_master/
│           ├── main.yml                 # Non-secret master variables
│           ├── vault.yml                # Encrypted secrets (not in Git)
│           └── vault.yml.example        # Template for encrypted secrets
└── roles/
    ├── salt_master/                     # Installs and configures the Salt master
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   ├── install.yml              # APT repo + packages
    │   │   ├── configure.yml            # Deploy api.conf
    │   │   ├── gitfs.yml                # Configure GitFS backend
    │   │   ├── auth.yml                 # PAM auth with function-level ACLs
    │   │   ├── reactor.yml              # Deploy reactor SLS files
    │   │   └── service.yml              # Enable and start services
    │   └── templates/
    │       ├── api.conf.j2
    │       ├── auth.conf.j2
    │       ├── gitfs.conf.j2
    │       ├── reactor.conf.j2
    │       ├── job_return.sls.j2
    │       └── presence_change.sls.j2
    └── salt_minion/                     # Installs and configures Salt minions
        ├── defaults/main.yml
        ├── handlers/main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── install.yml              # APT repo + packages
        │   ├── configure.yml            # Point minion to master
        │   └── service.yml              # Enable and start salt-minion
        └── templates/
            └── minion.conf.j2
```

---

## Setup Guide

### Step 1: Configure the Ansible Inventory

Create an inventory file that defines two host groups: `salt_master` (one host)
and `salt_minions` (one or more compute nodes).

Create the file at `ansible/inventory/hosts.yml`:

```ini
[salt_master]
salt-master-01  ansible_host=10.0.0.1

[salt_minions]
compute-01      ansible_host=10.0.1.1
compute-02      ansible_host=10.0.1.2
compute-03      ansible_host=10.0.1.3

[all:vars]
ansible_user=deploy
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Replace the hostnames, IP addresses, and SSH settings with your actual values.

---

### Step 2: Configure Variables

Edit `ansible/inventory/group_vars/salt_master/main.yml` to match your
environment. The defaults are:

```yaml
salt_version: "3006"

# GitFS -- the master pulls salt/ states from this repo
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"
salt_gitfs_update_interval: 60

# Salt REST API
salt_api_port: 8000
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# Network
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# References to vault-encrypted secrets (do not put real values here)
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

Key values to update:

| Variable | What to set it to |
|---|---|
| `salt_master_address` | The IP or hostname your minions will use to reach the master |
| `salt_gitfs_repo` | The Git URL for this repository |
| `salt_gitfs_branch` | The branch the master should track (e.g., `develop` or `main`) |
| `rails_webhook_url` | The full URL of the Rails webhook endpoint |
| `salt_api_ssl_cert` / `salt_api_ssl_key` | Paths to your SSL certificate and key on the master |

The minion role uses defaults from `ansible/roles/salt_minion/defaults/main.yml`:

```yaml
salt_version: "3006"
salt_master_address: "salt"
```

If your master hostname is not resolvable as `salt`, override
`salt_master_address` in a `group_vars/salt_minions.yml` file or in your
inventory.

---

### Step 3: Create the Ansible Vault

Secrets (the GitHub token for GitFS and the Salt API password) must be stored
in an encrypted vault file. A template is provided.

```bash
# Copy the example file
cp ansible/inventory/group_vars/salt_master/vault.yml.example \
   ansible/inventory/group_vars/salt_master/vault.yml

# Edit the file and replace placeholder values, then encrypt
ansible-vault encrypt ansible/inventory/group_vars/salt_master/vault.yml
```

Before encrypting, edit `vault.yml` and replace the placeholder values:

```yaml
vault_salt_gitfs_token: "ghp_your_actual_github_token_here"
vault_salt_api_password: "a_strong_random_password"
```

> **Note:** Never commit the unencrypted `vault.yml` to version control. Only
> the `.example` file should be checked in.

---

### Step 4: Deploy the Salt Master

Run the playbook with the `--limit` flag to deploy only the master first:

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_master \
  --ask-vault-pass
```

> **Note:** The `ansible.cfg` file sets the default inventory and vault
> password file, so you do not need `-i` if your `ansible.cfg` is configured.
> If you prefer to skip the vault password prompt, set
> `vault_password_file = ~/.vault_pass` in `ansible.cfg`.

This will:

1. Add the SaltStack package repository (from `packages.broadcom.com`) and
   install `salt-master` and `salt-api`. On RHEL, also installs EPEL and
   `pygit2` into Salt's bundled Python via `salt-pip`.
2. Create the PAM user (`rails_salt_user`) for API authentication.
3. Deploy configuration files under `/etc/salt/master.d/`:
   - `api.conf` -- REST API settings (port 8000, SSL, Tornado)
   - `gitfs.conf` -- GitFS backend pointing to this repository
   - `auth.conf` -- PAM external auth with function-level permissions
   - `reactor.conf` -- Reactor event-to-SLS mappings
4. Deploy reactor SLS files to `/srv/salt/reactor/`.
5. Enable and start `salt-master` and `salt-api` services.

Verify the master is running:

```bash
ssh salt-master-01 'sudo systemctl status salt-master salt-api'
```

---

### Step 5: Deploy the Salt Minions

```bash
cd ansible

ansible-playbook playbooks/salt.yml \
  --limit salt_minions \
  --ask-vault-pass
```

This will:

1. Add the SaltStack package repository and install `salt-minion`.
2. Deploy `/etc/salt/minion.d/master.conf` pointing the minion to the master
   address.
3. Enable and start the `salt-minion` service.

> **Note:** You can deploy both master and minions in a single run by omitting
> `--limit`. The playbook runs the master play first, then the minions play.

---

### Step 6: Accept Minion Keys

When a minion starts, it sends its public key to the master. You must accept
these keys before the master will communicate with the minion.

On the Salt master:

```bash
# List all pending keys
sudo salt-key --list unaccepted

# Accept a specific minion
sudo salt-key --accept compute-01

# Or accept all pending keys at once
sudo salt-key --accept-all
```

To verify that accepted minions are reachable:

```bash
sudo salt '*' test.ping
```

Expected output:

```
compute-01:
    True
compute-02:
    True
compute-03:
    True
```

> **Note:** If `test.ping` returns no output or times out, check that ports
> 4505 and 4506 are open between the master and minions. See
> [Troubleshooting](#troubleshooting) for more details.

---

### Step 7: Sync Custom Modules

The custom execution modules (`inventory` and `benchmark`) live in this
repository under `salt/_modules/`. The master pulls them via GitFS, but each
minion needs to download them before they can be used.

```bash
# Sync modules to all minions
sudo salt '*' saltutil.sync_modules
```

Expected output:

```
compute-01:
    - modules.inventory
    - modules.benchmark
compute-02:
    - modules.inventory
    - modules.benchmark
```

> **Note:** Module sync happens automatically when the master restarts (via an
> Ansible handler), but you should run it manually after the first deployment
> or whenever you update the module code.

---

### Step 8: Verify the Setup

Run a few commands to confirm everything is working:

```bash
# Check that all minions respond
sudo salt '*' test.ping

# Verify the custom inventory module is available
sudo salt 'compute-01' sys.doc inventory

# Collect DMI information from a single node
sudo salt 'compute-01' inventory.collect_dmi

# Collect CPU topology from all nodes
sudo salt '*' inventory.collect_cpu

# Check grains (Salt's built-in system facts)
sudo salt 'compute-01' grains.items
```

If `inventory.collect_dmi` returns an error about `dmidecode not found`, make
sure `dmidecode` is installed on the minion (`sudo apt install dmidecode`).

---

## Testing

### Running Unit Tests Locally

The unit tests are in `salt/_tests/` and use pytest with unittest.mock to
simulate system calls. No Salt installation is required to run them.

```bash
# From the repository root
python -m pytest salt/_tests/ -v
```

Expected output:

```
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_returns_structured_data PASSED
salt/_tests/test_inventory.py::TestCollectDmi::test_collect_dmi_handles_missing_dmidecode PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_returns_topology PASSED
salt/_tests/test_inventory.py::TestCollectNuma::test_collect_numa_handles_no_numa PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_returns_devices PASSED
salt/_tests/test_inventory.py::TestCollectNetworkV2::test_collect_network_v2_handles_lshw_failure PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_returns_list_of_devices PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_empty_output PASSED
salt/_tests/test_inventory.py::TestParseDmiMemory::test_parse_dmi_memory_handles_no_devices PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_collect_meminfo_parses_proc_meminfo PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_empty PASSED
salt/_tests/test_inventory.py::TestCollectMeminfo::test_parse_proc_meminfo_handles_plain_integers PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_returns_results PASSED
salt/_tests/test_benchmark.py::TestRunHpcg::test_run_hpcg_handles_failure PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_sends_sigterm PASSED
salt/_tests/test_benchmark.py::TestCancel::test_cancel_returns_error_when_no_process PASSED
```

### Testing Inventory Collection on a Live Minion

Once the Salt master and minions are deployed, test each inventory function:

```bash
# DMI data (BIOS, system, baseboard, memory DIMMs)
sudo salt 'compute-01' inventory.collect_dmi

# Memory stats from /proc/meminfo
sudo salt 'compute-01' inventory.collect_meminfo

# NUMA topology (node count, CPU lists, memory per node)
sudo salt 'compute-01' inventory.collect_numa

# CPU topology (sockets, cores, threads, model name, flags)
sudo salt 'compute-01' inventory.collect_cpu

# Network devices via lshw (name, driver, speed, MAC, vendor)
sudo salt 'compute-01' inventory.collect_network_v2
```

### Testing Benchmark Execution

> **Note:** The benchmark binaries (`hpcg` and `mlc`) must already be installed
> on the minion and available in `$PATH` (or you must specify the full path via
> `binary_path` for MLC).

```bash
# Run HPCG benchmark on a single node
sudo salt 'compute-01' benchmark.run_hpcg \
  work_dir=/tmp/hpcg \
  run_id=test-run-001

# Run MLC benchmark with quick profile
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test-run-002 \
  binary_path=/opt/mlc/mlc \
  profile=quick
```

---

## Custom Modules Reference

### inventory module

| Function | Description | Key System Dependencies |
|---|---|---|
| `inventory.collect_dmi()` | Collects BIOS, system, baseboard, and memory DIMM details via `dmidecode -t 0,1,2,17`. Returns a dict with keys `bios`, `system`, `baseboard`, and `memory` (list of DIMMs). | `dmidecode` |
| `inventory.collect_meminfo()` | Parses `/proc/meminfo` and returns a dict of memory values in kB (e.g., `MemTotal`, `MemFree`, `SwapTotal`). | None (reads `/proc/meminfo`) |
| `inventory.collect_numa()` | Reads NUMA topology from `/sys/devices/system/node/`. Returns `node_count` and a `nodes` dict mapping node number to `cpulist` and `memory_kb`. | None (reads `/sys`) |
| `inventory.collect_cpu()` | Parses `/proc/cpuinfo` to extract CPU topology. Returns `model_name`, `sockets`, `cores`, `cores_per_socket`, `threads`, `threads_per_core`, and `flags`. | None (reads `/proc/cpuinfo`) |
| `inventory.collect_network_v2()` | Collects NIC information using `lshw -class network -json`. Returns a `devices` list with `name`, `product`, `vendor`, `mac`, `driver`, `speed`, `link`, and `pci_slot` for each interface. | `lshw` |

### benchmark module

| Function | Description | Parameters |
|---|---|---|
| `benchmark.run_hpcg(work_dir, run_id, timeout=3600)` | Runs the `hpcg` binary in the given work directory. Returns status (`PASS`/`FAIL`), parsed metrics (e.g., `gflops`), timestamps, log content, and a list of artifact file paths. | `work_dir` (str), `run_id` (str), `timeout` (int, seconds) |
| `benchmark.run_mlc(work_dir, run_id, binary_path='mlc', profile='quick', timeout=3600)` | Runs MLC. In `quick` profile, measures idle latency and peak injection bandwidth. Returns the same structure as `run_hpcg` with MLC-specific metrics (e.g., `idle_latency_ns`). | `work_dir` (str), `run_id` (str), `binary_path` (str), `profile` (str), `timeout` (int, seconds) |
| `benchmark.cancel()` | Finds a running `hpcg` or `mlc` process via `pgrep` and sends SIGTERM. Returns `{success: True, pid: ...}` or an error dict. | None |

---

## Benchmark Orchestration

Benchmarks can be run either by calling the execution module directly or by
applying a Salt state that orchestrates the full workflow (prepare, execute,
collect).

### Running via Salt States (Recommended)

The state files under `salt/benchmark/` provide a three-phase workflow:

1. **Prepare** -- Create the work directory and verify the benchmark binary is
   installed.
2. **Execute** -- Run the benchmark via the custom execution module.
3. **Collect** -- Push output artifacts from the minion back to the master
   using `cp.push_dir`.

#### HPCG

```bash
sudo salt 'compute-01' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-20260131-001", "work_dir": "/tmp/hpcg"}'
```

#### MLC

```bash
sudo salt 'compute-01' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-20260131-001", "work_dir": "/tmp/mlc", "binary_path": "/opt/mlc/mlc", "profile": "quick"}'
```

### Running on Multiple Nodes

Use a glob or list target to run benchmarks across multiple nodes:

```bash
# All compute nodes
sudo salt 'compute-*' state.apply benchmark.hpcg \
  pillar='{"run_id": "hpcg-batch-001", "work_dir": "/tmp/hpcg"}'

# Specific nodes
sudo salt -L 'compute-01,compute-02' state.apply benchmark.mlc \
  pillar='{"run_id": "mlc-batch-001", "work_dir": "/tmp/mlc", "binary_path": "mlc"}'
```

### Where Artifacts End Up

After the collect phase, artifacts are pushed to the master and stored under:

```
/var/cache/salt/master/minions/<minion-id>/files/<work_dir>/
```

For example, for `compute-01` with `work_dir=/tmp/hpcg`:

```
/var/cache/salt/master/minions/compute-01/files/tmp/hpcg/
```

---

## Reactor Events

The Salt master monitors two event patterns on its event bus and forwards them
to the Rails application via HTTP POST.

### Presence Changes

- **Event tag:** `salt/presence/change`
- **Trigger:** A minion connects to or disconnects from the master.
- **Reactor file:** `/srv/salt/reactor/presence_change.sls`
- **Payload sent to Rails:**

```json
{
  "tag": "salt/presence/change",
  "new": ["compute-03"],
  "lost": []
}
```

This allows the Rails application to track which nodes are online.

### Benchmark Job Returns

- **Event tag:** `salt/job/ret/*`
- **Trigger:** Any job completes on a minion. The reactor filters for jobs
  where the function name contains `benchmark` or the state being applied
  includes `benchmark`.
- **Reactor file:** `/srv/salt/reactor/job_return.sls`
- **Payload sent to Rails:**

```json
{
  "tag": "salt/job/ret/20260131120000000000",
  "fun": "benchmark.run_hpcg",
  "id": "compute-01",
  "jid": "20260131120000000000",
  "retcode": 0,
  "return": { "status": "PASS", "metrics": { "gflops": 45.67 }, "..." : "..." }
}
```

Both reactors authenticate to Rails using a Bearer token read from the master
configuration (`rails_api_token`).

---

## Troubleshooting

This section documents issues encountered during real deployments, with
step-by-step solutions.

### Deployment Checklist

If you are deploying for the first time, issues tend to appear in this order.
Use this checklist to verify each step before moving to the next.

```
1. Ansible playbook runs without errors
   - [ ] Salt packages install (check repo URL if DNS fails)
   - [ ] group_vars load correctly (check directory structure)
   - [ ] PAM user is created

2. salt-master service starts
   - [ ] Config files owned by salt:salt (not root:root)
   - [ ] SSL certificates exist at /etc/salt/pki/api/
   - [ ] Ports 4505, 4506, 8000 are listening

3. salt-minion connects
   - [ ] Firewall allows ports 4505 and 4506
   - [ ] Minion config points to correct master address
   - [ ] Minion key accepted on master (salt-key -A)

4. Custom modules work
   - [ ] GitFS serves files (salt-run fileserver.file_list)
   - [ ] pygit2 installed in Salt's Python (not system Python)
   - [ ] Modules synced to minions (salt '*' saltutil.sync_modules)

5. Salt API responds
   - [ ] PAM auth works (shadow group permissions on RHEL)
   - [ ] API login returns a token
   - [ ] API commands return results (master fully initialized)
```

Use `sudo salt '*' test.ping` after each major step to verify connectivity.

### Salt repo URL: "Could not resolve host: repo.saltproject.io"

**Symptom:** The Ansible install task fails with a DNS or connection error
when trying to download packages from `repo.saltproject.io`.

**Cause:** The Salt Project shut down `repo.saltproject.io` in October 2024
and migrated to Broadcom's infrastructure. The old URL no longer resolves.

**Fix:** The Ansible roles in this repository already use the new URLs. If
you see this error, you may be running an older version of the roles. The
correct repository sources are:

| OS Family | Repository URL |
|---|---|
| RHEL / Rocky | `https://packages.broadcom.com/artifactory/saltproject-rpm/` |
| Debian / Ubuntu | `https://packages.broadcom.com/artifactory/saltproject-deb/` |
| GPG Key | `https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public` |

For RHEL, the simplest approach is to download the official repo file:

```bash
curl -fsSL https://github.com/saltstack/salt-install-guide/releases/latest/download/salt.repo \
  | sudo tee /etc/yum.repos.d/salt.repo
```

---

### group_vars not loaded: "'salt_api_password' is undefined"

**Symptom:** The playbook fails with `'salt_api_password' is undefined` or
similar errors for variables that are clearly defined in `group_vars/`.
Running `ansible -m debug -a "var=salt_api_password" salt_master` works
fine, but `ansible-playbook` does not.

**Cause:** Ansible resolves `group_vars/` relative to the **inventory
directory** or the **playbook directory**, not the project root. If
`group_vars/` is at `ansible/group_vars/` but your inventory is at
`ansible/inventory/hosts.yml`, the playbook cannot find the variables.

**Fix:** Place `group_vars/` inside the `inventory/` directory:

```
ansible/inventory/
├── hosts.yml
└── group_vars/
    ├── salt_minions.yml
    └── salt_master/
        ├── main.yml            # non-secret variables
        ├── vault.yml           # encrypted secrets
        └── vault.yml.example
```

Also, do not have both `group_vars/salt_master.yml` (file) and
`group_vars/salt_master/` (directory) at the same level. Ansible may only
load one of them. Move the file into the directory as `main.yml`.

---

### group_vars file vs. directory conflict

**Symptom:** Some variables from `group_vars/salt_master.yml` load but
vault variables from `group_vars/salt_master/vault.yml` do not (or vice
versa).

**Cause:** Having both a file `group_vars/salt_master.yml` and a directory
`group_vars/salt_master/` causes a conflict. Ansible may only process one.

**Fix:** Use the directory form exclusively:

```bash
# Move the file into the directory
mv group_vars/salt_master.yml group_vars/salt_master/main.yml
```

---

### Config file permission denied: salt-master fails to start

**Symptom:** `systemctl status salt-master` shows `failed` with
`PermissionError: [Errno 13] Permission denied: '/etc/salt/master.d/api.conf'`.

**Cause:** On RHEL/Rocky, the `salt-master` service runs as the `salt` user
(not root). If config files in `/etc/salt/master.d/` are owned by
`root:root` with mode `0640`, the `salt` user cannot read them.

**Fix:** All config files deployed to `/etc/salt/master.d/` must be owned
by `salt:salt`:

```bash
# Quick fix on the master
sudo chown salt:salt /etc/salt/master.d/*.conf
sudo systemctl restart salt-master
```

The Ansible roles in this repository set `owner: salt` and `group: salt` on
all template tasks. If you see this error, verify your role files use:

```yaml
- name: Deploy configuration
  ansible.builtin.template:
    src: some_config.j2
    dest: /etc/salt/master.d/some_config.conf
    owner: salt
    group: salt
    mode: '0640'
```

---

### Missing SSL certificates: salt-api not listening on port 8000

**Symptom:** `ss -tlnp | grep 8000` shows nothing. The `salt-api` service
may be running but the REST endpoint is unreachable.

**Cause:** The `api.conf` references SSL cert/key files that do not exist:

```yaml
rest_tornado:
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key
```

**Fix:** Generate a self-signed certificate (suitable for testing):

```bash
sudo mkdir -p /etc/salt/pki/api
sudo openssl req -x509 -nodes -days 3650 \
  -newkey rsa:2048 \
  -keyout /etc/salt/pki/api/key.key \
  -out /etc/salt/pki/api/cert.crt \
  -subj "/CN=$(hostname)/O=SaltStack"
sudo chown salt:salt /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo chmod 640 /etc/salt/pki/api/cert.crt /etc/salt/pki/api/key.key
sudo systemctl restart salt-api
```

The Ansible role generates self-signed certificates automatically. For
production, replace these with certificates from your organization's CA.

---

### pygit2 not found: "gitfs is configured but could not be loaded"

**Symptom:** The master log shows:

```
[ERROR   ] gitfs is configured but could not be loaded, are pygit2 and libgit2 installed?
[CRITICAL] No suitable gitfs provider module is installed.
```

GitFS returns no files, and `salt-run fileserver.file_list` is empty.

**Cause:** Salt 3006+ (onedir packages) bundles its own Python at
`/opt/saltstack/salt/bin/python3`. The system `python3-pygit2` package is
invisible to Salt because Salt does not use the system Python.

**Fix:** Install pygit2 into Salt's bundled Python:

```bash
# RHEL: install patchelf first (required for the pygit2 wheel)
sudo dnf install -y patchelf

# Install pygit2 in Salt's Python
sudo /opt/saltstack/salt/bin/pip3 install pygit2

# Restart to pick up the new module
sudo systemctl restart salt-master

# Verify
sudo salt-run fileserver.update
sudo salt-run fileserver.file_list
```

> **Note:** The system `python3-pygit2` package (installed via `dnf` or `apt`)
> is NOT used by Salt 3006+. You must install it via Salt's pip.

---

### PAM auth fails: "Could not authenticate using provided credentials"

**Symptom:** Salt API login returns 401. The master log shows:

```
unix_chkpwd: password check failed for user (rails_salt_user)
pam_unix(login:auth): authentication failure ... user=rails_salt_user
[ERROR   ] Pam auth failed for rails_salt_user
```

**Cause:** On RHEL/Rocky, `salt-master` runs as the `salt` user (not root).
PAM uses `unix_chkpwd` to verify passwords against `/etc/shadow`, but
`/etc/shadow` has mode `0000` by default — the `salt` user cannot read it.

Additionally, if the PAM user has `/usr/sbin/nologin` as its shell, PAM
may reject the authentication entirely.

**Fix (two parts):**

1. Grant the `salt` user read access to `/etc/shadow` via a shadow group:

```bash
sudo groupadd -f shadow
sudo usermod -aG shadow salt
sudo chgrp shadow /etc/shadow
sudo chmod g+r /etc/shadow
sudo systemctl restart salt-master
```

2. Ensure the PAM user has a valid shell:

```bash
sudo usermod -s /bin/bash rails_salt_user
```

The Ansible roles in this repository handle both of these automatically.

---

### Salt API commands timeout: "The master is not responding"

**Symptom:** API login works (returns a token), but any command execution
(`test.ping`, `get_minions`, etc.) returns:

```
Salt request timed out. The master is not responding.
```

**Cause:** This can happen when:

- The `salt-master` process has not fully initialized (it needs up to 60-90
  seconds after starting before all workers are ready).
- The `MWorkerQueue` process is stuck in a CPU spin loop (a known Salt 3006
  ZMQ issue). Check with: `ps aux | grep MWorkerQueue`
- The salt-api was started before the master finished initializing.

**Fix:**

1. Stop salt-api, restart salt-master, wait, then start salt-api:

```bash
sudo systemctl stop salt-api
sudo systemctl restart salt-master
sleep 60    # wait for master to fully initialize
sudo systemctl start salt-api
```

2. Verify the master is healthy before starting the API:

```bash
# All ports should be listening before starting salt-api
sudo ss -tlnp | grep -E '4505|4506'

# CLI ping should work
sudo salt '*' test.ping --timeout=15
```

3. If `MWorkerQueue` is at high CPU (50%+), stop and clean start:

```bash
sudo systemctl stop salt-api
sudo systemctl stop salt-master
sudo rm -f /var/run/salt/master/*.ipc
sudo systemctl start salt-master
sleep 60
sudo systemctl start salt-api
```

> **Note:** The `rest_tornado` backend (used by this deployment) is
> recommended over `rest_cherrypy` for Salt 3006, as it avoids certain
> CherryPy-related busy loop issues.

---

### Firewall blocking minion connections

**Symptom:** Minion keys do not appear on the master (`salt-key -L` shows
no unaccepted keys). The minion log shows timeout errors.

**Cause:** The firewall on the master is blocking ports 4505 and 4506.

**Fix (firewalld on RHEL/Rocky):**

```bash
# On the Salt master
sudo firewall-cmd --permanent --add-port=4505/tcp
sudo firewall-cmd --permanent --add-port=4506/tcp
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-ports
```

**Required ports:**

| Port | Direction | Protocol | Purpose |
|---|---|---|---|
| 4505 | Minion to Master | TCP | Salt publish (ZeroMQ) |
| 4506 | Minion to Master | TCP | Salt return (ZeroMQ) |
| 8000 | Rails to Master | TCP | Salt REST API (HTTPS) |

> **Note:** The Ansible `salt_master` role now includes a `firewall.yml` task that
> automatically opens these ports via `firewall-cmd` when firewalld is active.
> Re-running the playbook will fix firewall issues without manual intervention.

---

### SELinux blocking Salt communication

**Symptoms:** Salt commands timeout with `Message timed out` or `Unable to connect
to the salt master publisher`, `ausearch -m AVC` shows Salt-related denials.

**Cause:** SELinux in Enforcing mode may block Salt's ZeroMQ IPC sockets, port
binding, or execution of the bundled Python at `/opt/saltstack/salt/`.

**Diagnosis:**

```bash
# Check SELinux mode
sudo getenforce

# Search for Salt-related AVC denials
sudo ausearch -m AVC -ts today | grep -i salt

# Analyze denials
sudo ausearch -m AVC -ts today | grep salt | audit2why
```

**Fix — Ansible playbook (recommended):**

The Ansible `salt_master` and `salt_minion` roles include `selinux.yml` tasks that
automatically deploy custom SELinux policy modules when SELinux is Enforcing. The
playbook handles:

- Installing SELinux management tools (`policycoreutils-python-utils`, `checkpolicy`)
- Labeling port 8000 as `http_port_t` for salt-api
- Enabling `httpd_can_network_connect` SELinux boolean
- Restoring file contexts on Salt directories (`/etc/salt`, `/var/cache/salt`,
  `/var/run/salt`, `/var/log/salt`, `/opt/saltstack/salt`)
- Compiling and installing custom Type Enforcement policy modules
  (`salt_master_selinux`, `salt_minion_selinux`)

Re-run the playbook to apply:

```bash
cd ansible/
ansible-playbook playbooks/salt.yml --tags selinux
```

**Fix — Manual:**

```bash
# Verify the custom policy is installed
sudo semodule -l | grep salt

# If not installed, temporarily set permissive to collect denials
sudo setenforce 0

# Exercise Salt functionality, then generate policy from audit log
sudo ausearch -m AVC -ts recent | grep salt | audit2allow -M salt_local
sudo semodule -i salt_local.pp

# Re-enable enforcing
sudo setenforce 1
```

**Custom policy modules cover:**

| Permission | Purpose |
|---|---|
| ZeroMQ port binding (4505/4506) | Master publish and return channels |
| IPC socket management (`/var/run/salt/`) | Inter-process communication |
| Bundled Python execution (`/opt/saltstack/salt/`) | Salt onedir package runtime |
| HTTP port binding (8000) | Salt API (master only) |
| SSL certificate access | Salt API HTTPS |

---

### Managing minion auto-accept

Auto-accept allows the Salt master to automatically trust any connecting minion
without manual key approval. This is convenient for development and lab
environments but should be disabled in production.

**Check current setting:**

```bash
cd ansible/
ansible-playbook playbooks/auto-accept.yml --tags status
```

**Enable auto-accept:**

```bash
cd ansible/
ansible-playbook playbooks/auto-accept.yml -e "auto_accept=true"
```

**Disable auto-accept:**

```bash
cd ansible/
ansible-playbook playbooks/auto-accept.yml -e "auto_accept=false"
```

> **Security warning:** With `auto_accept: true`, any host that can reach ports
> 4505/4506 will be trusted as a minion. Always disable in production and use
> `sudo salt-key -A` to manually accept keys.

---

### Minion keys not appearing

**Symptom:** `salt-key --list unaccepted` shows no pending keys after starting
minions.

**Possible causes:**

- The minion cannot reach the master on port 4505. Check firewall rules (see
  above).
- The `salt_master_address` in the minion config does not resolve. Verify:
  `ssh compute-01 'getent hosts <master-address>'`
- The minion service is not running:
  `ssh compute-01 'sudo systemctl status salt-minion'`

```bash
# On the minion, check the log for connection errors
sudo journalctl -u salt-minion --no-pager -n 50
```

---

### Custom modules not found

**Symptom:** Running `salt 'compute-01' inventory.collect_dmi` returns
`'inventory.collect_dmi' is not available`.

**Fix:** Sync the modules:

```bash
sudo salt '*' saltutil.sync_modules
```

If sync returns an empty list, the master may not have pulled the modules from
Git yet. Force a GitFS update:

```bash
sudo salt-run fileserver.update
sudo salt '*' saltutil.sync_modules
```

---

### Benchmark binary not found

**Symptom:** `benchmark.run_hpcg` or state apply returns an error about the
binary not being found.

**Fix:** Install the benchmark binary on the minion and make sure it is in the
system `$PATH`, or provide the full path using the `binary_path` parameter for
MLC:

```bash
sudo salt 'compute-01' benchmark.run_mlc \
  work_dir=/tmp/mlc \
  run_id=test \
  binary_path=/usr/local/bin/mlc
```

---

### Reactor not firing

**Symptom:** Rails is not receiving webhook events.

**Check:**

```bash
# Watch the Salt event bus in real time
sudo salt-run state.event pretty=True

# Look for reactor errors in the master log
sudo grep -i reactor /var/log/salt/master | tail -20
```

Make sure `rails_webhook_url` is set correctly in the master group vars and
that the Rails application is reachable from the master.

---

## Security Notes

### Ansible Vault

All secrets (GitHub token, Salt API password) are stored in an Ansible Vault
encrypted file at `ansible/inventory/group_vars/salt_master/vault.yml`. The unencrypted
example file (`vault.yml.example`) shows the expected variable names but
contains only placeholder values.

- Always use `--ask-vault-pass` (or `--vault-password-file`) when running the
  playbook.
- Never commit decrypted secrets to Git.

### PAM Authentication

The Salt API uses PAM external authentication. The Ansible role creates a
system user (`rails_salt_user` by default) with `no_log: true` to prevent
the password hash from appearing in Ansible output.

The user is created with `/bin/bash` as its shell to allow PAM authentication
on RHEL systems. The user has no home directory and is a system account, so
it is not intended for interactive SSH access.

### Function-Level Permissions

The PAM user is granted access to a specific whitelist of Salt functions:

- `grains.items`
- `inventory.*`
- `benchmark.run_hpcg`, `benchmark.run_mlc`, `benchmark.cancel`
- `test.ping`
- `state.apply`
- `cmd.run`
- `cp.push`, `cp.push_dir`
- `saltutil.sync_modules`
- Runner: `manage.status`

This means the API user cannot execute arbitrary Salt functions outside this
list.

### SSL/TLS

The Salt REST API is configured to use HTTPS via Tornado with a certificate
and key specified in the configuration. Make sure to use a valid certificate
for production deployments.

### Restricted API Clients

The API configuration limits allowed netapi client types to:

- `local` -- Execute functions on minions
- `local_async` -- Execute functions asynchronously
- `runner` -- Execute runner functions on the master

This prevents use of other client types such as `wheel` (which could modify
keys or configuration).

### SELinux Policy

Salt does not ship an official SELinux policy. The Ansible playbook deploys custom
Type Enforcement modules (`salt_master_selinux.te`, `salt_minion_selinux.te`) that
grant the minimum permissions needed for Salt to operate under SELinux Enforcing
mode. The policy modules allow:

- ZeroMQ port binding and IPC socket management
- Execution of Salt's bundled Python from `/opt/saltstack/salt/`
- Salt CLI (`unconfined_t`) to connect to master/minion IPC sockets

If new Salt modules or state operations trigger additional AVC denials, extend the
policy using `audit2allow`:

```bash
sudo ausearch -m AVC -ts today | grep salt | audit2allow -M salt_custom
sudo semodule -i salt_custom.pp
```
