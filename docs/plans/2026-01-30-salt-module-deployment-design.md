# Salt Module Deployment via GitFS + Ansible

## 1. Overview & Architecture

**Goal**: Deploy Salt custom modules and states from this git repo to an on-premise Salt Master using Salt's GitFS backend, configured entirely via Ansible. The Rails app runs on a remote/cloud host and communicates with Salt Master over `salt-api` (HTTPS).

**Deployment topology**:

```
[Cloud/Remote]              [On-Premise HPC Cluster]
┌─────────┐   HTTPS API    ┌──────────────┐    ZeroMQ     ┌──────────┐
│ Rails    │───────────────>│ Salt Master  │──────────────>│ Minion 1 │
│ App      │<───────────────│ + salt-api   │              ├──────────┤
└─────────┘   webhook/SSE  │ + GitFS      │              │ Minion 2 │
                            └──────┬───────┘              ├──────────┤
                                   │ HTTPS poll           │ Minion N │
                            ┌──────▼───────┐              └──────────┘
                            │  Git Repo    │
                            │ (GitHub/etc) │
                            └──────────────┘
```

**Module distribution flow**:
1. Developer pushes code to git repo
2. Salt Master's GitFS polls repo (configurable interval, default 60s)
3. On next `state.apply` or explicit `saltutil.sync_modules`, modules sync to minions
4. Rails triggers operations via `salt-api` -- modules are already on the minions

## 2. Directory Restructure

The `salt/` directory will be reorganized to match Salt's `file_roots` conventions so GitFS works with a single `gitfs_root: salt` setting.

**Current layout**:
```
salt/
├── master.d/api.conf
├── modules/
│   ├── inventory.py
│   ├── benchmark.py
│   └── tests/
│       ├── __init__.py
│       ├── test_inventory.py
│       └── test_benchmark.py
├── states/benchmark/
│   ├── hpcg/{init,prepare,execute,collect}.sls
│   └── mlc/{init,prepare,execute,collect}.sls
└── reactor/
    ├── job_return.sls
    └── presence_change.sls
```

**New layout** (Salt conventions):
```
salt/
├── _modules/              # Custom execution modules (auto-synced to minions)
│   ├── inventory.py
│   └── benchmark.py
├── _tests/                # Module tests (not synced, dev-only)
│   ├── __init__.py
│   ├── test_inventory.py
│   └── test_benchmark.py
├── benchmark/             # State files (top-level = state tree)
│   ├── hpcg/
│   │   ├── init.sls
│   │   ├── prepare.sls
│   │   ├── execute.sls
│   │   └── collect.sls
│   └── mlc/
│       ├── init.sls
│       ├── prepare.sls
│       ├── execute.sls
│       └── collect.sls
├── reactor/               # Reactor files (referenced by absolute path in master config)
│   ├── job_return.sls
│   └── presence_change.sls
└── master.d/              # Master config snippets (deployed by Ansible, not via GitFS)
    └── api.conf
```

**Key changes**:
- `modules/` renamed to `_modules/` (Salt's convention for auto-synced execution modules)
- `states/benchmark/` flattened to `benchmark/` (states live at the root of `file_roots`)
- `modules/tests/` moved to `_tests/` (underscore prefix means Salt ignores it during sync)
- `master.d/` and `reactor/` are deployed by Ansible separately (not served via GitFS file_roots)

**Why this matters**: When GitFS serves the `salt/` directory as the file root, Salt expects `_modules/` at the root for custom execution modules and state directories (like `benchmark/`) at the root for state files. The previous layout required explicit `module_dirs` and `file_roots` overrides in the master config. With the new layout, a single `gitfs_root: salt` setting handles everything.

## 3. Ansible Playbook Structure

```
ansible/
├── inventory/
│   └── hosts.yml
├── group_vars/
│   ├── salt_master.yml              # Non-secret variables
│   └── salt_master/
│       └── vault.yml                # Secrets (Ansible Vault encrypted)
├── roles/
│   ├── salt_master/
│   │   ├── tasks/
│   │   │   ├── main.yml       # Include sub-tasks in order
│   │   │   ├── install.yml    # Install salt-master, salt-api, pygit2
│   │   │   ├── configure.yml  # Drop master config files
│   │   │   ├── gitfs.yml      # GitFS-specific config
│   │   │   ├── auth.yml       # PAM user + external_auth config
│   │   │   ├── reactor.yml    # Deploy reactor SLS files
│   │   │   └── service.yml    # Enable & restart services
│   │   ├── templates/
│   │   │   ├── gitfs.conf.j2
│   │   │   ├── api.conf.j2
│   │   │   ├── auth.conf.j2
│   │   │   ├── reactor.conf.j2
│   │   │   ├── job_return.sls.j2
│   │   │   └── presence_change.sls.j2
│   │   └── defaults/
│   │       └── main.yml
│   └── salt_minion/
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── install.yml
│       │   ├── configure.yml
│       │   └── service.yml
│       ├── templates/
│       │   └── minion.conf.j2
│       └── defaults/
│           └── main.yml
└── playbooks/
    └── salt.yml
```

**Key design decisions**:
- Reactor SLS files are Jinja templates because they contain the Rails webhook URL (varies per deployment)
- `master.d/` config is split into multiple files for clarity: `gitfs.conf`, `api.conf`, `auth.conf`, `reactor.conf`
- Secrets (GitFS token, API password) are stored in `group_vars/salt_master/vault.yml` encrypted with Ansible Vault; non-secret variables are in `group_vars/salt_master.yml`
- Reactor files deploy to `/srv/salt/reactor/` (outside GitFS file_roots, deployment-specific)
- The existing `ansible/roles/perfspect/` role is unaffected; the new roles sit alongside it

## 4. Salt Master Configuration Details

Each config snippet is templated by Ansible and dropped into `/etc/salt/master.d/` on the Salt Master.

### gitfs.conf.j2

```yaml
fileserver_backend:
  - gitfs
  - roots

gitfs_remotes:
  - https://github.com/your-org/diagnostic-tools.git:
    - root: salt
    - base: {{ salt_gitfs_branch | default('develop') }}
    - user: {{ salt_gitfs_user }}
    - password: {{ salt_gitfs_token }}

gitfs_provider: pygit2
gitfs_update_interval: 60
```

- `root: salt` tells GitFS to treat the `salt/` subdirectory as the file root.
- `base` maps a git branch to Salt's `base` environment. Defaults to `develop`.
- `roots` is kept as a fallback fileserver backend for any local overrides.
- `pygit2` is the recommended GitFS provider (supports HTTPS auth natively).

### api.conf.j2

```yaml
rest_cherrypy:
  port: {{ salt_api_port | default(8000) }}
  ssl_crt: {{ salt_api_ssl_cert }}
  ssl_key: {{ salt_api_ssl_key }}

netapi_enable_clients:
  - local
  - local_async
  - runner

presence_events: True
file_recv: True
```

Note: `netapi_enable_clients` requires Salt 3006.1+. On older versions, this key is silently ignored and all clients are enabled by default.

Security note: `file_recv: True` allows minions to push files to the master via `cp.push`. This is required for benchmark artifact collection. Mitigations: only authenticated minions (accepted keys) can push files, and pushed files are stored under `/var/cache/salt/master/minions/<minion-id>/files/`.

SSL Certificate Provisioning: The `salt_api_ssl_cert` and `salt_api_ssl_key` paths must point to valid certificates on the Salt Master. These can be provisioned by adding a certificate generation task to the `salt_master/tasks/install.yml` (e.g., self-signed via `openssl`), or managed externally. The Rails `SaltSetting` model supports `ca_cert_path` and `verify_ssl` options to trust the Salt Master's certificate.

### auth.conf.j2

```yaml
external_auth:
  pam:
    {{ salt_api_user }}:
      - '*':
        - grains.items
        - inventory.*
        - benchmark.run_hpcg
        - benchmark.run_mlc
        - benchmark.cancel
        - test.ping
        - state.apply
        - cmd.run              # lscpu fallback in SaltCollectService
        - cp.push
        - cp.push_dir
        - saltutil.sync_modules
      - '@runner':
        - manage.status
```

Changes from the current `api.conf`:
- `inventory.*` wildcard replaces the explicit list (`inventory.collect_dmi`, `inventory.collect_numa`, `inventory.collect_network_v2`). This avoids updating the auth config every time a new inventory function is added.
- `saltutil.sync_modules` is added so Rails can trigger module syncs after code deploys.
- Auth config is separated from API config for clarity.

### reactor.conf.j2

```yaml
reactor:
  - 'salt/job/ret/*':
    - /srv/salt/reactor/job_return.sls
  - 'salt/presence/change':
    - /srv/salt/reactor/presence_change.sls
```

Reactor SLS files are deployed by Ansible to `/srv/salt/reactor/` (not via GitFS) because they contain deployment-specific values like the Rails webhook URL. The reactor config references them by absolute path.

### job_return.sls.j2

```yaml
{% raw %}
{% set fun = data.get('fun', '') %}
{% set fun_args = data.get('fun_args', []) %}
{% set is_benchmark = 'benchmark' in fun %}
{% if not is_benchmark %}
  {% for arg in fun_args %}
    {% if arg is mapping and arg.get('mods', '')|string is match('benchmark.*') %}
      {% set is_benchmark = true %}
    {% endif %}
  {% endfor %}
{% endif %}
{% if is_benchmark %}
{% endraw %}
post_benchmark_result:
  local.cmd.run:
    - tgt: {{ '{{ data["id"] }}' }}
    - arg:
      - >-
        curl -s -X POST
        -H "Content-Type: application/json"
        -d '{{ '{{ data | tojson }}' }}'
        {{ rails_webhook_url }}
{% raw %}
{% endif %}
{% endraw %}
```

### presence_change.sls.j2

```yaml
{% raw %}
{% if data.get('new', []) or data.get('lost', []) %}
{% endraw %}
post_presence_change:
  local.cmd.run:
    - tgt: {{ '{{ salt["config.get"]("master") }}' }}
    - arg:
      - >-
        curl -s -X POST
        -H "Content-Type: application/json"
        -d '{{ '{{ {"tag": tag, "new": data.get("new", []), "lost": data.get("lost", [])} | tojson }}' }}'
        {{ rails_webhook_url }}
{% raw %}
{% endif %}
{% endraw %}
```

Note: The `{% raw %}...{% endraw %}` blocks prevent Ansible from interpreting Salt's Jinja expressions. The `{{ rails_webhook_url }}` variable (outside raw blocks) is substituted by Ansible at deploy time. The `rails_api_token` variable used in the existing reactor files should also be added as an Ansible variable if webhook authentication is required.

## 5. Ansible Task Details

### salt_master/tasks/install.yml

- Add SaltStack official APT repository (Salt 3006 LTS)
- Install `salt-master`, `salt-api`, `python3-pygit2`
- Create PAM user for Rails API access:
  ```yaml
  - name: Create salt API user
    ansible.builtin.user:
      name: "{{ salt_api_user }}"
      password: "{{ salt_api_password | password_hash('sha512') }}"
      shell: /usr/sbin/nologin
      system: yes
  ```

### salt_master/tasks/configure.yml

- Template `api.conf.j2` to `/etc/salt/master.d/api.conf`
- Template `auth.conf.j2` to `/etc/salt/master.d/auth.conf`
- Both notify `restart salt-master` handler

### salt_master/tasks/gitfs.yml

- Template `gitfs.conf.j2` to `/etc/salt/master.d/gitfs.conf`
- Notify `restart salt-master` handler (for config changes)
- Notify `sync salt modules` handler (separate from service restart)
- Post-restart handler runs `salt-run fileserver.update` to trigger initial GitFS fetch
- Post-sync handler runs `salt '*' saltutil.sync_modules` to push modules to minions

### salt_master/tasks/reactor.yml

- Create `/srv/salt/reactor/` directory
- Template `job_return.sls.j2` to `/srv/salt/reactor/job_return.sls`
- Template `presence_change.sls.j2` to `/srv/salt/reactor/presence_change.sls`
- Template `reactor.conf.j2` to `/etc/salt/master.d/reactor.conf`
- Notify `restart salt-master` handler

### salt_master/tasks/service.yml

- Enable and start `salt-master` and `salt-api`
- Handler definition:
  ```yaml
  handlers:
    - name: restart salt-master
      ansible.builtin.systemd:
        name: salt-master
        state: restarted
        daemon_reload: yes

    - name: restart salt-api
      ansible.builtin.systemd:
        name: salt-api
        state: restarted
      listen: "restart salt-master"

    - name: Sync custom modules to all minions
      ansible.builtin.command: salt '*' saltutil.sync_modules
      listen: "restart salt-master"
      failed_when: false    # No-op on fresh clusters with no accepted minions
      changed_when: false
  ```

  Note: The `restart salt-api` handler uses `listen: "restart salt-master"` to chain with the master restart. Changes to `api.conf` and `auth.conf` should notify the `restart salt-master` handler, which automatically triggers `restart salt-api` via the listener.

### salt_minion/tasks/configure.yml

- Template `minion.conf.j2` to `/etc/salt/minion.d/master.conf`
- Sets `master: {{ salt_master_address }}`
- Enable and start `salt-minion`

### Ansible Vault variables

Variables are split into plain and encrypted files:

`group_vars/salt_master.yml` (plain, not encrypted):
```yaml
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# References to vault-encrypted secrets
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

`group_vars/salt_master/vault.yml` (Ansible Vault encrypted):
```yaml
vault_salt_gitfs_token: "ghp_xxxxxxxxxxxxxxxxxxxx"
vault_salt_api_password: "your-secure-password"
```

### Main playbook (playbooks/salt.yml)

```yaml
---
- name: Configure Salt Master
  hosts: salt_master
  become: yes
  roles:
    - salt_master

- name: Configure Salt Minions
  hosts: salt_minions
  become: yes
  roles:
    - salt_minion
```

## 6. Module Sync to Minions

**Automatic sync triggers** (built into Salt):

| Trigger | When | Command |
|---------|------|---------|
| `state.apply` | Any state run on a minion | Modules auto-synced before state execution |
| `state.highstate` | Full state application | Same as above |
| `saltutil.sync_modules` | Explicit sync | `salt '*' saltutil.sync_modules` |
| Minion restart | When `startup_states: highstate` is set | Syncs on boot (optional) |

**Where modules land on minions**: `/var/cache/salt/minion/extmods/modules/`

**GitFS update cycle**:
1. Developer pushes to git (e.g., updates `salt/_modules/inventory.py`)
2. Salt Master polls git every 60 seconds (`gitfs_update_interval: 60`)
3. Master detects changed files, updates its local cache
4. Next `state.apply` or `saltutil.sync_modules` on a minion picks up the new module
5. No Ansible re-run required for module code changes -- only for config changes

**Verification commands**:
```bash
# Check modules are available on a minion
salt 'compute-001' sys.list_modules | grep -E 'inventory|benchmark'

# Force sync and verify
salt '*' saltutil.sync_modules
salt 'compute-001' inventory.collect_cpu

# Check GitFS is serving files
salt-run fileserver.file_list | grep _modules

# Force GitFS update (don't wait for interval)
salt-run fileserver.update
```

**Post-deploy Ansible handler**:
```yaml
- name: Sync custom modules to all minions
  ansible.builtin.command: salt '*' saltutil.sync_modules
  listen: "sync salt modules"
  failed_when: false    # No-op on fresh clusters with no accepted minions
  changed_when: false
```

This handler fires after any master config change triggers a restart. It ensures minions get the latest modules immediately rather than waiting for the next `state.apply`.

### Failure Modes

| Scenario | Behavior | Resolution |
|----------|----------|------------|
| GitFS fetch fails (network/auth) | Salt continues serving cached files from last successful fetch. Errors logged to `/var/log/salt/master`. | Fix network/credentials, then run `salt-run fileserver.update` |
| Minion offline during sync | Minion misses the sync. Modules sync automatically on next `state.apply` or minion restart. | No action needed -- Salt handles this automatically |
| Git auth token expires | GitFS fetch fails silently, stale cache used | Rotate token in Ansible Vault, re-run playbook |
| Salt Master restart during GitFS update | Update aborted, retried on next interval | No action needed |

## 7. What Ansible Manages vs. What GitFS Manages

Clear separation of responsibilities:

| Component | Managed by | Location on Master | Reason |
|-----------|------------|-------------------|--------|
| `_modules/*.py` | GitFS | auto-cached from git | Code changes frequently, no secrets |
| `benchmark/**/*.sls` | GitFS | auto-cached from git | State files, no secrets |
| `gitfs.conf` | Ansible | `/etc/salt/master.d/` | Contains git credentials |
| `api.conf` | Ansible | `/etc/salt/master.d/` | Contains SSL paths, port config |
| `auth.conf` | Ansible | `/etc/salt/master.d/` | Contains PAM user permissions |
| `reactor.conf` | Ansible | `/etc/salt/master.d/` | References absolute paths |
| `reactor/*.sls` | Ansible | `/srv/salt/reactor/` | Contains Rails webhook URL |
| `minion.conf` | Ansible | `/etc/salt/minion.d/` | Contains master address |

The `salt/master.d/api.conf` and `salt/reactor/*.sls` files in the git repo serve as reference/documentation but are not used directly. Ansible templates produce the actual deployed files with environment-specific values substituted.

## 8. Implementation Checklist

1. Restructure `salt/` directory: rename `modules/` to `_modules/`, move `states/benchmark/` to `benchmark/`, move `modules/tests/` to `_tests/`
2. Update state `include` paths if needed. The paths like `benchmark.mlc.prepare` remain unchanged because the directory name `benchmark/` is preserved -- only its parent path changes from `states/benchmark/` to `benchmark/`.
3. Remove `module_dirs` and `file_roots` from `salt/master.d/api.conf` (GitFS handles both)
4. Create Ansible `salt_master` role with all task files and templates
5. Create Ansible `salt_minion` role
6. Create `playbooks/salt.yml` main playbook
7. Set up Ansible Vault for sensitive variables (`salt_gitfs_token`, `salt_api_password`)
8. Test GitFS fetch on Salt Master (`salt-run fileserver.file_list`)
9. Test module sync to minions (`salt '*' saltutil.sync_modules`)
10. Verify Rails can trigger inventory collection and benchmarks via salt-api
