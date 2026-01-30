# Node UUID Workflow Redesign

## Problem

`InstallService` fails with "missing keyword: :node_uuid" because it doesn't pass the node's UUID to `generate_service_file`. Additionally, the UUID workflow was inconsistent - sometimes server-generated, sometimes read from agent.

## Design Decisions

1. **Node UUID is server-authoritative** - Generated at node creation (already implemented via `before_validation :generate_uuid`)

2. **Server writes UUID to agent** - During install, the server writes `@node.uuid` to `/etc/qis-agent/node_id` on the target

3. **Never read UUID from agent** - Remove `read_agent_uuid` method that overwrote server UUID

4. **Only InstallService writes service file** - UpdateService should only update the binary, not regenerate the service file

## Data Flow

```
Node created → UUID generated (server, SecureRandom.uuid)
     ↓
Install starts → @node.uuid available
     ↓
Write UUID to /etc/qis-agent/node_id on target
     ↓
Deploy service file with --node-uuid flag
     ↓
Agent starts with consistent UUID
```

## File Changes

### InstallService (`app/services/agent/install_service.rb`)

1. Add `node_uuid: @node.uuid` to `generate_service_file` calls in:
   - `deploy_local_service_file`
   - `deploy_remote_service_file`

2. Replace `read_agent_uuid` with `write_agent_uuid`:
   ```ruby
   def write_agent_uuid(ssh)
     report_progress "Writing node UUID"
     uuid_path = "/etc/qis-agent/node_id"

     if ssh.nil?
       execute_local_command("mkdir -p /etc/qis-agent", use_sudo: true)
       execute_local_command("echo '#{@node.uuid}' > #{uuid_path}", use_sudo: true)
     else
       cmd = build_remote_command(
         "mkdir -p /etc/qis-agent && echo '#{@node.uuid}' > #{uuid_path}",
         via_ssh: false, use_sudo: true
       )
       execute_command(ssh, cmd, password: @sudo_password)
     end
   end
   ```

3. Update execution flow:
   - Call `write_agent_uuid` before `deploy_*_service_file`
   - Remove `read_agent_uuid` call from `verify_health`

### UpdateService (`app/services/agent/update_service.rb`)

Remove service file regeneration:

1. Delete methods:
   - `should_regenerate_service_file?`
   - `deploy_local_service_file`
   - `deploy_remote_service_file`

2. Remove regeneration calls from:
   - `perform_local_update`
   - `upload_and_update`

## Test Updates

- `spec/services/agent/install_service_spec.rb` - Test `write_agent_uuid` instead of `read_agent_uuid`
- `spec/services/agent/update_service_spec.rb` - Remove service file regeneration tests
