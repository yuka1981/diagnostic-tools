# Agent Lifecycle Service Consolidation

**Date:** 2026-01-19
**Status:** Approved

## Overview

Consolidate overlapping agent lifecycle services into a unified set based on `LifecycleService`. Deprecate and remove the old standalone services after migration.

## Current State

Six services exist with overlapping functionality:

| Operation | Old (Standalone) | New (LifecycleService-based) |
|-----------|------------------|------------------------------|
| Install | `RemoteInstallService` | `InstallService` |
| Update | `PatchService` | `UpdateService` |
| Uninstall | `RemoteUninstallService` | `UninstallService` |

The new services provide: unified error hierarchy, AgentEvent audit logging, 5-phase execution pattern, and auto-rollback (UpdateService). However, they're missing two features from the old services.

## Changes

### 1. Add IP→Hostname Fallback to LifecycleService

**File:** `app/services/agent/lifecycle_service.rb`

When SSH connection to node IP fails (timeout, unreachable), retry with hostname if different.

```ruby
def connect_direct(&block)
  primary_host = @node.ip.presence || @node.hostname
  fallback_host = (@node.ip.present? && @node.hostname != @node.ip) ? @node.hostname : nil

  begin
    attempt_connection(primary_host, &block)
  rescue ConnectionError => e
    raise unless fallback_host && e.recoverable

    report_progress "Connection to #{primary_host} failed, retrying with #{fallback_host}..."
    attempt_connection(fallback_host, &block)
  end
end

private

def attempt_connection(host, &block)
  report_progress "Connecting directly to #{host}"
  Net::SSH.start(host, ssh_user, ssh_options.merge(port: @node.ssh_port || 22), &block)
rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT,
       Net::SSH::ConnectionTimeout => e
  raise ConnectionError.new(
    "SSH connection failed: #{e.message}",
    phase: :connect,
    details: { host: host, error_class: e.class.name },
    recoverable: true
  )
rescue Net::SSH::AuthenticationFailed => e
  raise ConnectionError.new(
    "SSH authentication failed: #{e.message}",
    phase: :connect,
    details: { host: host, error_class: e.class.name },
    recoverable: false  # Don't retry auth failures
  )
end
```

**Behavior:**
- Only retries network errors (timeout, unreachable), not auth failures
- Only retries if hostname differs from IP
- Logs the fallback attempt for visibility

### 2. Add WebSocket Uninstall to UninstallService

**File:** `app/services/agent/uninstall_service.rb`

When agent is online, send uninstall command via ActionCable instead of SSH.

```ruby
def execute_operation(ssh)
  report_progress "Starting agent uninstallation"

  if should_use_websocket?
    perform_websocket_uninstall
  elsif ssh.nil?
    perform_local_uninstall
  else
    perform_remote_uninstall(ssh)
  end
end

private

def should_use_websocket?
  @node.online? && @node.uuid.present?
end

def perform_websocket_uninstall
  report_progress "Agent is online - sending uninstall command via WebSocket"

  ActionCable.server.broadcast("agent_#{@node.uuid}", {
    type: "command",
    action: "uninstall",
    correlation_id: SecureRandom.uuid
  })

  report_progress "Uninstall command sent - agent will self-remove"
end

# Override to skip SSH when using WebSocket
def with_connection(&block)
  if should_use_websocket?
    yield nil
  else
    super
  end
end
```

### 3. Add Deprecation Warnings to Old Services

**Files:**
- `app/services/agent/remote_install_service.rb`
- `app/services/agent/patch_service.rb`
- `app/services/agent/remote_uninstall_service.rb`

Add to each service's `#call` method:

```ruby
def call
  ActiveSupport::Deprecation.warn(
    "Agent::RemoteInstallService is deprecated. Use Agent::InstallService instead.",
    caller
  )
  # ... existing implementation
end
```

### 4. Migrate Callers

Update all call sites to use new services.

**Interface mapping:**

```ruby
# OLD: RemoteInstallService
Agent::RemoteInstallService.new(
  target_host: node.hostname,
  arch: node.arch,
  bastion_host: node.jump_host,
  sudo_password: password,
  local_binary_path: binary_path,
  server_url: server_url,
  agent_token: token,
  node: node
).call

# NEW: InstallService
Agent::InstallService.new(
  node: node,
  server_url: server_url,
  api_token: token,
  binary_path: binary_path,  # or agent_release: release
  cache_key: cache_key       # for credential resolution
).call
```

**Return value change:**
- Old: `Result.new(success:, agent_uuid:)` or `Result.new(success:, message:)`
- New: `Result.new(success:, message:, agent_event:)` - includes audit record

### 5. Remove Old Services (After Migration)

Delete files:
- `app/services/agent/remote_install_service.rb`
- `app/services/agent/patch_service.rb`
- `app/services/agent/remote_uninstall_service.rb`
- `spec/services/agent/remote_install_service_spec.rb`
- `spec/services/agent/patch_service_spec.rb`
- `spec/services/agent/remote_uninstall_service_spec.rb`

## Implementation Plan

| Task | Description |
|------|-------------|
| 1 | Add IP→hostname fallback to `LifecycleService#connect_direct` |
| 2 | Add specs for IP fallback behavior |
| 3 | Add WebSocket uninstall to `UninstallService` |
| 4 | Add specs for WebSocket uninstall |
| 5 | Add deprecation warnings to old services |
| 6 | Identify and migrate all callers |
| 7 | Run full test suite, fix any failures |
| 8 | Remove old services (separate PR after validation) |

## Out of Scope

- CompilerService changes
- AgentRelease/version management changes
- These will be addressed in a future design iteration

## Testing

- Unit tests for IP fallback (mock SSH connection failures)
- Unit tests for WebSocket uninstall path
- Integration tests ensuring callers work with new services
- Verify deprecation warnings appear in logs when old services used
