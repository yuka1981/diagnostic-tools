# **FEATURE REQUEST: HPC Agent Lifecycle Redesign**

**Status**: Draft
**Priority**: High
**Target Version**: v1.0.x
**Dependencies**: `Agent::RemoteInstallService`, `Agent::PatchService`, `Agent::RemoteUninstallService`

## **1. Context & Goal**

The current install/uninstall/update logic for qis-agent has grown organically and contains significant inconsistencies:

| Area | Install | Update (Patch) | Uninstall |
|------|---------|----------------|-----------|
| Version tracking | Sets `"dev"` hardcoded | Sets from release record | Sets `nil` |
| Credential handling | `sudo_password` only | `ssh_password` + `sudo_password` with fallback | `sudo_password` only |
| Service file | Creates new | No modification | Removes |
| SELinux handling | Full context setup | Binary only | N/A |
| Error handling | SSH-specific errors | systemctl/journalctl detail | Minimal |
| Progress reporting | Task-based | Step-based callbacks | Step enum |

**Key Problems**:
1. Version appears as "dev" after install until agent heartbeat updates it
2. Patch operation doesn't update service file (stale server URL/token)
3. Credential handling differs between operations
4. No rollback mechanism when patch fails
5. Health verification is minimal (only systemd status check)
6. No audit trail for lifecycle events

**Goal**: Redesign the agent lifecycle operations with:
- Unified service architecture sharing common patterns
- Consistent credential handling across all operations
- Service file regeneration during updates
- Auto-rollback on patch failure
- Comprehensive health verification
- Database audit logging

## **2. Database Schema Changes**

### **2.1 New Model: `AgentEvent`**

Audit log for all agent lifecycle operations.

* **Table**: `agent_events`
* **Columns**:
  * `node_id`: bigint, foreign key (required)
  * `user_id`: bigint, foreign key (nullable - nil for system jobs)
  * `agent_release_id`: bigint, foreign key (nullable - for install/update)
  * `operation`: string, enum (`install`, `update`, `uninstall`)
  * `status`: string, enum (`pending`, `running`, `success`, `failed`, `rolled_back`)
  * `from_version`: string (previous version, for update)
  * `to_version`: string (target version)
  * `error_message`: text (human-readable failure summary)
  * `error_details`: jsonb (structured: stdout, stderr, systemctl output, journalctl)
  * `forced`: boolean (bypassed busy check?)
  * `started_at`: datetime
  * `completed_at`: datetime
  * `created_at`, `updated_at`: timestamps

**Indexes**:
- `index_agent_events_on_node_id`
- `index_agent_events_on_user_id`
- `index_agent_events_on_operation`
- `index_agent_events_on_status`
- `index_agent_events_on_created_at`

### **2.2 Migration for Node Model**

Ensure `last_heartbeat_at` column exists for health verification:

```ruby
add_column :nodes, :last_heartbeat_at, :datetime unless column_exists?(:nodes, :last_heartbeat_at)
add_index :nodes, :last_heartbeat_at
```

## **3. Architecture Design**

### **3.1 Unified Service Hierarchy**

```
Agent::LifecycleService (base class)
  ├── Agent::InstallService    (install binary + create service)
  ├── Agent::UpdateService     (swap binary + regenerate service)
  └── Agent::UninstallService  (remove binary + service)
```

### **3.2 Shared Module: `Agent::Concerns::RemoteExecution`**

Extracts common SSH/local execution patterns:

```ruby
module Agent
  module Concerns
    module RemoteExecution
      extend ActiveSupport::Concern

      # Unified connection handling (localhost, direct, bastion)
      def with_connection(&block)

      # Execute command with proper credential handling
      def execute_remote_command(cmd, sudo: false)

      # File upload with progress reporting
      def upload_file(local_path, remote_path, &progress_callback)

      # SELinux context setting
      def set_selinux_context(path, type:)

      # Consistent error capture
      def capture_diagnostics
    end
  end
end
```

### **3.3 Unified Error Hierarchy**

```ruby
module Agent
  class LifecycleError < StandardError
    attr_reader :phase, :details, :recoverable

    def initialize(message, phase:, details: {}, recoverable: false)
      @phase = phase
      @details = details
      @recoverable = recoverable
      super(message)
    end
  end

  class ConnectionError < LifecycleError; end      # SSH auth/network failures
  class ValidationError < LifecycleError; end      # Pre-flight check failures
  class DeploymentError < LifecycleError; end      # File transfer/permission issues
  class ServiceError < LifecycleError; end         # systemd start/stop failures
  class HealthCheckError < LifecycleError; end     # Post-operation verification failures
  class RollbackError < LifecycleError; end        # Rollback itself failed
end
```

## **4. Functional Requirements**

### **4.1 Unified 5-Phase Operation Flow**

All operations follow a consistent phase pattern:

#### **Phase 1: Pre-flight Checks**
- Validate node exists in database
- Test SSH connectivity (ping or SSH test)
- For update: Check node not busy (unless `force: true`)
- For update: Validate release exists, not recalled, has matching architecture
- Acquire credentials from cache or node record with fallback chain

#### **Phase 2: Connection & Preparation**
- Establish SSH connection (direct or via bastion)
- Create staging directory: `/tmp/qis-agent-staging/`
- Upload required files to staging location
- Verify checksums match on target

#### **Phase 3: Execute Operation**

**Install**:
```
1. Stop existing service (if upgrading from manual install)
2. Deploy binary to /usr/local/bin/qis-agent
3. Set permissions (755) and ownership (root:root)
4. Deploy systemd service file
5. Set SELinux contexts (bin_t, systemd_unit_file_t)
6. Enable and start systemd service
7. Read agent UUID from /etc/qis-agent/node_id
```

**Update**:
```
1. Stop current service
2. Backup current binary to /usr/local/bin/qis-agent.bak
3. Backup current service file to /etc/systemd/system/qis-agent.service.bak
4. Deploy new binary
5. Set permissions (755) and ownership (root:root)
6. Deploy regenerated service file (current server URL/token)
7. Set SELinux contexts
8. Start new service
9. On failure: trigger auto-rollback
```

**Uninstall**:
```
1. Stop service
2. Disable service
3. Remove binary (/usr/local/bin/qis-agent)
4. Remove service file (/etc/systemd/system/qis-agent.service)
5. Clean up staging files
6. Reload systemd daemon
7. Clear node.agent_version
```

#### **Phase 4: Health Verification**

Full 4-step verification (configurable timeout, default 30s):

```ruby
def verify_health(expected_version:, timeout: 30.seconds)
  # Step 1: Systemd status check
  status = execute_remote_command("systemctl is-active qis-agent")
  raise HealthCheckError.new("Service not active", phase: :systemd) unless status.strip == "active"

  # Step 2: Process running check
  pid = execute_remote_command("pidof qis-agent || pgrep -x qis-agent")
  raise HealthCheckError.new("Process not found", phase: :process) if pid.blank?

  # Step 3: Version match check
  version_output = execute_remote_command("/usr/local/bin/qis-agent version 2>/dev/null || echo unknown")
  unless version_output.include?(expected_version) || expected_version == "dev"
    raise HealthCheckError.new("Version mismatch: expected #{expected_version}, got #{version_output}", phase: :version)
  end

  # Step 4: Heartbeat check (wait for agent to report)
  deadline = Time.current + timeout
  loop do
    break if node.reload.last_heartbeat_at&.> @operation_started_at
    raise HealthCheckError.new("Heartbeat timeout", phase: :heartbeat) if Time.current > deadline
    sleep 2
  end
end
```

#### **Phase 5: Finalization**
- Update node record (`agent_version`, `uuid` if install)
- Create `AgentEvent` audit record with full details
- Clean up staging/temp files
- Broadcast completion status to UI via ActionCable

### **4.2 Credential Handling**

Unified credential chain for all operations:

```ruby
def resolve_credentials
  # Priority order:
  # 1. Cached credentials from form submission (5-min TTL)
  # 2. Node's stored credentials
  # 3. Environment defaults

  cached = Rails.cache.read("lifecycle_creds_#{@node.id}")

  @ssh_password = cached&.dig(:ssh_password) ||
                  @node.ssh_password ||
                  ENV['SSH_DEFAULT_PASSWORD']

  @sudo_password = cached&.dig(:sudo_password) ||
                   @node.sudo_credential ||
                   @ssh_password  # fallback to SSH password
end
```

All operations support:
- `ssh_password`: For SSH authentication (if key auth fails)
- `sudo_password`: For privilege escalation (falls back to ssh_password)
- Bastion credentials: `bastion_password` for jump host

### **4.3 Auto-Rollback (Update Only)**

When service fails to start after binary swap:

```ruby
def attempt_rollback
  Rails.logger.warn "[Agent::UpdateService] Service failed to start, attempting rollback..."

  # 1. Kill any hung process
  execute_remote_command("pkill -9 qis-agent || true", sudo: true)

  # 2. Restore binary
  execute_remote_command("mv /usr/local/bin/qis-agent.bak /usr/local/bin/qis-agent", sudo: true)

  # 3. Restore service file
  execute_remote_command("mv /etc/systemd/system/qis-agent.service.bak /etc/systemd/system/qis-agent.service", sudo: true)

  # 4. Reload and restart
  execute_remote_command("systemctl daemon-reload", sudo: true)
  execute_remote_command("systemctl start qis-agent", sudo: true)

  # 5. Verify old service is healthy
  sleep 3
  status = execute_remote_command("systemctl is-active qis-agent")

  if status.strip == "active"
    @agent_event.update!(status: :rolled_back, error_message: "Update failed, rolled back to previous version")
  else
    raise RollbackError.new("Rollback failed - manual intervention required", phase: :rollback)
  end
end
```

### **4.4 Service File Generation**

Unified service file template used by both Install and Update:

```ruby
def generate_service_file
  <<~SYSTEMD
    [Unit]
    Description=HPC Diagnostic Agent
    Documentation=https://github.com/yuka1981/diagnostic-tools
    Wants=network-online.target
    After=network-online.target

    [Service]
    Type=simple
    ExecStart=/usr/local/bin/qis-agent daemon --server "#{@server_url}" --token "#{@api_token}" --inventory-interval #{@inventory_interval}
    Restart=always
    RestartSec=10
    User=root
    StandardOutput=journal
    StandardError=journal
    SyslogIdentifier=qis-agent

    [Install]
    WantedBy=multi-user.target
  SYSTEMD
end
```

### **4.5 Version Tracking Consistency**

All operations derive version from consistent source:

| Operation | Version Source | After Health Check |
|-----------|---------------|-------------------|
| Install (release) | `release.version` | Verify matches |
| Install (dev compile) | Query `qis-agent version` | Record actual |
| Update | `release.version` | Verify matches |
| Uninstall | N/A | Set `nil` |

```ruby
def determine_version
  if @agent_release
    @expected_version = @agent_release.version
  else
    # Dev compile - query the binary
    @expected_version = extract_version_from_binary(@binary_path)
  end
end

def extract_version_from_binary(path)
  output = `#{path} version 2>/dev/null`.strip
  output.presence || "dev"
end
```

## **5. Technical Implementation Strategy**

### **5.1 File Structure**

```
app/services/agent/
├── lifecycle_service.rb          # Base class
├── concerns/
│   └── remote_execution.rb       # Shared SSH/execution module
├── install_service.rb            # Replaces RemoteInstallService
├── update_service.rb             # Replaces PatchService
├── uninstall_service.rb          # Replaces RemoteUninstallService
└── errors.rb                     # Error class hierarchy
```

### **5.2 Migration Path**

1. Create new services alongside existing ones
2. Add feature flag to switch between old/new implementations
3. Deprecate old services once new ones are validated
4. Remove old services in subsequent release

### **5.3 Job Updates**

Update background jobs to use new services:

```ruby
# app/jobs/agent/install_job.rb
class Agent::InstallJob < ApplicationJob
  def perform(node_id, cache_key)
    node = Node.find(node_id)
    credentials = Rails.cache.read("lifecycle_creds_#{cache_key}")

    Agent::InstallService.new(
      node: node,
      release: AgentRelease.latest_active,
      credentials: credentials,
      on_progress: ->(step, message) { broadcast_progress(node, step, message) }
    ).call
  end
end
```

### **5.4 Controller Updates**

Standardize cache key namespace:

```ruby
# All lifecycle operations use same namespace
cache_key = SecureRandom.hex(16)
Rails.cache.write(
  "lifecycle_creds_#{cache_key}",
  { ssh_password:, sudo_password:, bastion_password: },
  expires_in: 5.minutes
)
```

## **6. UI Requirements**

### **6.1 Agent Events View**

New page showing audit log for a node:

- Filter by operation type (install/update/uninstall)
- Filter by status (success/failed/rolled_back)
- Show timeline with expandable details
- Display error diagnostics for failed operations

### **6.2 Progress Indicators**

Unified progress steps across all operations:

```javascript
const LIFECYCLE_STEPS = {
  preflight: "Running pre-flight checks",
  connecting: "Establishing connection",
  uploading: "Uploading files",
  deploying: "Deploying agent",
  verifying: "Verifying health",
  finalizing: "Finalizing"
};
```

### **6.3 Error Display**

When operation fails, show:
- Phase where failure occurred
- Error message summary
- Expandable section with full diagnostics (stdout, stderr, systemctl, journalctl)
- For rolled_back status: indicate rollback was successful

## **7. Testing Strategy**

### **7.1 Unit Tests**

- Test each phase independently with mocked SSH connections
- Test credential resolution chain
- Test error handling for each error type
- Test rollback logic with various failure scenarios

### **7.2 Integration Tests**

- Test full lifecycle: install -> update -> uninstall
- Test rollback scenario with intentionally broken binary
- Test health verification with slow-starting agent

### **7.3 System Tests (Capybara)**

- Test UI progress indicators
- Test error display
- Test audit log viewing

## **8. Operations Guide**

### **8.1 Monitoring**

Query audit events for operations:

```ruby
# Failed operations in last 24 hours
AgentEvent.where(status: :failed).where("created_at > ?", 24.hours.ago)

# Nodes with rollback events
AgentEvent.where(status: :rolled_back).includes(:node).map(&:node).uniq

# Average operation duration by type
AgentEvent.where(status: :success)
          .group(:operation)
          .average("EXTRACT(EPOCH FROM (completed_at - started_at))")
```

### **8.2 Troubleshooting**

When operation fails, check `AgentEvent.error_details`:

```ruby
event = AgentEvent.find(id)
puts event.error_details["stderr"]
puts event.error_details["systemctl_status"]
puts event.error_details["journalctl_output"]
```

### **8.3 Manual Rollback**

If auto-rollback fails and manual intervention is needed:

```bash
# On target node
sudo systemctl stop qis-agent
sudo mv /usr/local/bin/qis-agent.bak /usr/local/bin/qis-agent
sudo mv /etc/systemd/system/qis-agent.service.bak /etc/systemd/system/qis-agent.service
sudo systemctl daemon-reload
sudo systemctl start qis-agent
sudo systemctl status qis-agent
```

## **9. Success Criteria**

- [ ] All three operations use unified base class and shared module
- [ ] Credential handling is consistent (ssh_password + sudo_password)
- [ ] Update operation regenerates service file
- [ ] Auto-rollback triggers on update failure
- [ ] 4-step health verification passes for all operations
- [ ] All operations create AgentEvent audit records
- [ ] Version tracking is accurate (no more "dev" after release install)
- [ ] Existing tests pass with new implementation
- [ ] New integration tests cover lifecycle scenarios
