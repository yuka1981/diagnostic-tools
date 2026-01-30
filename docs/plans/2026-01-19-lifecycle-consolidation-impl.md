# Agent Lifecycle Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate 6 overlapping agent lifecycle services into 3 unified services by adding missing features and deprecating old ones.

**Architecture:** Add IP→hostname fallback to `LifecycleService` base class for all operations. Add WebSocket uninstall path to `UninstallService` for online agents. Add deprecation warnings to old services to track migration progress.

**Tech Stack:** Rails 7.2, RSpec, Net::SSH, ActionCable

---

## Task 1: Add IP→Hostname Fallback to LifecycleService

**Files:**
- Modify: `app/services/agent/lifecycle_service.rb`
- Create: `spec/services/agent/lifecycle_service_spec.rb` (if not exists, or modify)

**Step 1: Write the failing test**

```ruby
# spec/services/agent/lifecycle_service_spec.rb
# Add to existing file or create new

require "rails_helper"

# Concrete test class since LifecycleService is abstract
class TestLifecycleService < Agent::LifecycleService
  def operation_type
    :install
  end

  def execute_operation(_ssh)
    # no-op for testing
  end

  def expected_version
    "test"
  end
end

RSpec.describe Agent::LifecycleService do
  describe "#connect_direct" do
    let(:node) { create(:node, :direct, hostname: "test.example.com", ip: "192.168.1.100") }
    let(:service) { TestLifecycleService.new(node: node) }

    context "when IP connection fails with network error" do
      before do
        # First call fails with timeout, second succeeds
        call_count = 0
        allow(Net::SSH).to receive(:start) do |host, *args, &block|
          call_count += 1
          if call_count == 1 && host == "192.168.1.100"
            raise Errno::ETIMEDOUT, "Connection timed out"
          else
            # Simulate successful connection
            mock_ssh = instance_double(Net::SSH::Connection::Session)
            block.call(mock_ssh) if block
          end
        end
      end

      it "retries with hostname after IP fails" do
        expect(Net::SSH).to receive(:start).with("192.168.1.100", anything, anything).ordered
        expect(Net::SSH).to receive(:start).with("test.example.com", anything, anything).ordered

        # Use send to access private method
        service.send(:with_connection) { |ssh| }
      end

      it "logs the fallback attempt" do
        expect(service).to receive(:report_progress).with(/Connection to 192.168.1.100 failed/)
        service.send(:with_connection) { |ssh| }
      end
    end

    context "when IP connection fails with auth error" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "auth failed")
      end

      it "does not retry with hostname" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |ssh| }
        }.to raise_error(Agent::ConnectionError, /authentication failed/i)
      end
    end

    context "when hostname equals IP" do
      let(:node) { create(:node, :direct, hostname: "192.168.1.100", ip: "192.168.1.100") }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ETIMEDOUT, "Connection timed out")
      end

      it "does not retry since no fallback available" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |ssh| }
        }.to raise_error(Agent::ConnectionError)
      end
    end

    context "when node has no IP (hostname only)" do
      let(:node) { create(:node, :direct, hostname: "test.example.com", ip: nil) }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED, "Connection refused")
      end

      it "does not retry since no fallback available" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |ssh| }
        }.to raise_error(Agent::ConnectionError)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/lifecycle_service_spec.rb --format documentation`
Expected: FAIL - tests fail because fallback logic doesn't exist yet

**Step 3: Implement the IP→hostname fallback**

Replace the `connect_direct` method in `app/services/agent/lifecycle_service.rb`:

```ruby
# In LifecycleService class, replace connect_direct with:

def connect_direct(&block)
  primary_host = @node.ip.presence || @node.hostname
  fallback_host = determine_fallback_host(primary_host)

  begin
    attempt_connection(primary_host, &block)
  rescue ConnectionError => e
    raise unless fallback_host && e.recoverable

    report_progress "Connection to #{primary_host} failed, retrying with #{fallback_host}..."
    attempt_connection(fallback_host, &block)
  end
end

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
    recoverable: false
  )
end

def determine_fallback_host(primary_host)
  return nil if @node.ip.blank?
  return nil if @node.hostname.blank?
  return nil if @node.hostname == @node.ip
  return nil if primary_host == @node.hostname

  @node.hostname
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/lifecycle_service_spec.rb --format documentation`
Expected: PASS - all new tests green

**Step 5: Run full agent service tests**

Run: `bin/rspec spec/services/agent/ --format progress`
Expected: No new failures (existing failures may remain)

**Step 6: Commit**

```bash
git add app/services/agent/lifecycle_service.rb spec/services/agent/lifecycle_service_spec.rb
git commit -m "feat: add IP→hostname fallback to LifecycleService

When SSH connection to node IP fails with a network error (timeout,
unreachable, refused), automatically retry with hostname if different.
Auth failures do not trigger retry."
```

---

## Task 2: Add WebSocket Uninstall to UninstallService

**Files:**
- Modify: `app/services/agent/uninstall_service.rb`
- Create/Modify: `spec/services/agent/uninstall_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/uninstall_service_spec.rb
# Add these tests to existing file

RSpec.describe Agent::UninstallService do
  describe "WebSocket uninstall" do
    let(:node) { create(:node, :direct, hostname: "test-node", uuid: "abc-123") }
    let(:service) { described_class.new(node: node) }

    context "when node is online with UUID" do
      before do
        allow(node).to receive(:online?).and_return(true)
      end

      it "uses WebSocket instead of SSH" do
        expect(Net::SSH).not_to receive(:start)
        expect(ActionCable.server).to receive(:broadcast).with(
          "agent_abc-123",
          hash_including(type: "command", action: "uninstall")
        )

        service.call
      end

      it "includes correlation_id in broadcast" do
        expect(ActionCable.server).to receive(:broadcast) do |channel, payload|
          expect(payload[:correlation_id]).to be_present
          expect(payload[:correlation_id]).to match(/\A[0-9a-f-]{36}\z/)
        end

        service.call
      end

      it "creates AgentEvent with success status" do
        allow(ActionCable.server).to receive(:broadcast)

        expect { service.call }.to change(AgentEvent, :count).by(1)

        event = AgentEvent.last
        expect(event.operation).to eq("uninstall")
        expect(event.status).to eq("success")
      end

      it "reports progress about WebSocket path" do
        allow(ActionCable.server).to receive(:broadcast)

        expect(service).to receive(:report_progress).with(/online.*WebSocket/i).at_least(:once)
        service.call
      end
    end

    context "when node is online but has no UUID" do
      let(:node) { create(:node, :direct, hostname: "test-node", uuid: nil) }

      before do
        allow(node).to receive(:online?).and_return(true)
        allow(Net::SSH).to receive(:start).and_yield(instance_double(Net::SSH::Connection::Session))
        allow(service).to receive(:perform_remote_uninstall)
      end

      it "falls back to SSH" do
        expect(ActionCable.server).not_to receive(:broadcast)
        expect(Net::SSH).to receive(:start)

        service.call rescue nil  # May fail due to mock, that's ok
      end
    end

    context "when node is offline" do
      before do
        allow(node).to receive(:online?).and_return(false)
        allow(Net::SSH).to receive(:start).and_yield(instance_double(Net::SSH::Connection::Session))
        allow(service).to receive(:perform_remote_uninstall)
      end

      it "uses SSH instead of WebSocket" do
        expect(ActionCable.server).not_to receive(:broadcast)
        expect(Net::SSH).to receive(:start)

        service.call rescue nil
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/uninstall_service_spec.rb --format documentation`
Expected: FAIL - WebSocket methods don't exist

**Step 3: Implement WebSocket uninstall**

Modify `app/services/agent/uninstall_service.rb`:

```ruby
# frozen_string_literal: true

require_relative "lifecycle_service"

module Agent
  # Service to uninstall the agent from a remote node
  class UninstallService < LifecycleService
    protected

    def operation_type
      :uninstall
    end

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

    def verify_health(_ssh)
      # No health verification for uninstall
    end

    def finalize
      @node.update_columns(agent_version: nil, source: :manual)
      report_progress "Agent uninstalled successfully"
    end

    def success_message
      "Agent uninstalled successfully"
    end

    def expected_version
      nil
    end

    # Override to skip SSH when using WebSocket
    def with_connection(&block)
      if should_use_websocket?
        yield nil
      else
        super
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

    def perform_local_uninstall
      report_progress "Stopping agent service"
      execute_local_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)

      report_progress "Disabling agent service"
      execute_local_command("systemctl disable #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)

      report_progress "Removing agent binary"
      execute_local_command("rm -f #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak", use_sudo: true)

      report_progress "Removing service file"
      execute_local_command("rm -f /etc/systemd/system/#{SERVICE_NAME}.service /etc/systemd/system/#{SERVICE_NAME}.service.bak", use_sudo: true)

      report_progress "Cleaning up staging files"
      execute_local_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/qis-agent.service", use_sudo: true)

      report_progress "Reloading systemd"
      execute_local_command("systemctl daemon-reload", use_sudo: true)
    end

    def perform_remote_uninstall(ssh)
      report_progress "Stopping agent service"
      cmd = build_remote_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Disabling agent service"
      cmd = build_remote_command("systemctl disable #{SERVICE_NAME} 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Removing agent binary"
      cmd = build_remote_command("rm -f #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Removing service file"
      cmd = build_remote_command("rm -f /etc/systemd/system/#{SERVICE_NAME}.service /etc/systemd/system/#{SERVICE_NAME}.service.bak", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Cleaning up staging files"
      cmd = build_remote_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/qis-agent.service", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Reloading systemd"
      cmd = build_remote_command("systemctl daemon-reload", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/uninstall_service_spec.rb --format documentation`
Expected: PASS - all WebSocket tests green

**Step 5: Run full agent service tests**

Run: `bin/rspec spec/services/agent/ --format progress`
Expected: No new failures

**Step 6: Commit**

```bash
git add app/services/agent/uninstall_service.rb spec/services/agent/uninstall_service_spec.rb
git commit -m "feat: add WebSocket uninstall path for online agents

When an agent is online and has a UUID, send uninstall command directly
via ActionCable instead of using SSH. Falls back to SSH if agent is
offline or has no UUID."
```

---

## Task 3: Add Deprecation Warnings to Old Services

**Files:**
- Modify: `app/services/agent/remote_install_service.rb`
- Modify: `app/services/agent/patch_service.rb`
- Modify: `app/services/agent/remote_uninstall_service.rb`

**Step 1: Add deprecation to RemoteInstallService**

At the start of the `call` method in `app/services/agent/remote_install_service.rb`:

```ruby
def call
  ActiveSupport::Deprecation.warn(
    "Agent::RemoteInstallService is deprecated. Use Agent::InstallService instead. " \
    "Called from: #{caller.first}",
    caller
  )

  if localhost?
    # ... rest of existing code
```

**Step 2: Add deprecation to PatchService**

At the start of the `call` method in `app/services/agent/patch_service.rb`:

```ruby
def call
  ActiveSupport::Deprecation.warn(
    "Agent::PatchService is deprecated. Use Agent::UpdateService instead. " \
    "Called from: #{caller.first}",
    caller
  )

  # Step 0: Safety Check (Critical)
  check_node_busy!
  # ... rest of existing code
```

**Step 3: Add deprecation to RemoteUninstallService**

At the start of the `call` method in `app/services/agent/remote_uninstall_service.rb`:

```ruby
def call
  ActiveSupport::Deprecation.warn(
    "Agent::RemoteUninstallService is deprecated. Use Agent::UninstallService instead. " \
    "Called from: #{caller.first}",
    caller
  )

  if @node&.online?
    # ... rest of existing code
```

**Step 4: Run tests to ensure no breakage**

Run: `bin/rspec spec/services/agent/ --format progress`
Expected: No new failures (deprecation warnings may appear in output)

**Step 5: Commit**

```bash
git add app/services/agent/remote_install_service.rb \
        app/services/agent/patch_service.rb \
        app/services/agent/remote_uninstall_service.rb
git commit -m "chore: add deprecation warnings to old lifecycle services

Warns when using:
- RemoteInstallService → use InstallService
- PatchService → use UpdateService
- RemoteUninstallService → use UninstallService"
```

---

## Task 4: Identify Callers of Old Services

**Step 1: Search for RemoteInstallService callers**

Run: `grep -rn "RemoteInstallService" app/ --include="*.rb" | grep -v "class RemoteInstallService"`

**Step 2: Search for PatchService callers**

Run: `grep -rn "PatchService" app/ --include="*.rb" | grep -v "class PatchService"`

**Step 3: Search for RemoteUninstallService callers**

Run: `grep -rn "RemoteUninstallService" app/ --include="*.rb" | grep -v "class RemoteUninstallService"`

**Step 4: Document findings**

Create a list of files that need migration. Common locations:
- `app/jobs/` - Background jobs
- `app/controllers/` - API/web controllers
- `app/services/` - Orchestrating services

**Step 5: Commit findings (if any documentation created)**

This step is investigative - actual migration depends on what's found.

---

## Task 5: Run Full Test Suite and Lint

**Step 1: Run RuboCop**

Run: `bin/rubocop app/services/agent/ --format github`
Expected: No new offenses (or auto-fixable only)

**Step 2: Auto-fix any offenses**

Run: `bin/rubocop -a app/services/agent/`

**Step 3: Run full agent test suite**

Run: `bin/rspec spec/services/agent/ spec/models/agent_event_spec.rb --format progress`
Expected: Same number of failures as baseline (33)

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "style: fix rubocop offenses in agent lifecycle services"
```

---

## Summary

| Task | Description | Commit Message |
|------|-------------|----------------|
| 1 | IP→hostname fallback | `feat: add IP→hostname fallback to LifecycleService` |
| 2 | WebSocket uninstall | `feat: add WebSocket uninstall path for online agents` |
| 3 | Deprecation warnings | `chore: add deprecation warnings to old lifecycle services` |
| 4 | Identify callers | (investigative - no commit) |
| 5 | Lint and test | `style: fix rubocop offenses` |

After these tasks, the new services will have feature parity with the old ones, and deprecation warnings will help track migration progress.
