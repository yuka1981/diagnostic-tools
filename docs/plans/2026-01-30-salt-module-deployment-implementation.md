# Salt Module Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the Salt directory to match Salt conventions and create Ansible roles for deploying Salt Master and Minion infrastructure with GitFS-based module distribution.

**Architecture:** Salt custom modules move to `_modules/` for auto-sync via GitFS. Ansible roles handle Salt Master/Minion installation, configuration (gitfs, api, auth, reactor), and service management. Reactor SLS files become Ansible Jinja templates with `{% raw %}` blocks for Salt/Ansible delimiter separation.

**Tech Stack:** Salt 3006 LTS, Ansible 2.14+, pygit2, CherryPy (salt-api)

**Design doc:** `docs/plans/2026-01-30-salt-module-deployment-design.md`

---

## Task 1: Restructure salt/ directory -- move modules to _modules/

**Files:**
- Move: `salt/modules/inventory.py` -> `salt/_modules/inventory.py`
- Move: `salt/modules/benchmark.py` -> `salt/_modules/benchmark.py`

### Step 1: Run existing Python tests to establish baseline

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark/salt && python -m pytest modules/tests/ -v
```

**Expected:** All tests pass. This gives us a known-good baseline before restructuring.

### Step 2: Use git mv to rename modules to _modules

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
mkdir -p salt/_modules
git mv salt/modules/inventory.py salt/_modules/inventory.py
git mv salt/modules/benchmark.py salt/_modules/benchmark.py
```

**Expected:** Git tracks the rename. The `salt/_modules/` directory now contains `inventory.py` and `benchmark.py`.

### Step 3: Run git status to verify

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git status
```

**Expected:** Output shows `renamed: salt/modules/inventory.py -> salt/_modules/inventory.py` and `renamed: salt/modules/benchmark.py -> salt/_modules/benchmark.py`. The `salt/modules/tests/` directory still exists with test files.

### Step 4: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add salt/_modules/inventory.py salt/_modules/benchmark.py salt/modules/inventory.py salt/modules/benchmark.py
git commit -m "$(cat <<'EOF'
refactor: rename salt/modules/ to salt/_modules/ for Salt convention

Salt expects custom execution modules in _modules/ at the file_roots
level for auto-sync via GitFS. This rename eliminates the need for
explicit module_dirs configuration in the master config.
EOF
)"
```

**Expected:** Commit succeeds with the two renames tracked.

---

## Task 2: Restructure salt/ directory -- move tests to _tests/

**Files:**
- Move: `salt/modules/tests/__init__.py` -> `salt/_tests/__init__.py`
- Move: `salt/modules/tests/test_inventory.py` -> `salt/_tests/test_inventory.py`
- Move: `salt/modules/tests/test_benchmark.py` -> `salt/_tests/test_benchmark.py`
- Modify: `salt/_tests/test_inventory.py` (update sys.path.insert)
- Modify: `salt/_tests/test_benchmark.py` (update sys.path.insert)
- Delete: `salt/modules/tests/` directory (empty after moves)
- Delete: `salt/modules/` directory (empty after moves)

### Step 1: Use git mv to move test files

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
mkdir -p salt/_tests
git mv salt/modules/tests/__init__.py salt/_tests/__init__.py
git mv salt/modules/tests/test_inventory.py salt/_tests/test_inventory.py
git mv salt/modules/tests/test_benchmark.py salt/_tests/test_benchmark.py
```

**Expected:** All three test files are moved to `salt/_tests/`.

### Step 2: Remove empty directories

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
rmdir salt/modules/tests
rmdir salt/modules
```

**Expected:** Both directories removed (they should be empty now since modules were moved in Task 1 and tests in Step 1).

### Step 3: Update sys.path.insert in test_inventory.py

In `salt/_tests/test_inventory.py`, change line 10:

**Old:**
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
```

**New:**
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '_modules'))
```

**Reason:** Tests moved from `salt/modules/tests/` to `salt/_tests/`. The parent `..` is now `salt/`, not `salt/modules/`. The modules are in `salt/_modules/`, so the path needs `../_modules`.

### Step 4: Update sys.path.insert in test_benchmark.py

In `salt/_tests/test_benchmark.py`, change line 5:

**Old:**
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
```

**New:**
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '_modules'))
```

**Reason:** Same as Step 3 -- the relative path from `_tests/` to `_modules/` requires going up one level to `salt/` then down into `_modules/`.

### Step 5: Run tests from salt/ directory

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark/salt && python -m pytest _tests/ -v
```

**Expected:** All tests pass. The `sys.path.insert` updates correctly resolve `import inventory` and `import benchmark` to `salt/_modules/inventory.py` and `salt/_modules/benchmark.py`.

### Step 6: Verify all tests pass

Confirm the output from Step 5 shows all tests passing with 0 failures. If any test fails, debug the import path issue before proceeding.

### Step 7: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add salt/_tests/ salt/modules/
git commit -m "$(cat <<'EOF'
refactor: move salt tests to _tests/ and update import paths

Move test files from salt/modules/tests/ to salt/_tests/ following Salt
convention. Update sys.path.insert to point to ../_modules instead of ..
since the tests directory is now a sibling of _modules/ under salt/.
EOF
)"
```

**Expected:** Commit succeeds. The `salt/modules/` directory no longer exists.

---

## Task 3: Restructure salt/ directory -- flatten states to root

**Files:**
- Move: `salt/states/benchmark/mlc/init.sls` -> `salt/benchmark/mlc/init.sls`
- Move: `salt/states/benchmark/mlc/prepare.sls` -> `salt/benchmark/mlc/prepare.sls`
- Move: `salt/states/benchmark/mlc/execute.sls` -> `salt/benchmark/mlc/execute.sls`
- Move: `salt/states/benchmark/mlc/collect.sls` -> `salt/benchmark/mlc/collect.sls`
- Move: `salt/states/benchmark/hpcg/init.sls` -> `salt/benchmark/hpcg/init.sls`
- Move: `salt/states/benchmark/hpcg/prepare.sls` -> `salt/benchmark/hpcg/prepare.sls`
- Move: `salt/states/benchmark/hpcg/execute.sls` -> `salt/benchmark/hpcg/execute.sls`
- Move: `salt/states/benchmark/hpcg/collect.sls` -> `salt/benchmark/hpcg/collect.sls`
- Delete: `salt/states/` directory (empty after moves)

### Step 1: Use git mv to move benchmark states to salt root

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git mv salt/states/benchmark salt/benchmark
```

**Expected:** The entire `salt/states/benchmark/` directory tree is moved to `salt/benchmark/`, preserving the `mlc/` and `hpcg/` subdirectories and all SLS files within them.

### Step 2: Remove empty states directory

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
rmdir salt/states
```

**Expected:** `salt/states/` is removed. It should be empty since `benchmark/` was the only subdirectory.

### Step 3: Verify include paths in init.sls files still work

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
grep -n 'include' salt/benchmark/mlc/init.sls
grep -n 'include' salt/benchmark/hpcg/init.sls
```

**Expected:** Both files still reference:
- `benchmark.mlc.prepare`, `benchmark.mlc.execute`, `benchmark.mlc.collect`
- `benchmark.hpcg.prepare`, `benchmark.hpcg.execute`, `benchmark.hpcg.collect`

These include paths are unchanged because Salt resolves them relative to `file_roots` (which will be `salt/` via GitFS `root: salt`). The `benchmark/` directory name is preserved, only the intermediate `states/` directory is removed.

### Step 4: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add salt/benchmark/ salt/states/
git commit -m "$(cat <<'EOF'
refactor: flatten salt/states/benchmark/ to salt/benchmark/

State files now live at the root of the salt/ directory, matching
Salt's file_roots convention. GitFS with root: salt will serve
benchmark/ directly as a state tree. Include paths like
benchmark.mlc.prepare remain unchanged.
EOF
)"
```

**Expected:** Commit succeeds. The `salt/states/` directory no longer exists.

---

## Task 4: Update salt/master.d/api.conf -- remove module_dirs and file_roots

**Files:**
- Modify: `salt/master.d/api.conf`

### Step 1: Read current api.conf

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
cat salt/master.d/api.conf
```

**Expected:** The file contains `rest_cherrypy`, `netapi_enable_clients`, `presence_events`, `file_recv`, `external_auth`, `module_dirs`, `file_roots`, and `reactor` sections.

### Step 2: Rewrite api.conf

Replace the entire contents of `salt/master.d/api.conf` with:

```yaml
# Salt API Configuration (reference only)
# NOTE: This file is a reference copy. The actual deployed config is
# generated by Ansible templates. See ansible/roles/salt_master/templates/
#
# NOTE: module_dirs and file_roots are managed by GitFS. See gitfs.conf.j2.
# NOTE: reactor config is in reactor.conf.j2.
# NOTE: external_auth config is in auth.conf.j2.

rest_cherrypy:
  port: 8000
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key

# Restrict API clients (requires Salt 3006.1+)
netapi_enable_clients:
  - local
  - local_async
  - runner

# Enable presence detection events on the event bus
presence_events: True

# Allow minions to push files to the master via cp.push
# Security: only authenticated minions can push, stored under
# /var/cache/salt/master/minions/<id>/files/
file_recv: True
```

**Removed sections:**
- `external_auth` -- moved to separate `auth.conf` (Ansible template)
- `module_dirs` -- managed by GitFS `_modules/` convention
- `file_roots` -- managed by GitFS `root: salt` setting
- `reactor` -- moved to separate `reactor.conf` (Ansible template)

### Step 3: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add salt/master.d/api.conf
git commit -m "$(cat <<'EOF'
refactor: remove module_dirs/file_roots/reactor from api.conf

These sections are now managed by Ansible templates:
- module_dirs: handled by GitFS _modules/ convention
- file_roots: handled by GitFS root: salt setting
- reactor: moved to reactor.conf.j2
- external_auth: moved to auth.conf.j2

The file is retained as a reference copy. Ansible templates
generate the actual deployed configuration.
EOF
)"
```

**Expected:** Commit succeeds. The api.conf is now a slim reference file.

---

## Task 5: Create Ansible salt_master role -- defaults, main tasks, and handlers

**Files:**
- Create: `ansible/roles/salt_master/defaults/main.yml`
- Create: `ansible/roles/salt_master/tasks/main.yml`
- Create: `ansible/roles/salt_master/templates/.gitkeep`
- Create: `ansible/roles/salt_master/handlers/main.yml`

### Step 1: Create directory structure

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
mkdir -p ansible/roles/salt_master/defaults
mkdir -p ansible/roles/salt_master/tasks
mkdir -p ansible/roles/salt_master/templates
mkdir -p ansible/roles/salt_master/handlers
touch ansible/roles/salt_master/templates/.gitkeep
```

**Expected:** All directories created.

### Step 2: Write defaults/main.yml

Create `ansible/roles/salt_master/defaults/main.yml` with:

```yaml
---
# Salt package version (3006 = LTS release)
salt_version: "3006"

# GitFS configuration
salt_gitfs_branch: "develop"
salt_gitfs_update_interval: 60
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"

# Salt API
salt_api_port: 8000
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# Salt API user (PAM authentication)
salt_api_user: "rails_salt_user"

# Reactor webhook URL
rails_webhook_url: "http://localhost:3000/api/v1/salt/events"
```

### Step 3: Write tasks/main.yml

Create `ansible/roles/salt_master/tasks/main.yml` with:

```yaml
---
- name: Install Salt Master packages
  ansible.builtin.import_tasks: install.yml

- name: Configure Salt Master
  ansible.builtin.import_tasks: configure.yml

- name: Configure GitFS
  ansible.builtin.import_tasks: gitfs.yml

- name: Configure authentication
  ansible.builtin.import_tasks: auth.yml

- name: Deploy reactor files
  ansible.builtin.import_tasks: reactor.yml

- name: Manage Salt services
  ansible.builtin.import_tasks: service.yml
```

### Step 4: Write handlers/main.yml

Create `ansible/roles/salt_master/handlers/main.yml` with:

```yaml
---
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

- name: sync salt modules
  ansible.builtin.command: salt '*' saltutil.sync_modules
  listen: "restart salt-master"
  failed_when: false
  changed_when: false
```

### Step 5: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/defaults/main.yml \
        ansible/roles/salt_master/tasks/main.yml \
        ansible/roles/salt_master/templates/.gitkeep \
        ansible/roles/salt_master/handlers/main.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master Ansible role skeleton with defaults and handlers

Create the salt_master role directory structure with:
- defaults/main.yml: default variables for salt version, gitfs, api, reactor
- tasks/main.yml: imports sub-tasks in order (install, configure, gitfs, auth, reactor, service)
- handlers/main.yml: restart salt-master/api and sync modules on config changes
EOF
)"
```

**Expected:** Commit succeeds with the role skeleton files.

---

## Task 6: Create salt_master role -- install.yml task

**Files:**
- Create: `ansible/roles/salt_master/tasks/install.yml`

### Step 1: Write install.yml

Create `ansible/roles/salt_master/tasks/install.yml` with:

```yaml
---
- name: Add SaltStack GPG key
  ansible.builtin.apt_key:
    url: "https://repo.saltproject.io/salt/py3/{{ ansible_distribution | lower }}/{{ ansible_distribution_version }}/{{ ansible_architecture }}/SALT-PROJECT-GPG-PUBKEY-2023.gpg"
    state: present

- name: Add SaltStack APT repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture }}] https://repo.saltproject.io/salt/py3/{{ ansible_distribution | lower }}/{{ ansible_distribution_version }}/{{ ansible_architecture }}/{{ salt_version }} {{ ansible_distribution_release }} main"
    state: present
    filename: saltstack

- name: Install Salt Master and API packages
  ansible.builtin.apt:
    name:
      - salt-master
      - salt-api
      - python3-pygit2
    state: present
    update_cache: yes

- name: Create Salt API PAM user
  ansible.builtin.user:
    name: "{{ salt_api_user }}"
    password: "{{ salt_api_password | password_hash('sha512') }}"
    shell: /usr/sbin/nologin
    system: yes
    create_home: no
```

### Step 2: Validate YAML syntax

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/salt_master/tasks/install.yml')); print('YAML valid')"
```

**Expected:** Output: `YAML valid`

### Step 3: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/tasks/install.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master install task with APT repo and PAM user

Install Salt Master 3006 LTS packages from the official SaltStack
repository: salt-master, salt-api, and python3-pygit2 (for GitFS).
Creates a PAM system user for Rails API authentication.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 7: Create salt_master role -- configure.yml and api.conf.j2

**Files:**
- Create: `ansible/roles/salt_master/templates/api.conf.j2`
- Create: `ansible/roles/salt_master/tasks/configure.yml`

### Step 1: Write api.conf.j2 template

Create `ansible/roles/salt_master/templates/api.conf.j2` with:

```yaml
# Salt API configuration (managed by Ansible)
rest_cherrypy:
  port: {{ salt_api_port | default(8000) }}
  ssl_crt: {{ salt_api_ssl_cert }}
  ssl_key: {{ salt_api_ssl_key }}

# Restrict API clients (requires Salt 3006.1+)
netapi_enable_clients:
  - local
  - local_async
  - runner

# Enable presence events for minion tracking
presence_events: True

# Allow minions to push files (benchmark artifacts)
# Security: only authenticated minions can push, stored under /var/cache/salt/master/minions/<id>/files/
file_recv: True
```

### Step 2: Write configure.yml task

Create `ansible/roles/salt_master/tasks/configure.yml` with:

```yaml
---
- name: Deploy Salt API configuration
  ansible.builtin.template:
    src: api.conf.j2
    dest: /etc/salt/master.d/api.conf
    owner: root
    group: root
    mode: '0640'
  notify: restart salt-master
```

### Step 3: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/templates/api.conf.j2 \
        ansible/roles/salt_master/tasks/configure.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master configure task with api.conf template

Template deploys api.conf to /etc/salt/master.d/ with CherryPy
settings, netapi client restrictions, presence events, and file_recv.
Notifies restart salt-master handler on changes.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 8: Create salt_master role -- gitfs.yml and gitfs.conf.j2

**Files:**
- Create: `ansible/roles/salt_master/templates/gitfs.conf.j2`
- Create: `ansible/roles/salt_master/tasks/gitfs.yml`

### Step 1: Write gitfs.conf.j2 template

Create `ansible/roles/salt_master/templates/gitfs.conf.j2` with:

```yaml
# GitFS fileserver backend (managed by Ansible)
fileserver_backend:
  - gitfs
  - roots

gitfs_remotes:
  - {{ salt_gitfs_repo }}:
    - root: salt
    - base: {{ salt_gitfs_branch | default('develop') }}
    - user: {{ salt_gitfs_user }}
    - password: {{ salt_gitfs_token }}

gitfs_provider: pygit2
gitfs_update_interval: {{ salt_gitfs_update_interval | default(60) }}
```

### Step 2: Write gitfs.yml task

Create `ansible/roles/salt_master/tasks/gitfs.yml` with:

```yaml
---
- name: Deploy GitFS configuration
  ansible.builtin.template:
    src: gitfs.conf.j2
    dest: /etc/salt/master.d/gitfs.conf
    owner: root
    group: root
    mode: '0640'
  notify: restart salt-master
```

### Step 3: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/templates/gitfs.conf.j2 \
        ansible/roles/salt_master/tasks/gitfs.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master GitFS task and template

Configure Salt Master to use GitFS with pygit2 provider for serving
custom modules (_modules/) and state files (benchmark/) from the
diagnostic-tools git repository. Uses root: salt to scope the
file_roots to the salt/ directory in the repo.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 9: Create salt_master role -- auth.yml and auth.conf.j2

**Files:**
- Create: `ansible/roles/salt_master/templates/auth.conf.j2`
- Create: `ansible/roles/salt_master/tasks/auth.yml`

### Step 1: Write auth.conf.j2 template

Create `ansible/roles/salt_master/templates/auth.conf.j2` with:

```yaml
# External authentication for Salt API (managed by Ansible)
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
        - cmd.run
        - cp.push
        - cp.push_dir
        - saltutil.sync_modules
      - '@runner':
        - manage.status
```

### Step 2: Write auth.yml task

Create `ansible/roles/salt_master/tasks/auth.yml` with:

```yaml
---
- name: Deploy Salt authentication configuration
  ansible.builtin.template:
    src: auth.conf.j2
    dest: /etc/salt/master.d/auth.conf
    owner: root
    group: root
    mode: '0640'
  notify: restart salt-master
```

### Step 3: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/templates/auth.conf.j2 \
        ansible/roles/salt_master/tasks/auth.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master auth task and template

Configure PAM external_auth for the Rails API user with permissions
for inventory.*, benchmark operations, state.apply, cmd.run, cp.push,
saltutil.sync_modules, and manage.status runner. Uses inventory.*
wildcard instead of explicit function names to avoid config updates
when new inventory functions are added.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 10: Create salt_master role -- reactor.yml with reactor templates

**Files:**
- Create: `ansible/roles/salt_master/templates/reactor.conf.j2`
- Create: `ansible/roles/salt_master/templates/job_return.sls.j2`
- Create: `ansible/roles/salt_master/templates/presence_change.sls.j2`
- Create: `ansible/roles/salt_master/tasks/reactor.yml`

### Step 1: Write reactor.conf.j2 template

Create `ansible/roles/salt_master/templates/reactor.conf.j2` with:

```yaml
# Reactor configuration (managed by Ansible)
reactor:
  - 'salt/job/ret/*':
    - /srv/salt/reactor/job_return.sls
  - 'salt/presence/change':
    - /srv/salt/reactor/presence_change.sls
```

### Step 2: Write job_return.sls.j2 template

This is the trickiest template because it mixes Salt Jinja and Ansible Jinja. Salt reactor SLS files use Jinja2 syntax (`{% ... %}`, `{{ ... }}`), which conflicts with Ansible's Jinja2 template rendering. The solution is to wrap Salt Jinja expressions in `{% raw %}...{% endraw %}` blocks so Ansible passes them through literally, while leaving Ansible variables like `{{ rails_webhook_url }}` outside the raw blocks for Ansible to substitute at deploy time.

The current reactor at `salt/reactor/job_return.sls` uses `salt['config.get']('rails_webhook_url', ...)` and `salt['config.get']('rails_api_token', ...)` to read the webhook URL and API token from Salt's master config. In the new design, these values are baked into the reactor file by Ansible at deploy time, eliminating the runtime `config.get` lookup.

Create `ansible/roles/salt_master/templates/job_return.sls.j2` with:

```
# Reactor: forward benchmark job returns to Rails webhook (managed by Ansible)
{% raw %}
{% set fun = data.get('fun', '') %}
{% set fun_args = data.get('fun_args', []) %}
{% set fun_args_str = fun_args | join(' ') %}
{% set is_benchmark = 'benchmark' in fun or (fun == 'state.apply' and 'benchmark' in fun_args_str) %}
{% if is_benchmark %}
{% endraw %}
post_benchmark_result:
  runner.http.query:
    - url: {{ rails_webhook_url }}
    - method: POST
    - header_dict:
        Content-Type: application/json
{% raw %}
    - data: '{{ {"tag": tag, "fun": data.get("fun", ""), "id": data.get("id", ""), "jid": data.get("jid", ""), "retcode": data.get("retcode", 1), "return": data.get("return", {})} | tojson }}'
{% endif %}
{% endraw %}
```

### Step 3: Write presence_change.sls.j2 template

Create `ansible/roles/salt_master/templates/presence_change.sls.j2` with:

```
# Reactor: notify Rails when minion presence changes (managed by Ansible)
{% raw %}
{% if data.get('new', []) or data.get('lost', []) %}
{% endraw %}
post_presence_change:
  runner.http.query:
    - url: {{ rails_webhook_url }}
    - method: POST
    - header_dict:
        Content-Type: application/json
{% raw %}
    - data: '{{ {"tag": tag, "new": data.get("new", []), "lost": data.get("lost", [])} | tojson }}'
{% endif %}
{% endraw %}
```

### Step 4: Write reactor.yml task

Create `ansible/roles/salt_master/tasks/reactor.yml` with:

```yaml
---
- name: Create reactor directory
  ansible.builtin.file:
    path: /srv/salt/reactor
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Deploy reactor configuration
  ansible.builtin.template:
    src: reactor.conf.j2
    dest: /etc/salt/master.d/reactor.conf
    owner: root
    group: root
    mode: '0640'
  notify: restart salt-master

- name: Deploy job return reactor
  ansible.builtin.template:
    src: job_return.sls.j2
    dest: /srv/salt/reactor/job_return.sls
    owner: root
    group: root
    mode: '0644'
  notify: restart salt-master

- name: Deploy presence change reactor
  ansible.builtin.template:
    src: presence_change.sls.j2
    dest: /srv/salt/reactor/presence_change.sls
    owner: root
    group: root
    mode: '0644'
  notify: restart salt-master
```

### Step 5: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/templates/reactor.conf.j2 \
        ansible/roles/salt_master/templates/job_return.sls.j2 \
        ansible/roles/salt_master/templates/presence_change.sls.j2 \
        ansible/roles/salt_master/tasks/reactor.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master reactor task and templates

Deploy reactor SLS files to /srv/salt/reactor/ via Ansible templates.
Uses {% raw %} blocks to preserve Salt Jinja expressions while
substituting Ansible variables (rails_webhook_url) at deploy time.
Replaces runtime salt['config.get'] lookups with baked-in values.

Templates:
- reactor.conf.j2: event-to-reactor mapping
- job_return.sls.j2: forward benchmark job results to Rails webhook
- presence_change.sls.j2: forward minion presence changes to Rails
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 11: Create salt_master role -- service.yml

**Files:**
- Create: `ansible/roles/salt_master/tasks/service.yml`

### Step 1: Write service.yml

Create `ansible/roles/salt_master/tasks/service.yml` with:

```yaml
---
- name: Enable and start salt-master
  ansible.builtin.systemd:
    name: salt-master
    state: started
    enabled: yes

- name: Enable and start salt-api
  ansible.builtin.systemd:
    name: salt-api
    state: started
    enabled: yes
```

### Step 2: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_master/tasks/service.yml
git commit -m "$(cat <<'EOF'
feat: add salt_master service management task

Enable and start salt-master and salt-api systemd services.
Restarts are handled by handlers triggered from config changes.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 12: Create Ansible salt_minion role

**Files:**
- Create: `ansible/roles/salt_minion/defaults/main.yml`
- Create: `ansible/roles/salt_minion/tasks/main.yml`
- Create: `ansible/roles/salt_minion/tasks/install.yml`
- Create: `ansible/roles/salt_minion/tasks/configure.yml`
- Create: `ansible/roles/salt_minion/tasks/service.yml`
- Create: `ansible/roles/salt_minion/templates/minion.conf.j2`
- Create: `ansible/roles/salt_minion/handlers/main.yml`

### Step 1: Create directory structure

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
mkdir -p ansible/roles/salt_minion/defaults
mkdir -p ansible/roles/salt_minion/tasks
mkdir -p ansible/roles/salt_minion/templates
mkdir -p ansible/roles/salt_minion/handlers
```

**Expected:** All directories created.

### Step 2: Write defaults/main.yml

Create `ansible/roles/salt_minion/defaults/main.yml` with:

```yaml
---
# Salt package version (must match master version)
salt_version: "3006"

# Salt master address (IP or hostname)
salt_master_address: "salt"
```

### Step 3: Write handlers/main.yml

Create `ansible/roles/salt_minion/handlers/main.yml` with:

```yaml
---
- name: restart salt-minion
  ansible.builtin.systemd:
    name: salt-minion
    state: restarted
    daemon_reload: yes
```

### Step 4: Write tasks/main.yml

Create `ansible/roles/salt_minion/tasks/main.yml` with:

```yaml
---
- name: Install Salt Minion
  ansible.builtin.import_tasks: install.yml

- name: Configure Salt Minion
  ansible.builtin.import_tasks: configure.yml

- name: Manage Salt Minion service
  ansible.builtin.import_tasks: service.yml
```

### Step 5: Write tasks/install.yml

Create `ansible/roles/salt_minion/tasks/install.yml` with:

```yaml
---
- name: Add SaltStack GPG key
  ansible.builtin.apt_key:
    url: "https://repo.saltproject.io/salt/py3/{{ ansible_distribution | lower }}/{{ ansible_distribution_version }}/{{ ansible_architecture }}/SALT-PROJECT-GPG-PUBKEY-2023.gpg"
    state: present

- name: Add SaltStack APT repository
  ansible.builtin.apt_repository:
    repo: "deb [arch={{ ansible_architecture }}] https://repo.saltproject.io/salt/py3/{{ ansible_distribution | lower }}/{{ ansible_distribution_version }}/{{ ansible_architecture }}/{{ salt_version }} {{ ansible_distribution_release }} main"
    state: present
    filename: saltstack

- name: Install salt-minion
  ansible.builtin.apt:
    name:
      - salt-minion
    state: present
    update_cache: yes
```

### Step 6: Write templates/minion.conf.j2

Create `ansible/roles/salt_minion/templates/minion.conf.j2` with:

```yaml
# Salt Minion configuration (managed by Ansible)
master: {{ salt_master_address }}
```

### Step 7: Write tasks/configure.yml

Create `ansible/roles/salt_minion/tasks/configure.yml` with:

```yaml
---
- name: Deploy Salt Minion configuration
  ansible.builtin.template:
    src: minion.conf.j2
    dest: /etc/salt/minion.d/master.conf
    owner: root
    group: root
    mode: '0640'
  notify: restart salt-minion
```

### Step 8: Write tasks/service.yml

Create `ansible/roles/salt_minion/tasks/service.yml` with:

```yaml
---
- name: Enable and start salt-minion
  ansible.builtin.systemd:
    name: salt-minion
    state: started
    enabled: yes
```

### Step 9: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/roles/salt_minion/
git commit -m "$(cat <<'EOF'
feat: add salt_minion Ansible role

Create salt_minion role for deploying Salt Minion to compute nodes:
- install.yml: add SaltStack APT repo and install salt-minion
- configure.yml: template minion.conf with master address
- service.yml: enable and start salt-minion service
- handlers: restart salt-minion on config changes

Follows the same structure as the existing perfspect role.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 13: Create main salt playbook and group_vars

**Files:**
- Create: `ansible/playbooks/salt.yml`
- Create: `ansible/group_vars/salt_master.yml`
- Create: `ansible/group_vars/salt_master/vault.yml.example`
- Modify: `.gitignore` (add vault.yml exclusion)

### Step 1: Write playbooks/salt.yml

Create `ansible/playbooks/salt.yml` with:

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

### Step 2: Write group_vars/salt_master.yml

Create `ansible/group_vars/salt_master.yml` with:

```yaml
---
# Salt Master configuration (non-secret values)
# Secrets are in group_vars/salt_master/vault.yml (Ansible Vault encrypted)

salt_version: "3006"

# GitFS configuration
salt_gitfs_user: "machine-account"
salt_gitfs_branch: "develop"
salt_gitfs_repo: "https://github.com/yuka1981/diagnostic-tools.git"
salt_gitfs_update_interval: 60

# Salt API
salt_api_port: 8000
salt_api_user: "rails_salt_user"
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# Network
salt_master_address: "10.0.0.1"
rails_webhook_url: "https://your-rails-app.com/api/v1/salt/events"

# References to vault-encrypted secrets
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
```

### Step 3: Create group_vars/salt_master/ directory

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
mkdir -p ansible/group_vars/salt_master
```

**Expected:** Directory created.

### Step 4: Write vault.yml.example

Create `ansible/group_vars/salt_master/vault.yml.example` with:

```yaml
---
# EXAMPLE ONLY -- copy to vault.yml and encrypt with:
#   ansible-vault encrypt ansible/group_vars/salt_master/vault.yml
#
# DO NOT commit vault.yml with real secrets. Only this .example file
# should be checked into version control.

vault_salt_gitfs_token: "ghp_replace_with_actual_github_token"
vault_salt_api_password: "replace_with_actual_secure_password"
```

### Step 5: Add vault.yml to .gitignore

Append to the project `.gitignore`:

```
# Ansible Vault encrypted secrets (use vault.yml.example as template)
ansible/group_vars/salt_master/vault.yml
```

**Verify:** The `.gitignore` entry prevents accidentally committing a real `vault.yml` with secrets.

### Step 6: Commit

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add ansible/playbooks/salt.yml \
        ansible/group_vars/salt_master.yml \
        ansible/group_vars/salt_master/vault.yml.example \
        .gitignore
git commit -m "$(cat <<'EOF'
feat: add salt playbook, group_vars, and vault example

Create the main salt.yml playbook that applies salt_master and
salt_minion roles to their respective host groups.

group_vars/salt_master.yml contains non-secret configuration.
group_vars/salt_master/vault.yml.example is a template for
Ansible Vault encrypted secrets (gitfs token, api password).
vault.yml is added to .gitignore to prevent committing secrets.
EOF
)"
```

**Expected:** Commit succeeds.

---

## Task 14: Validate Ansible syntax and run tests

**Files:**
- No new files (validation only)
- Modify: Any files if fixes are needed

### Step 1: Validate YAML syntax of all role files

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
python3 -c "
import yaml, glob, sys
errors = []
for f in sorted(glob.glob('ansible/roles/**/*.yml', recursive=True)):
    try:
        yaml.safe_load(open(f))
        print(f'OK: {f}')
    except Exception as e:
        errors.append(f)
        print(f'FAIL: {f}: {e}')
for f in sorted(glob.glob('ansible/group_vars/**/*.yml', recursive=True)):
    try:
        yaml.safe_load(open(f))
        print(f'OK: {f}')
    except Exception as e:
        errors.append(f)
        print(f'FAIL: {f}: {e}')
for f in sorted(glob.glob('ansible/playbooks/salt.yml')):
    try:
        yaml.safe_load(open(f))
        print(f'OK: {f}')
    except Exception as e:
        errors.append(f)
        print(f'FAIL: {f}: {e}')
if errors:
    print(f'\nFailed: {len(errors)} files')
    sys.exit(1)
else:
    print(f'\nAll YAML files valid')
"
```

**Expected:** All YAML files pass validation. Note: Jinja2 template files (`.j2`) are not pure YAML and are intentionally skipped by this check.

### Step 2: Verify Jinja2 templates exist

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
ls -la ansible/roles/salt_master/templates/
```

**Expected:** Lists `api.conf.j2`, `auth.conf.j2`, `gitfs.conf.j2`, `reactor.conf.j2`, `job_return.sls.j2`, `presence_change.sls.j2`, and `.gitkeep`.

### Step 3: Run Python tests to verify salt directory restructure

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark/salt && python -m pytest _tests/ -v
```

**Expected:** All tests pass. This confirms the directory restructure (Tasks 1-3) and import path updates (Task 2) did not break anything.

### Step 4: Commit fixes if needed

If any validation or test failed, fix the issue and commit:

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add -A
git commit -m "fix: correct issues found during validation"
```

**Expected:** No fixes needed if all previous tasks were done correctly.

---

## Task 15: Final cleanup and verification

**Files:**
- No new files (verification only)
- Delete: Any remaining empty directories

### Step 1: Run git status to verify all files are tracked

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git status
```

**Expected:** No untracked files related to this work. Working tree should be clean.

### Step 2: Verify the complete new directory structure

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
echo "=== Salt directory ==="
find salt/ -type f | sort

echo ""
echo "=== Ansible roles ==="
find ansible/roles/salt_master/ -type f | sort
find ansible/roles/salt_minion/ -type f | sort

echo ""
echo "=== Ansible playbooks and group_vars ==="
find ansible/playbooks/salt.yml ansible/group_vars/ -type f 2>/dev/null | sort
```

**Expected salt/ structure:**
```
salt/_modules/benchmark.py
salt/_modules/inventory.py
salt/_tests/__init__.py
salt/_tests/test_benchmark.py
salt/_tests/test_inventory.py
salt/benchmark/hpcg/collect.sls
salt/benchmark/hpcg/execute.sls
salt/benchmark/hpcg/init.sls
salt/benchmark/hpcg/prepare.sls
salt/benchmark/mlc/collect.sls
salt/benchmark/mlc/execute.sls
salt/benchmark/mlc/init.sls
salt/benchmark/mlc/prepare.sls
salt/master.d/api.conf
salt/reactor/job_return.sls
salt/reactor/presence_change.sls
```

**Expected ansible/roles/salt_master/ structure:**
```
ansible/roles/salt_master/defaults/main.yml
ansible/roles/salt_master/handlers/main.yml
ansible/roles/salt_master/tasks/auth.yml
ansible/roles/salt_master/tasks/configure.yml
ansible/roles/salt_master/tasks/gitfs.yml
ansible/roles/salt_master/tasks/install.yml
ansible/roles/salt_master/tasks/main.yml
ansible/roles/salt_master/tasks/reactor.yml
ansible/roles/salt_master/tasks/service.yml
ansible/roles/salt_master/templates/.gitkeep
ansible/roles/salt_master/templates/api.conf.j2
ansible/roles/salt_master/templates/auth.conf.j2
ansible/roles/salt_master/templates/gitfs.conf.j2
ansible/roles/salt_master/templates/job_return.sls.j2
ansible/roles/salt_master/templates/presence_change.sls.j2
ansible/roles/salt_master/templates/reactor.conf.j2
```

**Expected ansible/roles/salt_minion/ structure:**
```
ansible/roles/salt_minion/defaults/main.yml
ansible/roles/salt_minion/handlers/main.yml
ansible/roles/salt_minion/tasks/configure.yml
ansible/roles/salt_minion/tasks/install.yml
ansible/roles/salt_minion/tasks/main.yml
ansible/roles/salt_minion/tasks/service.yml
ansible/roles/salt_minion/templates/minion.conf.j2
```

### Step 3: Verify old directories are gone

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
test -d salt/modules && echo "ERROR: salt/modules/ still exists" || echo "OK: salt/modules/ removed"
test -d salt/states && echo "ERROR: salt/states/ still exists" || echo "OK: salt/states/ removed"
```

**Expected:** Both checks show `OK`.

### Step 4: Verify state include paths are preserved

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
grep 'benchmark.mlc' salt/benchmark/mlc/init.sls
grep 'benchmark.hpcg' salt/benchmark/hpcg/init.sls
```

**Expected:**
- MLC init.sls references: `benchmark.mlc.prepare`, `benchmark.mlc.execute`, `benchmark.mlc.collect`
- HPCG init.sls references: `benchmark.hpcg.prepare`, `benchmark.hpcg.execute`, `benchmark.hpcg.collect`

### Step 5: Commit any remaining changes

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git status
```

If there are uncommitted changes:

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git add -A
git commit -m "$(cat <<'EOF'
chore: clean up empty directories from salt restructure
EOF
)"
```

**Expected:** Working tree is clean. If not, commit the remaining cleanup.

### Step 6: Review full commit log for this work

```bash
cd /home/reid/code/diagnostic-tools/.worktrees/intel-mlc-benchmark
git log --oneline -15
```

**Expected commits (oldest to newest):**
1. `refactor: rename salt/modules/ to salt/_modules/ for Salt convention`
2. `refactor: move salt tests to _tests/ and update import paths`
3. `refactor: flatten salt/states/benchmark/ to salt/benchmark/`
4. `refactor: remove module_dirs/file_roots/reactor from api.conf`
5. `feat: add salt_master Ansible role skeleton with defaults and handlers`
6. `feat: add salt_master install task with APT repo and PAM user`
7. `feat: add salt_master configure task with api.conf template`
8. `feat: add salt_master GitFS task and template`
9. `feat: add salt_master auth task and template`
10. `feat: add salt_master reactor task and templates`
11. `feat: add salt_master service management task`
12. `feat: add salt_minion Ansible role`
13. `feat: add salt playbook, group_vars, and vault example`
