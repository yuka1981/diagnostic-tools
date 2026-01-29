# SaltStack REST API Migration Design

## Overview

Replace the current custom Go agent (`qis-agent`) and SSH-based node management with SaltStack's architecture using Salt minions and the salt-api REST interface. The Rails application communicates with nodes exclusively through salt-api on the admin node.

**Goals:**
- Eliminate custom agent deployment and maintenance (replace with community-maintained salt-minion)
- Replace fragile SSH/bastion topology with Salt's persistent ZeroMQ transport
- Gain centralized orchestration and state management via Salt
- Standardize on SaltStack as the infrastructure management layer

**Decision Record:**
- Salt Minion mode (not salt-ssh) — full event bus, real-time communication
- Full replacement of Go agent — no hybrid/coexistence period
- Token-based auth with PAM backend and auto-renewal
- Salt Master on admin node — minions connect on internal network
- Grains + custom modules hybrid for inventory mapping
- Salt states + orchestrate runner for benchmark workflows
- Development environment only — no production migration concerns

## Architecture

```
┌─────────────────┐         ┌──────────────────────┐
│   Rails App     │  HTTPS  │   Admin Node          │
│                 │────────▶│   ┌────────────────┐  │
│ SaltApiClient   │         │   │  salt-api       │  │
│ (token auth)    │◀────────│   │  (CherryPy)     │  │
│                 │   JSON  │   └────────────────┘  │
│ ProcessState    │         │   ┌────────────────┐  │
│ Service         │         │   │  salt-master    │  │
│ (unchanged)     │         │   │  + reactor      │  │
└─────────────────┘         │   └───────┬────────┘  │
                            └───────────┼───────────┘
                               ZeroMQ 4505/4506
                    ┌───────────┼───────────┐
                    │           │           │
              ┌─────▼──┐ ┌─────▼──┐ ┌─────▼──┐
              │ minion  │ │ minion  │ │ minion  │
              │ node-01 │ │ node-02 │ │ node-03 │
              │         │ │         │ │         │
              │ custom  │ │ custom  │ │ custom  │
              │ modules │ │ modules │ │ modules │
              └─────────┘ └─────────┘ └─────────┘
```

**Key changes from current architecture:**
- `SshExecutionService` replaced by `SaltApiClient` — all node communication goes through salt-api
- Go agent (`qis-agent`) fully replaced by salt-minion + custom Salt modules (Python)
- Heartbeat replaced by Salt's built-in minion presence detection (`manage.status`)
- Benchmark orchestration via Salt states instead of SSH + nohup
- Event streaming via Salt's SSE endpoint replaces Turbo broadcast from job callbacks

**What stays the same:**
- `ProcessStateService` and `NodeState` versioning model — the mapping layer feeds it the same schema
- Rails UI, controllers, Turbo Streams for frontend updates
- PostgreSQL data model for nodes, benchmark runs, artifacts

## Salt Master & Minion Configuration

### Salt Master (on admin node)

```yaml
# /etc/salt/master.d/api.conf
rest_cherrypy:
  port: 8000
  ssl_crt: /etc/salt/pki/api/cert.crt
  ssl_key: /etc/salt/pki/api/key.key

netapi_enable_clients:
  - local        # synchronous execution
  - local_async  # async execution (benchmarks)
  - runner       # orchestrate runner

# PAM auth for Rails service account
external_auth:
  pam:
    rails_salt_user:
      - '*':
        - grains.items
        - inventory.collect_dmi
        - inventory.collect_numa
        - inventory.collect_network_v2
        - benchmark.run_hpcg
        - benchmark.run_mlc
        - benchmark.cancel
        - test.ping
      - '@runner':
        - manage.status
        - state.orchestrate

# Custom modules/states paths
file_roots:
  base:
    - /srv/salt/states
module_dirs:
  - /srv/salt/modules

# Reactor for event-driven updates
reactor:
  - 'salt/job/ret/*':
    - /srv/salt/reactor/job_return.sls
  - 'salt/presence/change':
    - /srv/salt/reactor/presence_change.sls
```

### Salt Minion (on each compute node)

```yaml
# /etc/salt/minion.d/master.conf
master: <admin-node-ip>
id: <hostname>  # matches Node model's hostname field
```

Custom execution modules placed in `/srv/salt/modules/` on the master are automatically synced to minions via `saltutil.sync_modules`. No manual per-node deployment needed.

## Rails Salt API Client

### `app/services/salt_api_client.rb`

Core HTTP client replacing `SshExecutionService` as the primary node communication layer.

**Responsibilities:**
- Token lifecycle: authenticate via PAM, cache token, auto-renew before expiry
- Synchronous calls (`local` client) for inventory collection
- Async calls (`local_async` client) for benchmark execution
- Job polling (`GET /jobs/<jid>`) for async result retrieval
- Event streaming (`GET /events`) via SSE for real-time updates
- Minion status (`runner` client) for presence detection

**Interface:**

```ruby
client = SaltApiClient.new

# Inventory
client.run("node-01", "grains.items")
client.run("node-01", "inventory.collect_dmi")

# Benchmark (async)
jid = client.run_async("node-01", "state.orchestrate",
                        mods: "benchmark.hpcg",
                        pillar: { work_dir: "/tmp/hpcg" })
result = client.job_result(jid)

# Presence
client.run_runner("manage.status")

# Events (streaming)
client.events do |tag, data|
  # process event
end
```

**Token management:** The client authenticates on first call, stores the token and expiry in memory. Before each request it checks if the token expires within 60 seconds and re-authenticates if so. No tokens stored in the database — ephemeral session tokens scoped to the Rails process.

**Error handling:** Wraps salt-api HTTP errors into domain exceptions:
- `SaltApiClient::AuthenticationError`
- `SaltApiClient::TargetUnreachable`
- `SaltApiClient::TimeoutError`

## Inventory Collection & Mapping

### Collection Flow

When inventory is triggered (UI click or scheduled), `Inventory::SaltCollectService` replaces the SSH-based `TriggerCollectService`:

1. Call `grains.items` on the target minion — returns CPU, memory, OS, network interfaces
2. Call custom modules in parallel for gaps:
   - `inventory.collect_dmi` — DMI/BIOS data (wraps `dmidecode`)
   - `inventory.collect_numa` — NUMA topology from `/sys/devices/system/node/`
   - `inventory.collect_network_v2` — Advanced networking (wraps `lshw -class network -json`)
3. Pass combined data through `Salt::InventoryMapper` that transforms Salt's data format into the existing schema

### Mapper (`app/services/salt/inventory_mapper.rb`)

```ruby
# Input: raw grains + custom module outputs
# Output: hash matching existing ProcessStateService expectations

{
  host: { hostname:, ip:, arch:, kernel: },    # from grains
  cpu:  { model:, cores:, sockets:, mhz: },    # from grains
  memory: { total_kb:, dimms: [] },             # grains + custom
  disks: [ { name:, size_gb:, type: } ],        # from grains
  network: { interfaces: [] },                  # from grains
  network_v2: { devices: [] },                  # from custom module
  dmi: { bios:, system:, baseboard: }           # from custom module
}
```

`ProcessStateService` stays unchanged. The mapper is the only translation layer. Content hashing and versioned `NodeState` creation work identically.

### Periodic Collection

Replace the agent's daemon mode heartbeat/inventory loop with a Rails `sidekiq-cron` job that calls `SaltCollectService` on a configurable interval, or a Salt scheduled job on the master.

## Benchmark Orchestration

### Salt States Structure

```
/srv/salt/states/benchmark/
├── hpcg/
│   ├── init.sls          # orchestrate entry point
│   ├── prepare.sls       # create work dir, check dependencies
│   ├── execute.sls       # run HPCG binary
│   └── collect.sls       # parse results, gather artifacts
├── mlc/
│   ├── init.sls
│   ├── prepare.sls
│   ├── execute.sls
│   └── collect.sls
└── pillar/
    └── benchmark.sls     # configurable parameters
```

### Execution Flow

1. Rails calls `run_async` with `state.orchestrate` for `benchmark.hpcg`
2. Pillar data passes parameters: work directory, binary path, MLC profile, advanced options
3. Salt orchestrate runner sequences: prepare → execute → collect
4. Each step fires events on the Salt event bus with progress info
5. Rails listens via `GET /events` SSE or polls `GET /jobs/<jid>`
6. On completion, the `collect` state returns structured results: status, metrics, log content, artifact file paths

### Result Handling

`Benchmark::SaltResultService` replaces the agent's HTTP callback:

- Receives the job return data (metrics, status, logs, artifact paths)
- Fetches artifact file contents from minion via `cp.push` or `salt-cp`
- Updates `BenchmarkRun` record with status, metrics, timestamps
- Creates `ArtifactIndex` records

### Cancellation

`benchmark.cancel` execution module sends SIGTERM to the running process. Called via `client.run("node-01", "benchmark.cancel")`.

## Real-Time Events & Presence Detection

### Event Streaming

Salt's event bus replaces three current mechanisms: Turbo broadcast from job callbacks, agent heartbeat POSTs, and benchmark status polling.

### Event Listener (`app/services/salt/event_listener_service.rb`)

A persistent background process (Sidekiq job or standalone thread) connects to `GET /events` on salt-api via SSE. Dispatches events by tag pattern:

| Salt event tag | Rails action |
|---|---|
| `salt/job/ret/*/benchmark.*` | Update `BenchmarkRun` status, broadcast Turbo Stream |
| `salt/job/ret/*/inventory.*` | Feed results to `ProcessStateService` |
| `salt/presence/change` | Update node online/offline status |
| `salt/auth` | Log minion key events (new node registered) |

### Presence Detection (Replacing Heartbeat)

Current system: agent sends heartbeat every 60s, node marked offline if no heartbeat within 2 minutes.

New system: Salt master tracks minion presence natively:
- **Reactive:** Salt fires `salt/presence/change` events when minions connect/disconnect. Event listener catches it and updates `Node` records.
- **Polling:** Rails periodically calls `manage.status` runner (returns lists of up/down minions). Updates `Node` records accordingly.

The `online?` method on `Node` shifts from "heartbeat within 2 minutes" to "Salt reports minion as present."

Turbo Stream updates continue to work — the event listener broadcasts to the same channels the UI already subscribes to.

## Code to Remove

### Go Agent (entire `agent/` directory)
- All commands: `collect`, `inventory push`, `start`, `hpcg`, `mlc`, `cancel`, `mlc_install`
- All collectors, uploaders, identity management
- Build and release pipeline for the Go binary

### Rails SSH Layer
- `app/services/ssh_execution_service.rb` — base class for all SSH operations
- `app/services/inventory/trigger_collect_service.rb` — SSH-based collection
- `app/services/benchmark/trigger_run_service.rb` — SSH-based benchmark launch
- `app/services/agent/install_service.rb` — agent binary deployment
- `app/services/agent/update_service.rb` — agent upgrade
- `app/services/agent/uninstall_service.rb` — agent removal
- `app/services/agent/lifecycle_service.rb` — base class
- `app/services/agent/credential_checker.rb` — API key validation for agent
- SSH configuration: `SshSetting` model, jump host config, per-node SSH overrides

### API Endpoints (Agent Callbacks)
- `POST /api/v1/inventory/push` — replaced by Salt inventory collection
- `POST /api/nodes/:id/heartbeat` — replaced by Salt presence
- `POST /api/v1/benchmark_runs` — replaced by Salt job returns
- `POST /api/v1/mlc_installations/:uuid/progress|complete` — replaced by Salt states

### Node Model Fields (Unused After Migration)
- `connection_method`, SSH override fields (`ssh_user_override`, `ssh_port_override`, etc.)
- `last_heartbeat_at`, `agent_version`, `agent_status`
- `agent_path`, `benchmark_work_dir` (move to Salt pillar data)

## New Components

### Rails Services

```
app/services/
├── salt_api_client.rb                    # Core HTTP client for salt-api
├── salt/
│   ├── inventory_mapper.rb              # Grains + custom → ProcessStateService schema
│   ├── event_listener_service.rb        # SSE consumer, dispatches events
│   └── benchmark_result_service.rb      # Job return → BenchmarkRun update
├── inventory/
│   └── salt_collect_service.rb          # Replaces trigger_collect_service
└── benchmark/
    └── salt_trigger_run_service.rb      # Replaces trigger_run_service
```

### Salt Master Files (on admin node)

```
/srv/salt/
├── modules/                             # Custom execution modules
│   ├── inventory_dmi.py                 # DMI collection (dmidecode)
│   ├── inventory_numa.py                # NUMA topology (/sys)
│   ├── inventory_network_v2.py          # Advanced networking (lshw)
│   └── benchmark.py                     # run_hpcg, run_mlc, cancel
├── states/
│   ├── benchmark/
│   │   ├── hpcg/
│   │   │   ├── init.sls
│   │   │   ├── prepare.sls
│   │   │   ├── execute.sls
│   │   │   └── collect.sls
│   │   └── mlc/
│   │       ├── init.sls
│   │       ├── prepare.sls
│   │       ├── execute.sls
│   │       └── collect.sls
│   └── pillar/
│       └── benchmark.sls
├── reactor/
│   ├── job_return.sls                   # Route job results
│   └── presence_change.sls             # Node online/offline
└── master.d/
    └── api.conf                         # salt-api + auth config
```

### Tests

```
spec/services/
├── salt_api_client_spec.rb
├── salt/
│   ├── inventory_mapper_spec.rb
│   ├── event_listener_service_spec.rb
│   └── benchmark_result_service_spec.rb
├── inventory/
│   └── salt_collect_service_spec.rb
└── benchmark/
    └── salt_trigger_run_service_spec.rb
```
