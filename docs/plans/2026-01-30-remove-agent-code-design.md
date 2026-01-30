# Remove Go Agent Code — Design

## Context

The Go agent (`agent/` directory) is being fully replaced by Salt custom modules for inventory collection and benchmark execution. All agent-related code, API endpoints, SSH infrastructure, and database artifacts should be removed.

## Scope

### Delete Entirely

**`agent/` directory** — All Go source code, tests, build config, docs.

**Rails files:**

| Category | Files |
|----------|-------|
| API Controllers | `api/v1/heartbeats_controller.rb`, `api/v1/health_controller.rb`, `api/v1/benchmark_runs_controller.rb`, `api/v1/mlc_installations_controller.rb` |
| SSH Services | `ssh_execution_service.rb`, `ssh_override_migration_service.rb`, `benchmark/preflight_service.rb`, `benchmark/cancel_run_service.rb` |
| Models | `ssh_setting.rb`, `ssh_config.rb`, `agent_event.rb` |
| Controllers | `settings/ssh_defaults_controller.rb` |
| Views | `views/settings/ssh_defaults/` (entire directory) |
| JS | `ssh_override_controller.js` |
| Specs | All specs for the above: factories, model specs, request specs, service specs, system specs |

**Routes to remove** from `config/routes.rb`:
- `get "health"` endpoint
- `post :heartbeat` endpoint
- `namespace :settings { resource :ssh_defaults }` block

### Modify

**`app/models/node.rb`:**
- Remove `has_many :agent_events` association
- Remove all `effective_ssh_*` methods
- Remove SSH-related validations

**`app/models/benchmark_run.rb`:**
- Remove `AGENT_STATUS_MAP` constant
- Remove `status_from_agent` class method

**`app/controllers/api/v1/base_controller.rb`:**
- Remove agent token authentication fallback

**`app/services/mlc/trigger_install_service.rb`:**
- Remove SSH execution inheritance; rewrite or delete if Salt states handle MLC installation

**`app/jobs/mlc/install_job.rb`:**
- Remove `agent_token` parameter

**`app/views/shared/_sidebar.html.erb`:**
- Remove SSH settings link

**`spec/factories/nodes.rb`:**
- Remove SSH/agent attribute traits

### Database Migration

Create `RemoveAgentAndSshIntegration` migration:

**Drop tables:** `agent_binaries`, `agent_releases`, `agent_events`, `ssh_settings`, `ssh_profiles`

**Remove columns from `nodes`:**
- `agent_path`, `agent_version`, `agent_status`, `last_heartbeat_at`
- `ssh_port`, `ssh_user`, `ssh_key`, `ssh_password`, `ssh_connect_method`
- `ssh_user_override`, `ssh_port_override`, `ssh_key_override`, `ssh_password_override`, `sudo_credential_override`, `ssh_connect_method_override`
- `benchmark_work_dir`, `sudo_credential`

**Keep:** `api_token`, `api_key_id` on `nodes` (used by Salt API auth).

## Approach

Single-pass removal: delete all agent code, modify affected files, create cleanup migration, update tests. One coherent set of changes.

## Verification

- `bin/rubocop -f github` passes with no offenses
- `bin/rspec` passes (all green)
- No remaining references to `qis-agent`, `hpc-agent`, `SshExecutionService`, `SshSetting`, or `agent_events` in Rails code
- `db:migrate` runs cleanly
