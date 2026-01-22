# Intel PerfSPECT Integration Design

**Date**: 2026-01-22
**Status**: Draft
**Author**: Claude (with user collaboration)

## Overview

Integrate Intel PerfSPECT into the HPC diagnostic tools platform, enabling system profiling, performance analysis, and benchmark comparison across cluster nodes. PerfSPECT will be executed via Ansible playbooks triggered from the Rails application.

## Goals

- Full PerfSPECT capability: `report`, `telemetry`, and `flame` subcommands
- Hybrid UI: Quick profiling from node details + benchmark recipe capability
- Preset profiles for common use cases + custom command builder for power users
- Real-time status updates via Turbo broadcasts

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Rails Web App                          │
├─────────────────────────────────────────────────────────┤
│  New Components:                                        │
│  - ProfilingRun model (status, metrics, artifacts)      │
│  - ProfilingRecipe model (presets + custom configs)     │
│  - Profiling::TriggerJob (background execution)         │
│  - Ansible::ExecutorService (runs playbooks via SSH)    │
└─────────────────────────────────────────────────────────┘
                         │
                         │ SSH
                         ▼
┌─────────────────────────────────────────────────────────┐
│               Admin/Jump Node                           │
├─────────────────────────────────────────────────────────┤
│  - Ansible installed                                    │
│  - Playbooks synced from Rails server                   │
│  - Executes against target compute nodes                │
└─────────────────────────────────────────────────────────┘
                         │
                         │ Ansible (SSH)
                         ▼
┌─────────────────────────────────────────────────────────┐
│              Target Compute Node                        │
├─────────────────────────────────────────────────────────┤
│  - module load perfspect/3.13.0                         │
│  - perfspect report|telemetry|flame                     │
│  - Results → shared filesystem + API callback           │
└─────────────────────────────────────────────────────────┘
```

Key difference from current benchmark flow: Instead of SSH → agent binary, we use SSH → admin node → Ansible → target node. This enables complex multi-step profiling workflows while keeping execution declarative and idempotent.

## Data Models

### ProfilingRecipe

Templates for profiling configurations (similar to BenchmarkRecipe).

| Field | Type | Description |
|-------|------|-------------|
| name | string | "Quick System Report", "Full Analysis", "CPU Flame Graph" |
| slug | string | "quick-system-report" |
| description | text | User-facing explanation |
| tool | string | "perfspect" (extensible for future tools) |
| subcommand | string | "report", "telemetry", "flame" |
| module_name | string | "perfspect/3.13.0" (configurable per recipe) |
| default_options | jsonb | `{"duration": 60, "output_format": "html"}` |
| timeout_seconds | integer | Max execution time |
| status | enum | active/archived |

### ProfilingRun

Individual execution records.

| Field | Type | Description |
|-------|------|-------------|
| uuid | string | Unique identifier |
| node_id | reference | Target node |
| profiling_recipe_id | reference | Which recipe (nullable for custom runs) |
| status | enum | pending → running → success/failed/cancelled |
| options | jsonb | Merged recipe defaults + user overrides |
| metrics | jsonb | Extracted key metrics (if applicable) |
| started_at | datetime | Execution start time |
| finished_at | datetime | Execution end time |
| log_content | text | Ansible output / stderr |
| error_message | text | Error details if failed |
| artifact_path | string | Shared filesystem path to results |
| user_id | reference | Who triggered it |

### ProfilingArtifact

Links to result files (HTML reports, flame graphs, JSON data).

| Field | Type | Description |
|-------|------|-------------|
| profiling_run_id | reference | Parent run |
| filename | string | "system_report.html" |
| file_type | string | "html", "svg", "json" |
| file_path | string | Full path on shared filesystem |
| file_size | integer | File size in bytes |

## Ansible Playbook Structure

Directory layout in the repo:

```
ansible/
├── inventory/
│   └── dynamic.py           # Script that queries Rails API for node inventory
├── playbooks/
│   └── perfspect/
│       ├── report.yml       # System configuration report
│       ├── telemetry.yml    # Live performance collection
│       ├── flame.yml        # CPU flame graph generation
│       └── custom.yml       # Generic runner for custom commands
├── roles/
│   └── perfspect/
│       ├── tasks/
│       │   ├── main.yml
│       │   ├── setup.yml    # Module load, workspace prep
│       │   ├── execute.yml  # Run perfspect command
│       │   └── collect.yml  # Gather results, upload metrics
│       ├── templates/
│       │   └── perfspect_config.j2
│       └── defaults/
│           └── main.yml     # Default module name, paths, timeouts
└── callback_plugins/
    └── rails_notify.py      # Custom callback to POST status updates to Rails API
```

### Example Playbook

`ansible/playbooks/perfspect/report.yml`:

```yaml
- name: Run PerfSPECT System Report
  hosts: "{{ target_host }}"
  gather_facts: no
  vars:
    run_uuid: "{{ run_uuid }}"
    api_server: "{{ api_server }}"
    api_token: "{{ api_token }}"
    output_dir: "{{ shared_artifacts_path }}/{{ run_uuid }}"

  roles:
    - role: perfspect
      perfspect_subcommand: report
      perfspect_options: "{{ options | default({}) }}"
```

The callback plugin sends real-time status updates (RUNNING, SUCCESS, FAILED) to Rails API, enabling Turbo broadcast to connected users.

## Rails Service Layer

### Ansible::ExecutorService

Core service that runs playbooks via SSH to admin node.

```ruby
# app/services/ansible/executor_service.rb
class Ansible::ExecutorService
  def initialize(admin_node:, playbook:, extra_vars:)
    @admin_node = admin_node   # AdminNode record or config
    @playbook = playbook       # "perfspect/report.yml"
    @extra_vars = extra_vars   # Hash passed as --extra-vars JSON
  end

  def execute
    # 1. SSH to admin node
    # 2. Sync playbooks if needed (rsync or git pull)
    # 3. Run: ansible-playbook -i inventory/dynamic.py \
    #         playbooks/#{@playbook} \
    #         --extra-vars '#{@extra_vars.to_json}'
    # 4. Stream output, capture exit code
    # 5. Return Result object with success/failure + output
  end
end
```

### Profiling::TriggerService

Orchestrates a profiling run.

```ruby
# app/services/profiling/trigger_service.rb
class Profiling::TriggerService
  def call(profiling_run)
    # 1. Build extra_vars from run config
    extra_vars = {
      target_host: profiling_run.node.hostname,
      run_uuid: profiling_run.uuid,
      api_server: Rails.application.config.api_base_url,
      api_token: generate_callback_token(profiling_run),
      shared_artifacts_path: Settings.shared_artifacts_path,
      options: profiling_run.options
    }

    # 2. Determine playbook from recipe
    playbook = "perfspect/#{profiling_run.subcommand}.yml"

    # 3. Execute via Ansible
    result = Ansible::ExecutorService.new(
      admin_node: Settings.ansible_admin_node,
      playbook: playbook,
      extra_vars: extra_vars
    ).execute

    # 4. Handle result
  end
end
```

### Profiling::TriggerJob

Background job wrapper with retry logic and notifications.

## User Interface

### Node Details Page - Profiling Tab

```
┌─────────────────────────────────────────────────────────┐
│  Node: compute-001                                      │
├──────────┬──────────┬──────────┬───────────────────────┤
│ Overview │ Hardware │ Benchmarks │ Profiling          │
└──────────┴──────────┴──────────┴───────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  Quick Profiles                                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐       │
│  │ System      │ │ Telemetry   │ │ Flame       │       │
│  │   Report    │ │  (60s)      │ │   Graph     │       │
│  │   [Run]     │ │   [Run]     │ │   [Run]     │       │
│  └─────────────┘ └─────────────┘ └─────────────┘       │
│                                                         │
│  [+ Custom Profile...]                                  │
├─────────────────────────────────────────────────────────┤
│  Recent Profiling Runs                                  │
│  ┌─────────────────────────────────────────────────┐   │
│  │ System Report    ✓ Success   2 min ago  [View]  │   │
│  │ Telemetry (120s) ● Running   started 45s ago    │   │
│  │ Flame Graph      ✗ Failed    1 hour ago [View]  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Custom Profile Builder

Modal or slide-out panel:

```
┌─────────────────────────────────────────────────────────┐
│  Custom PerfSPECT Profile                        [X]   │
├─────────────────────────────────────────────────────────┤
│  Subcommand:  ○ report  ○ telemetry  ○ flame           │
│                                                         │
│  Module:      [perfspect/3.13.0    ▼]                  │
│                                                         │
│  ── Options (varies by subcommand) ──                  │
│  Duration:    [60] seconds     (telemetry/flame only)  │
│  Output format: ○ HTML  ○ JSON  ○ Both                 │
│  Collect perf data: [✓]                                │
│                                                         │
│  ── Advanced ──                                        │
│  Extra args:  [                                    ]   │
│                                                         │
│              [Cancel]  [Run Profile]                   │
└─────────────────────────────────────────────────────────┘
```

### Results View

Display artifacts inline where possible:
- HTML reports rendered in iframe
- Flame graphs displayed as interactive SVG
- JSON data shown in formatted/collapsible view

## Configuration

### Rails Settings

`config/settings.yml`:

```yaml
profiling:
  # Admin node where Ansible is installed
  ansible_admin_node:
    host: "admin-node.cluster.local"
    user: "ansible"
    ssh_key_path: "/path/to/key"

  # Path on admin node where playbooks are located
  playbooks_path: "/opt/hpc-tools/ansible"

  # Sync method: "rsync" (push from Rails) or "git" (pull on admin node)
  playbook_sync_method: "rsync"

  # Shared filesystem path accessible by both Rails and compute nodes
  shared_artifacts_path: "/shared/profiling_artifacts"

  # Default module name (overridable per recipe)
  default_perfspect_module: "perfspect/3.13.0"

  # Timeouts
  default_timeout_seconds: 300
  ansible_connection_timeout: 30
```

### Environment Variables

For sensitive values:

```bash
ANSIBLE_ADMIN_HOST=admin-node.cluster.local
ANSIBLE_ADMIN_USER=ansible
ANSIBLE_SSH_KEY_PATH=/path/to/key
PROFILING_API_SECRET=<secret for callback authentication>
```

## API Endpoints

### Callback API (Ansible → Rails)

```
POST /api/v1/profiling_runs/:uuid/status
```

Called by Ansible callback plugin during execution:

```json
{
  "status": "running",
  "message": "Executing perfspect report...",
  "progress": 50
}
```

```
POST /api/v1/profiling_runs/:uuid/complete
```

Called at end of playbook with final results:

```json
{
  "status": "success",
  "metrics": {
    "cpu_model": "Intel Xeon Gold 6248",
    "cores": 40,
    "bios_version": "2.10.0",
    "turbo_enabled": true
  },
  "artifacts": [
    {
      "filename": "system_report.html",
      "file_path": "/shared/profiling_artifacts/abc123/system_report.html",
      "file_type": "html",
      "file_size": 245678
    }
  ],
  "log_content": "..."
}
```

### Web API (UI consumption)

| Endpoint | Description |
|----------|-------------|
| `GET /api/v1/nodes/:node_id/profiling_runs` | List profiling runs for a node |
| `GET /api/v1/profiling_runs/:uuid` | Get run details + artifacts |
| `GET /api/v1/profiling_runs/:uuid/artifacts/:filename` | Stream artifact file |
| `POST /api/v1/profiling_runs/:uuid/cancel` | Request cancellation |

### Authentication

- Callback API uses a run-specific token generated at trigger time
- Web API uses existing session/API key authentication

## Error Handling

| Scenario | Detection | Response |
|----------|-----------|----------|
| SSH to admin node fails | Connection timeout/refused | Mark run as failed, log SSH error details, notify user |
| Ansible playbook syntax error | Non-zero exit + parsing stderr | Mark failed, capture full Ansible output in log_content |
| Module load fails | Ansible task failure | Mark failed, suggest checking module availability |
| PerfSPECT command fails | Non-zero exit from perfspect | Mark failed, capture stderr, partial artifacts still saved |
| Callback API unreachable | Ansible uri module timeout | Playbook continues, final status determined by exit code |
| Shared filesystem unavailable | Write permission error | Mark failed, suggest checking mount/permissions |
| Run timeout exceeded | Ansible async timeout | Kill process, mark as failed with timeout message |
| User requests cancellation | Cancel API called | SSH to admin node, kill Ansible process |

### Idempotency

If a run is triggered twice with the same UUID, Ansible skips already-completed tasks. Artifacts are overwritten (not duplicated).

### Cleanup

Old artifacts can be pruned via scheduled job based on retention policy (configurable days).

## Implementation Phases

### Phase 1: Foundation

- Create `ProfilingRecipe`, `ProfilingRun`, `ProfilingArtifact` models + migrations
- Set up `ansible/` directory structure with placeholder playbooks
- Add configuration settings (Settings.profiling.*)

### Phase 2: Ansible Integration

- Implement `Ansible::ExecutorService` for SSH → admin node → playbook execution
- Create `perfspect` role with setup/execute/collect tasks
- Build callback plugin for Rails API status updates
- Test manually: run playbook from admin node against a target

### Phase 3: Rails Services & Jobs

- Implement `Profiling::TriggerService` and `Profiling::TriggerJob`
- Add API endpoints for callbacks (`/api/v1/profiling_runs/:uuid/status`, `/complete`)
- Wire up Turbo broadcasts for real-time status updates

### Phase 4: UI

- Add "Profiling" tab to node details page
- Build quick profile cards (report, telemetry, flame)
- Implement custom profile builder modal
- Create results view with artifact display (HTML iframe, SVG render)

### Phase 5: Polish

- Cancellation support
- Artifact cleanup job
- Preflight checks (similar to benchmark preflight)
- Seed default ProfilingRecipe records

## Future Considerations

- Support for additional profiling tools (Intel VTune, perf, etc.)
- Multi-node profiling runs (profile across a set of nodes)
- Scheduled/recurring profiling jobs
- Comparison views between profiling runs
- Integration with benchmark runs (profile during benchmark execution)
