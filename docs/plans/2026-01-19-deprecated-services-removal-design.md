# Deprecated Services Removal Design

## Overview

Remove three deprecated agent lifecycle services and update all callers to use their replacements.

## Services Being Removed

| Deprecated Service | Replacement | Error Class Change |
|-------------------|-------------|-------------------|
| `Agent::RemoteInstallService` | `Agent::InstallService` | `InstallError` → `Agent::Errors::*` |
| `Agent::RemoteUninstallService` | `Agent::UninstallService` | `UninstallError` → `Agent::Errors::*` |
| `Agent::PatchService` | `Agent::UpdateService` | `PatchError` → `Agent::Errors::*` |

## Interface Changes

### InstallService

The new service uses node-stored settings instead of direct parameters:

```ruby
# OLD
Agent::RemoteInstallService.new(
  target_host: target_host,
  arch: arch,
  bastion_host: bastion_host,
  bastion_user: bastion_user,
  bastion_password: credentials[:bastion_password],
  sudo_password: credentials[:sudo_password],
  local_binary_path: local_binary_path,
  server_url: server_url,
  agent_token: agent_token,
  node: node,
  on_progress: ->(msg) { ... }
)

# NEW
Agent::InstallService.new(
  node: node,
  server_url: server_url,
  api_token: agent_token,
  binary_path: local_binary_path,
  cache_key: cache_key,
  on_progress: ->(msg) { ... }
)
```

### UninstallService

The new service removes step-based progress tracking:

```ruby
# OLD
Agent::RemoteUninstallService.new(
  target_host: target_host,
  bastion_host: bastion_host,
  bastion_user: bastion_user,
  bastion_password: credentials[:bastion_password],
  sudo_password: credentials[:sudo_password],
  node: node,
  on_progress: ->(step, msg) { ... }
)
# Uses RemoteUninstallService::STEPS constant

# NEW
Agent::UninstallService.new(
  node: node,
  cache_key: cache_key,
  on_progress: ->(msg) { ... }
)
# No STEPS constant - uses AgentEvent for tracking
```

### UpdateService

The new service uses the lifecycle error hierarchy:

```ruby
# OLD
Agent::PatchService.new(
  node: node,
  agent_release: agent_release,
  force: force,
  on_progress: ->(msg) { ... }
)
# Raises Agent::PatchService::PatchError

# NEW
Agent::UpdateService.new(
  node: node,
  agent_release: agent_release,
  force: force,
  cache_key: cache_key,
  on_progress: ->(msg) { ... }
)
# Raises Agent::Errors::ValidationError, ServiceError, etc.
```

## Files to Delete

1. `app/services/agent/remote_install_service.rb`
2. `app/services/agent/remote_uninstall_service.rb`
3. `app/services/agent/patch_service.rb`
4. `spec/services/agent/remote_install_service_spec.rb`
5. `spec/services/agent/remote_uninstall_service_spec.rb`
6. `spec/services/agent/patch_service_spec.rb`

## Files to Rewrite

### 1. `app/jobs/agent/install_job.rb`

- Change service class from `RemoteInstallService` to `InstallService`
- Store credentials in cache and pass `cache_key` instead of direct params
- Remove manual UUID sync (service handles it internally)
- Update parameter names: `agent_token` → `api_token`, `local_binary_path` → `binary_path`

### 2. `app/jobs/agent/uninstall_job.rb`

- Change service class from `RemoteUninstallService` to `UninstallService`
- Store credentials in cache and pass `cache_key`
- Update progress callback signature from `(step, msg)` to `(msg)`
- Define local STEPS constant for UI compatibility or update view

### 3. `app/jobs/agent/update_job.rb`

- Change service class from `PatchService` to `UpdateService`
- Update error rescue from `PatchService::PatchError` to `Agent::Errors::*`
- Add `cache_key` parameter for credentials

## Files to Update

### 1. `app/views/nodes/uninstalls/create.turbo_stream.erb`

Remove reference to `Agent::RemoteUninstallService::STEPS`.

### 2. `spec/jobs/agent/install_job_spec.rb`

- Update mocks from `RemoteInstallService` to `InstallService`
- Update expected parameters
- Update result structure expectations

### 3. `spec/jobs/agent/uninstall_job_spec.rb`

- Update mocks from `RemoteUninstallService` to `UninstallService`
- Update expected parameters
- Remove STEPS constant references

### 4. `spec/jobs/agent/update_job_spec.rb`

- Update mocks from `PatchService` to `UpdateService`
- Update error class from `PatchError` to lifecycle errors
- Update result structure expectations

### 5. `spec/system/node_management_spec.rb`

- Update service references from deprecated to new services

## Execution Order

1. Update jobs to use new services
2. Update job specs to match new interfaces
3. Update view to remove STEPS reference
4. Update system specs
5. Delete deprecated service files
6. Delete deprecated service specs
7. Run full test suite to verify

## Rollback Plan

If issues arise, the deprecated services can be restored from git history. The deprecation warnings were added specifically to allow a transition period.
