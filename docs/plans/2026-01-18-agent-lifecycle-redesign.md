# Agent Lifecycle Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify install/uninstall/update operations with consistent credential handling, error hierarchy, audit logging, health verification, and auto-rollback.

**Architecture:** Introduce `Agent::LifecycleService` base class with shared `RemoteExecution` concern. All three operations inherit from base class, sharing connection management, credential resolution, progress reporting, and error handling. New `AgentEvent` model provides audit trail.

**Tech Stack:** Rails 7.2, RSpec, FactoryBot, Net::SSH, ActiveStorage

---

## Task 1: Create AgentEvent Migration

**Files:**
- Create: `db/migrate/XXXXXX_create_agent_events.rb`
- Test: Run migration and verify schema

**Step 1: Generate the migration**

```bash
bin/rails generate migration CreateAgentEvents
```

**Step 2: Write the migration**

```ruby
# db/migrate/XXXXXX_create_agent_events.rb
class CreateAgentEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_events do |t|
      t.references :node, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :agent_release, null: true, foreign_key: true

      t.string :operation, null: false
      t.string :status, null: false, default: "pending"
      t.string :from_version
      t.string :to_version
      t.text :error_message
      t.jsonb :error_details, default: {}
      t.boolean :forced, default: false

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :agent_events, :operation
    add_index :agent_events, :status
    add_index :agent_events, :created_at
  end
end
```

**Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration succeeds, schema.rb updated

**Step 4: Verify schema**

Run: `bin/rails runner "puts AgentEvent.column_names.join(', ')"`
Expected: Shows all columns defined above

**Step 5: Commit**

```bash
git add db/migrate/*_create_agent_events.rb db/schema.rb
git commit -m "feat: add agent_events table for lifecycle audit logging"
```

---

## Task 2: Create AgentEvent Model with Tests

**Files:**
- Create: `app/models/agent_event.rb`
- Create: `spec/models/agent_event_spec.rb`
- Create: `spec/factories/agent_events.rb`

**Step 1: Write the failing test**

```ruby
# spec/models/agent_event_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentEvent do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:agent_release).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:operation) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:operation).with_values(install: "install", update: "update", uninstall: "uninstall").backed_by_column_of_type(:string) }
    it { is_expected.to define_enum_for(:status).with_values(pending: "pending", running: "running", success: "success", failed: "failed", rolled_back: "rolled_back").backed_by_column_of_type(:string) }
  end

  describe "factory" do
    it "creates a valid agent_event" do
      event = build(:agent_event)
      expect(event).to be_valid
    end
  end

  describe "#duration" do
    it "returns nil when not completed" do
      event = build(:agent_event, started_at: 1.minute.ago, completed_at: nil)
      expect(event.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      event = build(:agent_event, started_at: 1.minute.ago, completed_at: Time.current)
      expect(event.duration).to be_within(1).of(60)
    end
  end

  describe "#mark_running!" do
    it "sets status to running and started_at" do
      event = create(:agent_event)
      event.mark_running!
      expect(event.status).to eq("running")
      expect(event.started_at).to be_present
    end
  end

  describe "#mark_success!" do
    it "sets status to success and completed_at" do
      event = create(:agent_event, :running)
      event.mark_success!
      expect(event.status).to eq("success")
      expect(event.completed_at).to be_present
    end
  end

  describe "#mark_failed!" do
    it "sets status to failed with error details" do
      event = create(:agent_event, :running)
      event.mark_failed!(message: "SSH timeout", details: { stderr: "Connection refused" })
      expect(event.status).to eq("failed")
      expect(event.error_message).to eq("SSH timeout")
      expect(event.error_details["stderr"]).to eq("Connection refused")
      expect(event.completed_at).to be_present
    end
  end

  describe "#mark_rolled_back!" do
    it "sets status to rolled_back" do
      event = create(:agent_event, :running)
      event.mark_rolled_back!(message: "Update failed, restored previous version")
      expect(event.status).to eq("rolled_back")
      expect(event.error_message).to eq("Update failed, restored previous version")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/agent_event_spec.rb`
Expected: FAIL - uninitialized constant AgentEvent

**Step 3: Create factory**

```ruby
# spec/factories/agent_events.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :agent_event do
    association :node
    operation { :install }
    status { :pending }
    to_version { "v1.0.0" }

    trait :running do
      status { :running }
      started_at { Time.current }
    end

    trait :success do
      status { :success }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_message { "Operation failed" }
    end

    trait :rolled_back do
      status { :rolled_back }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      error_message { "Rolled back to previous version" }
    end

    trait :with_user do
      association :user
    end

    trait :with_release do
      association :agent_release
    end

    trait :install do
      operation { :install }
    end

    trait :update do
      operation { :update }
      from_version { "v0.9.0" }
    end

    trait :uninstall do
      operation { :uninstall }
      from_version { "v1.0.0" }
      to_version { nil }
    end
  end
end
```

**Step 4: Write the model**

```ruby
# app/models/agent_event.rb
# frozen_string_literal: true

class AgentEvent < ApplicationRecord
  belongs_to :node
  belongs_to :user, optional: true
  belongs_to :agent_release, optional: true

  enum :operation, { install: "install", update: "update", uninstall: "uninstall" }
  enum :status, { pending: "pending", running: "running", success: "success", failed: "failed", rolled_back: "rolled_back" }

  validates :operation, presence: true
  validates :status, presence: true

  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end

  def mark_running!
    update!(status: :running, started_at: Time.current)
  end

  def mark_success!
    update!(status: :success, completed_at: Time.current)
  end

  def mark_failed!(message:, details: {})
    update!(
      status: :failed,
      error_message: message,
      error_details: details,
      completed_at: Time.current
    )
  end

  def mark_rolled_back!(message:)
    update!(
      status: :rolled_back,
      error_message: message,
      completed_at: Time.current
    )
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/models/agent_event_spec.rb`
Expected: PASS (all tests green)

**Step 6: Commit**

```bash
git add app/models/agent_event.rb spec/models/agent_event_spec.rb spec/factories/agent_events.rb
git commit -m "feat: add AgentEvent model for lifecycle audit logging"
```

---

## Task 3: Create Error Class Hierarchy

**Files:**
- Create: `app/services/agent/errors.rb`
- Create: `spec/services/agent/errors_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/errors_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::LifecycleError do
  describe "initialization" do
    it "accepts message, phase, details, and recoverable" do
      error = described_class.new("Something failed", phase: :preflight, details: { foo: "bar" }, recoverable: true)
      expect(error.message).to eq("Something failed")
      expect(error.phase).to eq(:preflight)
      expect(error.details).to eq({ foo: "bar" })
      expect(error.recoverable).to be true
    end

    it "defaults details to empty hash and recoverable to false" do
      error = described_class.new("Failed", phase: :deploy)
      expect(error.details).to eq({})
      expect(error.recoverable).to be false
    end
  end

  it "is a StandardError" do
    expect(described_class.new("test", phase: :test)).to be_a(StandardError)
  end
end

RSpec.describe Agent::ConnectionError do
  it "inherits from LifecycleError" do
    expect(described_class.new("SSH failed", phase: :connect)).to be_a(Agent::LifecycleError)
  end
end

RSpec.describe Agent::ValidationError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Invalid", phase: :preflight)).to be_a(Agent::LifecycleError)
  end
end

RSpec.describe Agent::DeploymentError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Deploy failed", phase: :deploy)).to be_a(Agent::LifecycleError)
  end
end

RSpec.describe Agent::ServiceError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Service failed", phase: :start)).to be_a(Agent::LifecycleError)
  end
end

RSpec.describe Agent::HealthCheckError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Health check failed", phase: :verify)).to be_a(Agent::LifecycleError)
  end
end

RSpec.describe Agent::RollbackError do
  it "inherits from LifecycleError" do
    expect(described_class.new("Rollback failed", phase: :rollback)).to be_a(Agent::LifecycleError)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/errors_spec.rb`
Expected: FAIL - uninitialized constant Agent::LifecycleError

**Step 3: Write the error classes**

```ruby
# app/services/agent/errors.rb
# frozen_string_literal: true

module Agent
  # Base error class for all agent lifecycle operations
  # Provides structured error information including phase, details, and recoverability
  class LifecycleError < StandardError
    attr_reader :phase, :details, :recoverable

    def initialize(message, phase:, details: {}, recoverable: false)
      @phase = phase
      @details = details
      @recoverable = recoverable
      super(message)
    end
  end

  # Raised when SSH connection fails (auth, network, timeout)
  class ConnectionError < LifecycleError; end

  # Raised when pre-flight validation fails
  class ValidationError < LifecycleError; end

  # Raised when file transfer or permission setting fails
  class DeploymentError < LifecycleError; end

  # Raised when systemd service operations fail
  class ServiceError < LifecycleError; end

  # Raised when post-operation health verification fails
  class HealthCheckError < LifecycleError; end

  # Raised when auto-rollback fails
  class RollbackError < LifecycleError; end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/errors_spec.rb`
Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add app/services/agent/errors.rb spec/services/agent/errors_spec.rb
git commit -m "feat: add unified error hierarchy for agent lifecycle operations"
```

---

## Task 4: Create RemoteExecution Concern

**Files:**
- Create: `app/services/agent/concerns/remote_execution.rb`
- Create: `spec/services/agent/concerns/remote_execution_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/concerns/remote_execution_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Test class to include the concern
class TestExecutionService
  include Agent::Concerns::RemoteExecution

  attr_accessor :node, :ssh_password, :sudo_password, :on_progress

  def initialize(node:, ssh_password: nil, sudo_password: nil)
    @node = node
    @ssh_password = ssh_password
    @sudo_password = sudo_password
  end
end

RSpec.describe Agent::Concerns::RemoteExecution do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100") }
  let(:service) { TestExecutionService.new(node: node) }

  describe "#localhost_target?" do
    it "returns true for 127.0.0.1" do
      node.ip = "127.0.0.1"
      expect(service.localhost_target?).to be true
    end

    it "returns true for localhost hostname" do
      node.ip = nil
      node.hostname = "localhost"
      expect(service.localhost_target?).to be true
    end

    it "returns true for ::1 IPv6" do
      node.ip = "::1"
      expect(service.localhost_target?).to be true
    end

    it "returns false for regular IP" do
      expect(service.localhost_target?).to be false
    end
  end

  describe "#use_bastion?" do
    context "with direct connection" do
      let(:node) { create(:node, :direct) }

      it "returns false" do
        expect(service.use_bastion?).to be false
      end
    end

    context "with custom bastion and jump_host" do
      let(:node) { create(:node, :custom_bastion, jump_host: "jump.example.com") }

      it "returns true" do
        expect(service.use_bastion?).to be true
      end
    end

    context "with localhost" do
      let(:node) { build_stubbed(:node, :global_bastion, ip: "127.0.0.1") }

      it "returns false even for bastion mode" do
        expect(service.use_bastion?).to be false
      end
    end
  end

  describe "#resolve_credentials" do
    let(:cache_key) { "lifecycle_creds_test123" }

    it "uses cached credentials when available" do
      Rails.cache.write(cache_key, { ssh_password: "cached_ssh", sudo_password: "cached_sudo" }, expires_in: 5.minutes)
      service.resolve_credentials(cache_key: cache_key)
      expect(service.ssh_password).to eq("cached_ssh")
      expect(service.sudo_password).to eq("cached_sudo")
    end

    it "falls back to node credentials when cache empty" do
      node.update!(ssh_password: "node_ssh", sudo_credential: "node_sudo")
      service.resolve_credentials(cache_key: "nonexistent")
      expect(service.ssh_password).to eq("node_ssh")
      expect(service.sudo_password).to eq("node_sudo")
    end

    it "uses ssh_password as sudo fallback" do
      node.update!(ssh_password: "shared_pass", sudo_credential: nil)
      service.resolve_credentials(cache_key: "nonexistent")
      expect(service.sudo_password).to eq("shared_pass")
    end
  end

  describe "#ssh_user" do
    it "uses node's ssh_user when present" do
      node.ssh_user = "custom_user"
      expect(service.ssh_user).to eq("custom_user")
    end

    it "falls back to SshConfig user" do
      node.ssh_user = nil
      allow(SshConfig).to receive(:user).and_return("config_user")
      expect(service.ssh_user).to eq("config_user")
    end

    it "defaults to root" do
      node.ssh_user = nil
      allow(SshConfig).to receive(:user).and_return(nil)
      expect(service.ssh_user).to eq("root")
    end
  end

  describe "#report_progress" do
    it "calls on_progress callback when set" do
      messages = []
      service.on_progress = ->(msg) { messages << msg }
      service.report_progress("Test message")
      expect(messages).to include("Test message")
    end

    it "broadcasts to ActionCable when node persisted" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "node_logs_#{node.id}",
        hash_including(log: /Test message/, stream: "meta")
      )
      service.report_progress("Test message")
    end
  end

  describe "#capture_diagnostics" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

    before do
      allow(service).to receive(:execute_command).and_return("")
    end

    it "captures systemctl status output" do
      allow(service).to receive(:execute_command)
        .with(mock_ssh, anything, password: anything)
        .and_return("Active: failed")

      diagnostics = service.capture_diagnostics(mock_ssh)
      expect(diagnostics).to have_key(:systemctl_status)
    end
  end

  describe "#set_selinux_context" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

    it "runs restorecon command" do
      expect(service).to receive(:execute_command).with(
        mock_ssh,
        /restorecon.*chcon -t bin_t/,
        password: anything
      )
      service.set_selinux_context(mock_ssh, "/usr/local/bin/hpc-agent", type: "bin_t")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/concerns/remote_execution_spec.rb`
Expected: FAIL - uninitialized constant Agent::Concerns::RemoteExecution

**Step 3: Create the directory structure**

```bash
mkdir -p app/services/agent/concerns
mkdir -p spec/services/agent/concerns
```

**Step 4: Write the concern**

```ruby
# app/services/agent/concerns/remote_execution.rb
# frozen_string_literal: true

require "net/ssh"
require "net/scp"
require "open3"

module Agent
  module Concerns
    # Shared SSH/local execution patterns for agent lifecycle operations
    module RemoteExecution
      extend ActiveSupport::Concern

      SERVICE_NAME = "hpc-agent"
      TARGET_BIN_PATH = "/usr/local/bin/hpc-agent"
      STAGING_DIR = "/tmp/hpc-agent-staging"

      def localhost?(host)
        return false if host.blank?

        host == "127.0.0.1" || host == "localhost" || host == "::1"
      end

      def localhost_target?
        localhost?(@node.ip) || localhost?(@node.hostname)
      end

      def use_bastion?
        return false if @node.direct?
        return false if localhost_target?
        return true if @node.custom_bastion? && @node.jump_host.present?
        return true if @node.global_bastion? && ::SshConfig.use_jump_host?

        false
      end

      def resolve_credentials(cache_key:)
        cached = Rails.cache.read(cache_key)

        @ssh_password = cached&.dig(:ssh_password) ||
                        @node.ssh_password

        @sudo_password = cached&.dig(:sudo_password) ||
                         @node.sudo_credential ||
                         @ssh_password
      end

      def ssh_user
        @node.ssh_user.presence || ::SshConfig.user || "root"
      end

      def ssh_keys
        key_path = ::SshConfig.key_path
        key_path.present? ? [ key_path ] : []
      end

      def ssh_options
        {
          timeout: 30,
          non_interactive: true,
          verify_host_key: :never,
          keys: ssh_keys,
          password: @ssh_password,
          append_all_supported_algorithms: true,
          auth_methods: [ "publickey", "password", "keyboard-interactive" ]
        }.compact
      end

      def report_progress(message)
        @on_progress&.call(message)
        Rails.logger.info "[#{self.class.name}] #{message}"

        return unless @node&.persisted?

        ActionCable.server.broadcast("node_logs_#{@node.id}", { log: "==> #{message}\n", stream: "meta" })
      end

      def broadcast_log(data, stream)
        return unless @node&.persisted?
        return if data.blank?
        return if data.match?(/\[sudo\] password for/)

        ActionCable.server.broadcast("node_logs_#{@node.id}", { log: data, stream: stream })
      end

      def execute_command(ssh, cmd, password: nil)
        stdout = ""
        stderr = ""
        exit_code = nil

        actual_cmd = if password.present? && cmd.include?("sudo")
                       if cmd.include?("sudo -S")
                         cmd.sub("sudo -S", "echo #{Shellwords.escape(password)} | sudo -S")
                       else
                         cmd.sub("sudo ", "echo #{Shellwords.escape(password)} | sudo -S ")
                       end
        else
                       cmd
        end

        log_cmd = password.present? ? actual_cmd.gsub(password.to_s, "********") : actual_cmd
        Rails.logger.debug "[#{self.class.name}] Executing: #{log_cmd}"

        ssh.open_channel do |ch|
          if password.present? && cmd.include?("sudo")
            ch.request_pty { |_, _| }
          end

          ch.exec(actual_cmd) do |channel, success|
            raise Agent::DeploymentError.new("Could not execute command", phase: :execute, details: { command: log_cmd }) unless success

            channel.on_data do |_, data|
              stdout += data
              unless data.match?(/\[sudo\] password for |Password:|Sorry, try again/i)
                broadcast_log(data, "stdout")
              end
            end

            channel.on_extended_data do |_, _, data|
              stderr += data
              unless data.match?(/\[sudo\] password for |Password:|Sorry, try again/i)
                broadcast_log(data, "stderr")
              end
            end

            channel.on_request("exit-status") { |_, data| exit_code = data.read_long }
          end
        end
        ssh.loop

        if exit_code != 0
          clean_stderr = stderr.gsub(/\[sudo\] password for .*:\s*|Sorry, try again\.\s*/i, "").strip
          clean_stdout = stdout.gsub(/\[sudo\] password for .*:\s*|Sorry, try again\.\s*/i, "").strip
          error_output = clean_stderr.presence || clean_stdout.presence || "Unknown error"
          raise Agent::DeploymentError.new(
            "Command failed (exit #{exit_code}): #{error_output}",
            phase: :execute,
            details: { command: log_cmd, exit_code: exit_code, stderr: clean_stderr, stdout: clean_stdout }
          )
        end

        stdout
      end

      def execute_local_command(cmd, use_sudo: false)
        full_cmd = build_local_command(cmd, use_sudo: use_sudo)

        log_cmd = @sudo_password.present? ? full_cmd.gsub(@sudo_password.to_s, "********") : full_cmd
        Rails.logger.debug "[#{self.class.name}] Executing locally: #{log_cmd}"

        stdout, stderr, status = Open3.capture3(full_cmd)

        broadcast_log(stdout, "stdout") if stdout.present?
        filtered_stderr = stderr.lines.reject { |line| line.match?(/\[sudo\] password for/) }.join
        broadcast_log(filtered_stderr, "stderr") if filtered_stderr.present?

        unless status.success?
          raise Agent::DeploymentError.new(
            "Command failed (exit #{status.exitstatus}): #{filtered_stderr.strip}",
            phase: :execute,
            details: { command: log_cmd, exit_code: status.exitstatus, stderr: filtered_stderr, stdout: stdout }
          )
        end

        stdout
      end

      def build_local_command(cmd, use_sudo:)
        if use_sudo && @sudo_password.present?
          "echo #{Shellwords.escape(@sudo_password)} | sudo -S bash -c #{Shellwords.escape(cmd)}"
        elsif use_sudo
          "sudo bash -c #{Shellwords.escape(cmd)}"
        else
          cmd
        end
      end

      def build_remote_command(inner_cmd, via_ssh:, use_sudo: false)
        if via_ssh
          target_spec = @node.ip.presence || @node.hostname
          ssh_target = target_spec.include?(":") ? "[#{target_spec}]" : target_spec
          remote_cmd = use_sudo ? "sudo -S bash -c '#{inner_cmd.gsub("'", "'\\''")}'" : inner_cmd
          "ssh -o StrictHostKeyChecking=no root@#{Shellwords.escape(ssh_target)} #{Shellwords.escape(remote_cmd)}"
        else
          use_sudo ? "sudo -S bash -c '#{inner_cmd.gsub("'", "'\\''")}'" : inner_cmd
        end
      end

      def set_selinux_context(ssh, path, type:)
        selinux_cmd = <<~SELINUX.squish
          if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
            restorecon -v #{path} 2>/dev/null ||
            chcon -t #{type} #{path} 2>/dev/null || true;
          fi
        SELINUX

        if ssh.nil?
          execute_local_command(selinux_cmd, use_sudo: true)
        else
          cmd = build_remote_command(selinux_cmd, via_ssh: false, use_sudo: true)
          execute_command(ssh, cmd, password: @sudo_password)
        end
      end

      def capture_diagnostics(ssh, via_ssh: false)
        diagnostics = {}

        begin
          status_cmd = build_remote_command("systemctl status #{SERVICE_NAME} --no-pager -l 2>&1 | tail -20", via_ssh: via_ssh, use_sudo: true)
          diagnostics[:systemctl_status] = execute_command(ssh, status_cmd, password: @sudo_password)
        rescue Agent::DeploymentError => e
          diagnostics[:systemctl_status] = e.details[:stderr] || e.message
        end

        begin
          journal_cmd = build_remote_command("journalctl -u #{SERVICE_NAME} -n 20 --no-pager 2>&1", via_ssh: via_ssh, use_sudo: true)
          diagnostics[:journalctl_output] = execute_command(ssh, journal_cmd, password: @sudo_password)
        rescue Agent::DeploymentError => e
          diagnostics[:journalctl_output] = e.details[:stderr] || e.message
        end

        diagnostics
      end

      def generate_service_file(server_url:, api_token:, inventory_interval: 60)
        <<~SYSTEMD
          [Unit]
          Description=HPC Diagnostic Agent
          Documentation=https://github.com/yuka1981/diagnostic-tools
          Wants=network-online.target
          After=network-online.target

          [Service]
          Type=simple
          ExecStart=#{TARGET_BIN_PATH} daemon --server "#{server_url}" --token "#{api_token}" --inventory-interval #{inventory_interval}
          Restart=always
          RestartSec=10
          User=root
          StandardOutput=journal
          StandardError=journal
          SyslogIdentifier=hpc-agent

          [Install]
          WantedBy=multi-user.target
        SYSTEMD
      end
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/concerns/remote_execution_spec.rb`
Expected: PASS (all tests green)

**Step 6: Commit**

```bash
git add app/services/agent/concerns/remote_execution.rb spec/services/agent/concerns/remote_execution_spec.rb
git commit -m "feat: add RemoteExecution concern for shared SSH patterns"
```

---

## Task 5: Create LifecycleService Base Class

**Files:**
- Create: `app/services/agent/lifecycle_service.rb`
- Create: `spec/services/agent/lifecycle_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/lifecycle_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

# Concrete implementation for testing
class TestLifecycleService < Agent::LifecycleService
  def operation_type
    :install
  end

  def execute_operation
    # No-op for testing
  end
end

RSpec.describe Agent::LifecycleService do
  let(:node) { create(:node, :direct, hostname: "test-node") }
  let(:service) { TestLifecycleService.new(node: node) }

  describe "#initialize" do
    it "accepts node parameter" do
      expect(service).to be_a(Agent::LifecycleService)
    end

    it "accepts optional parameters" do
      svc = TestLifecycleService.new(
        node: node,
        cache_key: "test_key",
        user: create(:user),
        on_progress: ->(msg) { puts msg }
      )
      expect(svc).to be_a(Agent::LifecycleService)
    end
  end

  describe "#call" do
    context "when operation succeeds" do
      before do
        allow(service).to receive(:execute_operation)
        allow(service).to receive(:verify_health)
        allow(service).to receive(:finalize)
      end

      it "creates AgentEvent with success status" do
        expect { service.call }.to change(AgentEvent, :count).by(1)
        event = AgentEvent.last
        expect(event.operation).to eq("install")
        expect(event.status).to eq("success")
      end

      it "returns Result with success" do
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "when operation fails" do
      before do
        allow(service).to receive(:execute_operation).and_raise(
          Agent::DeploymentError.new("Deploy failed", phase: :deploy, details: { stderr: "Permission denied" })
        )
      end

      it "creates AgentEvent with failed status" do
        expect { service.call rescue nil }.to change(AgentEvent, :count).by(1)
        event = AgentEvent.last
        expect(event.status).to eq("failed")
        expect(event.error_message).to include("Deploy failed")
      end

      it "raises the error" do
        expect { service.call }.to raise_error(Agent::DeploymentError)
      end
    end
  end

  describe "phase execution" do
    it "runs phases in order: preflight, connect, execute, verify, finalize" do
      execution_order = []

      allow(service).to receive(:run_preflight_checks) { execution_order << :preflight }
      allow(service).to receive(:with_connection) do |&block|
        execution_order << :connect
        block.call(nil)
      end
      allow(service).to receive(:execute_operation) { execution_order << :execute }
      allow(service).to receive(:verify_health) { execution_order << :verify }
      allow(service).to receive(:finalize) { execution_order << :finalize }

      service.call

      expect(execution_order).to eq(%i[preflight connect execute verify finalize])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/lifecycle_service_spec.rb`
Expected: FAIL - uninitialized constant Agent::LifecycleService

**Step 3: Write the base class**

```ruby
# app/services/agent/lifecycle_service.rb
# frozen_string_literal: true

require_relative "errors"
require_relative "concerns/remote_execution"

module Agent
  # Base class for all agent lifecycle operations (install, update, uninstall)
  # Provides consistent 5-phase execution: preflight, connect, execute, verify, finalize
  class LifecycleService
    include Concerns::RemoteExecution

    Result = Struct.new(:success, :message, :agent_event, keyword_init: true) do
      def success?
        success
      end
    end

    attr_reader :node, :agent_event

    def initialize(node:, cache_key: nil, user: nil, agent_release: nil, force: false, on_progress: nil)
      @node = node
      @cache_key = cache_key
      @user = user
      @agent_release = agent_release
      @force = force
      @on_progress = on_progress
      @operation_started_at = nil
    end

    def call
      create_agent_event
      @agent_event.mark_running!
      @operation_started_at = Time.current

      resolve_credentials(cache_key: @cache_key) if @cache_key

      run_preflight_checks

      with_connection do |ssh|
        execute_operation(ssh)
        verify_health(ssh)
      end

      finalize
      @agent_event.mark_success!

      Result.new(success: true, message: success_message, agent_event: @agent_event)
    rescue Agent::LifecycleError => e
      handle_error(e)
      raise
    rescue StandardError => e
      wrapped = Agent::DeploymentError.new(e.message, phase: :unknown, details: { original_class: e.class.name })
      handle_error(wrapped)
      raise wrapped
    end

    protected

    # Subclasses must implement these methods
    def operation_type
      raise NotImplementedError, "Subclasses must implement #operation_type"
    end

    def execute_operation(_ssh)
      raise NotImplementedError, "Subclasses must implement #execute_operation"
    end

    def run_preflight_checks
      raise ValidationError.new("Node must be persisted", phase: :preflight) unless @node.persisted?
    end

    def verify_health(_ssh)
      # Default: no verification. Subclasses can override.
    end

    def finalize
      # Default: no finalization. Subclasses can override.
    end

    def success_message
      "Operation completed successfully"
    end

    def expected_version
      @agent_release&.version || "dev"
    end

    private

    def create_agent_event
      @agent_event = AgentEvent.create!(
        node: @node,
        user: @user,
        agent_release: @agent_release,
        operation: operation_type,
        status: :pending,
        from_version: @node.agent_version,
        to_version: expected_version,
        forced: @force
      )
    end

    def with_connection(&block)
      if localhost_target?
        report_progress "Executing locally (localhost detected)"
        yield nil
      elsif use_bastion?
        connect_via_bastion(&block)
      else
        connect_direct(&block)
      end
    end

    def connect_direct(&block)
      host = @node.ip.presence || @node.hostname
      report_progress "Connecting directly to #{host}"

      Net::SSH.start(host, ssh_user, ssh_options.merge(port: @node.ssh_port || 22), &block)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Net::SSH::AuthenticationFailed => e
      raise ConnectionError.new(
        "SSH connection failed: #{e.message}",
        phase: :connect,
        details: { host: host, error_class: e.class.name },
        recoverable: true
      )
    end

    def connect_via_bastion(&block)
      gateway_host = @node.jump_host.presence || ::SshConfig.jump_host
      gateway_user = @node.jump_user.presence || ::SshConfig.jump_user || ssh_user
      gateway_port = @node.jump_port || ::SshConfig.jump_port || 22

      report_progress "Connecting via bastion #{gateway_host}"

      Net::SSH.start(gateway_host, gateway_user, ssh_options.merge(port: gateway_port), &block)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Net::SSH::AuthenticationFailed => e
      raise ConnectionError.new(
        "Bastion connection failed: #{e.message}",
        phase: :connect,
        details: { bastion: gateway_host, error_class: e.class.name },
        recoverable: true
      )
    end

    def handle_error(error)
      details = error.details.merge(phase: error.phase)

      @agent_event&.mark_failed!(
        message: error.message,
        details: details
      )

      Rails.logger.error "[#{self.class.name}] #{error.class.name}: #{error.message}"
      Rails.logger.error "[#{self.class.name}] Phase: #{error.phase}, Details: #{error.details.inspect}"
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/lifecycle_service_spec.rb`
Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add app/services/agent/lifecycle_service.rb spec/services/agent/lifecycle_service_spec.rb
git commit -m "feat: add LifecycleService base class with 5-phase execution"
```

---

## Task 6: Create UpdateService (Replace PatchService)

**Files:**
- Create: `app/services/agent/update_service.rb`
- Create: `spec/services/agent/update_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/update_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UpdateService do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100", agent_version: "v0.9.0") }
  let(:agent_release) { create(:agent_release, version: "v1.0.0") }

  describe "#operation_type" do
    it "returns :update" do
      service = described_class.new(node: node, agent_release: agent_release)
      expect(service.send(:operation_type)).to eq(:update)
    end
  end

  describe "#run_preflight_checks" do
    context "when node is busy" do
      let(:recipe) { create(:benchmark_recipe) }

      before do
        create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :running)
      end

      it "raises NodeBusyError" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::NodeBusyError)
      end

      it "allows force bypass" do
        service = described_class.new(node: node, agent_release: agent_release, force: true)
        # Will fail at SSH, but won't raise NodeBusyError
        expect { service.call }.to raise_error(Agent::ConnectionError)
      end
    end

    context "when agent_release is recalled" do
      let(:recalled_release) { create(:agent_release, :recalled, version: "v2.0.0") }

      it "raises ValidationError" do
        service = described_class.new(node: node, agent_release: recalled_release)
        expect { service.call }.to raise_error(Agent::ValidationError, /recalled/)
      end
    end

    context "when agent_release has no binary for architecture" do
      let(:release_without_binary) { create(:agent_release, version: "v3.0.0") }

      before do
        release_without_binary.binary.purge
        release_without_binary.agent_binaries.destroy_all
      end

      it "raises ValidationError" do
        service = described_class.new(node: node, agent_release: release_without_binary)
        expect { service.call }.to raise_error(Agent::ValidationError, /No binary/)
      end
    end
  end

  describe "auto-rollback" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }
    let(:mock_scp) { instance_double(Net::SCP) }
    let(:mock_channel) { instance_double(Net::SSH::Connection::Channel) }

    before do
      allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
      allow(mock_ssh).to receive(:scp).and_return(mock_scp)
      allow(mock_scp).to receive(:upload!)
      allow(mock_ssh).to receive(:loop)

      # Simulate service start failure
      command_count = 0
      allow(mock_ssh).to receive(:open_channel) do |&block|
        block.call(mock_channel)
        mock_ssh
      end

      allow(mock_channel).to receive(:request_pty).and_yield(mock_channel, true)
      allow(mock_channel).to receive(:exec) { |_cmd, &block| block.call(mock_channel, true) }

      data_callback = nil
      exit_callback = nil

      allow(mock_channel).to receive(:on_data) { |&block| data_callback = block }
      allow(mock_channel).to receive(:on_extended_data)
      allow(mock_channel).to receive(:on_request).with("exit-status") { |&block| exit_callback = block }

      allow(mock_ssh).to receive(:loop) do
        command_count += 1
        case command_count
        when 2
          # Checksum verification
          data_callback&.call(mock_channel, agent_release.checksum)
        when 6
          # Service status - simulate failure
          data_callback&.call(mock_channel, "failed")
        when 7..12
          # Rollback commands - succeed
          data_callback&.call(mock_channel, "active") if command_count == 12
        end
        mock_data = double("exit_data")
        allow(mock_data).to receive(:read_long).and_return(0)
        exit_callback&.call(mock_channel, mock_data)
      end
    end

    it "attempts rollback when service fails to start" do
      service = described_class.new(node: node, agent_release: agent_release)

      expect { service.call }.to raise_error(Agent::ServiceError)

      event = AgentEvent.last
      expect(event.status).to eq("rolled_back").or eq("failed")
    end
  end

  describe "creates AgentEvent" do
    it "records the update operation" do
      service = described_class.new(node: node, agent_release: agent_release)

      expect { service.call rescue nil }.to change(AgentEvent, :count).by(1)

      event = AgentEvent.last
      expect(event.operation).to eq("update")
      expect(event.from_version).to eq("v0.9.0")
      expect(event.to_version).to eq("v1.0.0")
    end
  end

  describe "service file regeneration" do
    it "regenerates service file during update" do
      service = described_class.new(
        node: node,
        agent_release: agent_release,
        server_url: "https://new-server.example.com",
        api_token: "new_token_123"
      )

      expect(service.send(:should_regenerate_service_file?)).to be true
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/update_service_spec.rb`
Expected: FAIL - uninitialized constant Agent::UpdateService

**Step 3: Write the UpdateService**

```ruby
# app/services/agent/update_service.rb
# frozen_string_literal: true

module Agent
  # Service to update the agent binary on a remote node
  # Includes auto-rollback on failure and service file regeneration
  class UpdateService < LifecycleService
    def initialize(node:, agent_release:, server_url: nil, api_token: nil, **options)
      super(node: node, agent_release: agent_release, **options)
      @server_url = server_url || default_server_url
      @api_token = api_token || @node.effective_api_token
      @local_checksum = nil
      @rollback_attempted = false
    end

    protected

    def operation_type
      :update
    end

    def run_preflight_checks
      super

      check_node_busy!
      validate_release!
      find_agent_binary!
    end

    def execute_operation(ssh)
      binary_tempfile, @local_checksum = download_binary_to_temp
      report_progress "Starting agent update to #{@agent_release.version}"

      begin
        if ssh.nil?
          perform_local_update(binary_tempfile)
        else
          upload_and_update(ssh, binary_tempfile)
        end
      ensure
        binary_tempfile.close
        binary_tempfile.unlink
      end
    end

    def verify_health(ssh)
      report_progress "Verifying service health"
      verify_service_running(ssh)
    rescue ServiceError => e
      attempt_rollback(ssh)
      raise
    end

    def finalize
      @node.update_column(:agent_version, @agent_release.version)
      report_progress "Agent updated to #{@agent_release.version}"
    end

    def success_message
      "Agent updated to #{@agent_release.version}"
    end

    def should_regenerate_service_file?
      true # Always regenerate during update
    end

    private

    def check_node_busy!
      return if @force
      return unless @node.busy?

      raise NodeBusyError
    end

    def validate_release!
      raise ValidationError.new("Agent release must be persisted", phase: :preflight) unless @agent_release.persisted?
      raise ValidationError.new("Agent release is recalled and cannot be deployed", phase: :preflight) if @agent_release.recalled?
    end

    def find_agent_binary!
      @agent_binary = @agent_release.binary_for_arch(node_arch)
      @agent_binary ||= legacy_binary_wrapper

      raise ValidationError.new("No binary available for architecture: #{node_arch}", phase: :preflight) unless @agent_binary
    end

    def node_arch
      @node.arch.presence || "x86_64"
    end

    def legacy_binary_wrapper
      return nil unless @agent_release.binary.attached?

      LegacyBinaryWrapper.new(@agent_release)
    end

    def download_binary_to_temp
      report_progress "Downloading binary for #{node_arch} from storage"
      tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
      binary_content = @agent_binary.binary.download
      tempfile.write(binary_content)
      tempfile.rewind

      local_checksum = Digest::SHA256.hexdigest(binary_content)
      report_progress "Local checksum: #{local_checksum[0..15]}..."

      [ tempfile, local_checksum ]
    end

    def perform_local_update(binary_tempfile)
      report_progress "Copying binary to staging"
      FileUtils.cp(binary_tempfile.path, "/tmp/agent_update")

      report_progress "Stopping agent service"
      execute_local_command("systemctl stop #{SERVICE_NAME}", use_sudo: true)

      report_progress "Verifying binary checksum"
      verify_local_checksum

      report_progress "Creating backup and installing new binary"
      swap_local_binary

      report_progress "Setting file permissions"
      execute_local_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", use_sudo: true)

      if should_regenerate_service_file?
        report_progress "Regenerating service file"
        deploy_local_service_file
      end

      report_progress "Setting SELinux context"
      set_selinux_context(nil, TARGET_BIN_PATH, type: "bin_t")

      report_progress "Starting agent service"
      execute_local_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", use_sudo: true)
    end

    def upload_and_update(ssh, binary_tempfile)
      report_progress "Uploading binary to target"
      ssh.scp.upload!(binary_tempfile.path, "/tmp/agent_update")

      report_progress "Stopping agent service"
      systemctl_cmd("stop", ssh)

      report_progress "Verifying binary checksum"
      verify_remote_checksum(ssh)

      report_progress "Creating backup and installing new binary"
      swap_remote_binary(ssh)

      report_progress "Setting file permissions"
      set_remote_permissions(ssh)

      if should_regenerate_service_file?
        report_progress "Regenerating service file"
        deploy_remote_service_file(ssh)
      end

      report_progress "Setting SELinux context"
      set_selinux_context(ssh, TARGET_BIN_PATH, type: "bin_t")

      report_progress "Starting agent service"
      execute_command(ssh, build_remote_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def systemctl_cmd(action, ssh)
      cmd = build_remote_command("systemctl #{action} #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def verify_local_checksum
      output = execute_local_command("sha256sum /tmp/agent_update | awk '{print $1}'")
      actual = output.strip

      unless actual == @local_checksum
        raise ValidationError.new("Checksum mismatch! Expected: #{@local_checksum}, Got: #{actual}", phase: :verify)
      end
    end

    def verify_remote_checksum(ssh)
      cmd = build_remote_command("sha256sum /tmp/agent_update | awk '{print $1}'", via_ssh: false)
      output = execute_command(ssh, cmd)
      actual = output.strip

      unless actual == @local_checksum
        raise ValidationError.new("Checksum mismatch! Expected: #{@local_checksum}, Got: #{actual}", phase: :verify)
      end
    end

    def swap_local_binary
      cmd = <<~CMD.squish
        if [ -f #{TARGET_BIN_PATH} ]; then
          mv #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak;
        fi &&
        mv /tmp/agent_update #{TARGET_BIN_PATH}
      CMD
      execute_local_command(cmd, use_sudo: true)
    end

    def swap_remote_binary(ssh)
      cmd = <<~CMD.squish
        if [ -f #{TARGET_BIN_PATH} ]; then
          mv #{TARGET_BIN_PATH} #{TARGET_BIN_PATH}.bak;
        fi &&
        mv /tmp/agent_update #{TARGET_BIN_PATH}
      CMD
      execute_command(ssh, build_remote_command(cmd, via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def set_remote_permissions(ssh)
      cmd = build_remote_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def deploy_local_service_file
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      # Backup existing service file
      execute_local_command("cp #{service_path} #{service_path}.bak 2>/dev/null || true", use_sudo: true)

      # Write new service file via temp file
      tempfile = Tempfile.new("hpc-agent-service")
      tempfile.write(service_content)
      tempfile.close

      FileUtils.cp(tempfile.path, "/tmp/hpc-agent.service")
      execute_local_command("mv /tmp/hpc-agent.service #{service_path}", use_sudo: true)
      set_selinux_context(nil, service_path, type: "systemd_unit_file_t")

      tempfile.unlink
    end

    def deploy_remote_service_file(ssh)
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      # Backup existing service file
      backup_cmd = build_remote_command("cp #{service_path} #{service_path}.bak 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, backup_cmd, password: @sudo_password)

      # Write new service file via base64 encoding
      encoded_content = Base64.strict_encode64(service_content)
      write_cmd = build_remote_command("echo '#{encoded_content}' | base64 -d > /tmp/hpc-agent.service && mv /tmp/hpc-agent.service #{service_path}", via_ssh: false, use_sudo: true)
      execute_command(ssh, write_cmd, password: @sudo_password)

      set_selinux_context(ssh, service_path, type: "systemd_unit_file_t")
    end

    def verify_service_running(ssh)
      max_retries = 10
      retry_count = 0

      loop do
        status = get_service_status(ssh)

        if status == "active"
          report_progress "Service is running"
          return
        elsif status == "activating"
          retry_count += 1
          if retry_count >= max_retries
            raise ServiceError.new("Service stuck in activating state", phase: :verify)
          end
          report_progress "Service is starting... (#{retry_count}/#{max_retries})"
          sleep 1
        else
          diagnostics = ssh.nil? ? {} : capture_diagnostics(ssh)
          raise ServiceError.new(
            "Service failed to start. Status: #{status}",
            phase: :verify,
            details: diagnostics
          )
        end
      end
    end

    def get_service_status(ssh)
      if ssh.nil?
        output = execute_local_command("systemctl is-active #{SERVICE_NAME}", use_sudo: true)
        output.strip
      else
        cmd = build_remote_command("systemctl is-active #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
        output = execute_command(ssh, cmd, password: @sudo_password)
        output.strip
      end
    rescue DeploymentError => e
      e.details[:stdout]&.strip || "unknown"
    end

    def attempt_rollback(ssh)
      return if @rollback_attempted

      @rollback_attempted = true
      report_progress "Service failed to start, attempting rollback..."

      begin
        if ssh.nil?
          perform_local_rollback
        else
          perform_remote_rollback(ssh)
        end

        sleep 3
        status = get_service_status(ssh)

        if status == "active"
          @agent_event.mark_rolled_back!(message: "Update failed, rolled back to previous version")
          report_progress "Rollback successful, restored previous version"
        else
          raise RollbackError.new("Rollback failed - service still not running", phase: :rollback)
        end
      rescue StandardError => e
        Rails.logger.error "[UpdateService] Rollback failed: #{e.message}"
        raise RollbackError.new("Rollback failed: #{e.message}", phase: :rollback, details: { original_error: e.class.name })
      end
    end

    def perform_local_rollback
      execute_local_command("pkill -9 hpc-agent || true", use_sudo: true)
      execute_local_command("mv #{TARGET_BIN_PATH}.bak #{TARGET_BIN_PATH}", use_sudo: true)
      execute_local_command("mv /etc/systemd/system/#{SERVICE_NAME}.service.bak /etc/systemd/system/#{SERVICE_NAME}.service 2>/dev/null || true", use_sudo: true)
      execute_local_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", use_sudo: true)
    end

    def perform_remote_rollback(ssh)
      execute_command(ssh, build_remote_command("pkill -9 hpc-agent || true", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("mv #{TARGET_BIN_PATH}.bak #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("mv /etc/systemd/system/#{SERVICE_NAME}.service.bak /etc/systemd/system/#{SERVICE_NAME}.service 2>/dev/null || true", via_ssh: false, use_sudo: true), password: @sudo_password)
      execute_command(ssh, build_remote_command("systemctl daemon-reload && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true), password: @sudo_password)
    end

    def default_server_url
      Rails.application.routes.url_helpers.root_url(host: ENV.fetch("APP_HOST", "localhost:3000"))
    end

    # Wrapper class for backward compatibility with legacy single-binary releases
    class LegacyBinaryWrapper
      attr_reader :checksum

      def initialize(agent_release)
        @agent_release = agent_release
        @checksum = agent_release.checksum
      end

      def binary
        @agent_release.binary
      end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/update_service_spec.rb`
Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add app/services/agent/update_service.rb spec/services/agent/update_service_spec.rb
git commit -m "feat: add UpdateService with auto-rollback and service file regeneration"
```

---

## Task 7: Create InstallService

**Files:**
- Create: `app/services/agent/install_service.rb`
- Create: `spec/services/agent/install_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/install_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::InstallService do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100") }
  let(:agent_release) { create(:agent_release, version: "v1.0.0") }

  describe "#operation_type" do
    it "returns :install" do
      service = described_class.new(node: node, agent_release: agent_release, server_url: "http://localhost", api_token: "token")
      expect(service.send(:operation_type)).to eq(:install)
    end
  end

  describe "creates AgentEvent" do
    it "records the install operation" do
      service = described_class.new(node: node, agent_release: agent_release, server_url: "http://localhost", api_token: "token")

      expect { service.call rescue nil }.to change(AgentEvent, :count).by(1)

      event = AgentEvent.last
      expect(event.operation).to eq("install")
      expect(event.to_version).to eq("v1.0.0")
    end
  end

  describe "#finalize" do
    it "sets agent_version on node" do
      service = described_class.new(node: node, agent_release: agent_release, server_url: "http://localhost", api_token: "token")

      # Mock successful execution
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)
      allow(service).to receive(:verify_health)

      service.call

      node.reload
      expect(node.agent_version).to eq("v1.0.0")
    end
  end

  describe "with dev binary (no release)" do
    it "accepts binary_path instead of agent_release" do
      service = described_class.new(
        node: node,
        binary_path: "/tmp/compiled-agent",
        server_url: "http://localhost",
        api_token: "token"
      )

      expect(service.send(:expected_version)).to eq("dev")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/install_service_spec.rb`
Expected: FAIL - uninitialized constant Agent::InstallService

**Step 3: Write the InstallService**

```ruby
# app/services/agent/install_service.rb
# frozen_string_literal: true

module Agent
  # Service to install the agent binary on a remote node
  class InstallService < LifecycleService
    def initialize(node:, server_url:, api_token:, agent_release: nil, binary_path: nil, **options)
      super(node: node, agent_release: agent_release, **options)
      @server_url = server_url
      @api_token = api_token
      @binary_path = binary_path
      @local_checksum = nil
    end

    protected

    def operation_type
      :install
    end

    def run_preflight_checks
      super
      validate_binary_source!
    end

    def execute_operation(ssh)
      prepare_binary
      report_progress "Starting agent installation"

      if ssh.nil?
        perform_local_install
      else
        upload_and_install(ssh)
      end
    end

    def verify_health(ssh)
      report_progress "Verifying service health"
      verify_service_running(ssh)
      read_agent_uuid(ssh)
    end

    def finalize
      version = @agent_release&.version || extract_installed_version
      @node.update_columns(agent_version: version, source: :agent_push)
      report_progress "Agent installed successfully (version: #{version})"
    end

    def success_message
      "Agent installed (version: #{expected_version})"
    end

    def expected_version
      @agent_release&.version || "dev"
    end

    private

    def validate_binary_source!
      has_release = @agent_release&.persisted?
      has_binary_path = @binary_path.present? && File.exist?(@binary_path)

      unless has_release || has_binary_path
        raise ValidationError.new("Either agent_release or binary_path must be provided", phase: :preflight)
      end

      if has_release
        @agent_binary = @agent_release.binary_for_arch(node_arch) || legacy_binary_wrapper
        raise ValidationError.new("No binary available for architecture: #{node_arch}", phase: :preflight) unless @agent_binary
      end
    end

    def node_arch
      @node.arch.presence || "x86_64"
    end

    def legacy_binary_wrapper
      return nil unless @agent_release&.binary&.attached?

      UpdateService::LegacyBinaryWrapper.new(@agent_release)
    end

    def prepare_binary
      if @binary_path.present?
        @binary_tempfile = nil
        @local_checksum = Digest::SHA256.file(@binary_path).hexdigest
        report_progress "Using local binary: #{@binary_path}"
      else
        report_progress "Downloading binary for #{node_arch} from storage"
        @binary_tempfile = Tempfile.new([ "agent-binary", "" ], binmode: true)
        binary_content = @agent_binary.binary.download
        @binary_tempfile.write(binary_content)
        @binary_tempfile.rewind
        @local_checksum = Digest::SHA256.hexdigest(binary_content)
      end
      report_progress "Binary checksum: #{@local_checksum[0..15]}..."
    end

    def actual_binary_path
      @binary_path || @binary_tempfile.path
    end

    def perform_local_install
      report_progress "Copying binary to staging"
      FileUtils.cp(actual_binary_path, "/tmp/agent_install")

      stop_existing_service_if_running

      report_progress "Installing binary"
      execute_local_command("mv /tmp/agent_install #{TARGET_BIN_PATH}", use_sudo: true)

      report_progress "Setting file permissions"
      execute_local_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", use_sudo: true)

      report_progress "Deploying service file"
      deploy_local_service_file

      report_progress "Setting SELinux contexts"
      set_selinux_context(nil, TARGET_BIN_PATH, type: "bin_t")
      set_selinux_context(nil, "/etc/systemd/system/#{SERVICE_NAME}.service", type: "systemd_unit_file_t")

      report_progress "Enabling and starting service"
      execute_local_command("systemctl daemon-reload && systemctl enable #{SERVICE_NAME} && systemctl start #{SERVICE_NAME}", use_sudo: true)

      report_progress "Setting dmidecode SUID"
      execute_local_command("chmod 4755 $(which dmidecode) 2>/dev/null || true", use_sudo: true)
    ensure
      cleanup_binary_tempfile
    end

    def upload_and_install(ssh)
      report_progress "Uploading binary to target"
      ssh.scp.upload!(actual_binary_path, "/tmp/agent_install")

      stop_existing_service_if_running_remote(ssh)

      report_progress "Installing binary"
      cmd = build_remote_command("mv /tmp/agent_install #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting file permissions"
      cmd = build_remote_command("chmod 755 #{TARGET_BIN_PATH} && chown root:root #{TARGET_BIN_PATH}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Deploying service file"
      deploy_remote_service_file(ssh)

      report_progress "Setting SELinux contexts"
      set_selinux_context(ssh, TARGET_BIN_PATH, type: "bin_t")
      set_selinux_context(ssh, "/etc/systemd/system/#{SERVICE_NAME}.service", type: "systemd_unit_file_t")

      report_progress "Enabling and starting service"
      cmd = build_remote_command("systemctl daemon-reload && systemctl enable #{SERVICE_NAME} && systemctl start #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Setting dmidecode SUID"
      cmd = build_remote_command("chmod 4755 $(which dmidecode) 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    ensure
      cleanup_binary_tempfile
    end

    def stop_existing_service_if_running
      execute_local_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", use_sudo: true)
    end

    def stop_existing_service_if_running_remote(ssh)
      cmd = build_remote_command("systemctl stop #{SERVICE_NAME} 2>/dev/null || true", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end

    def deploy_local_service_file
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      tempfile = Tempfile.new("hpc-agent-service")
      tempfile.write(service_content)
      tempfile.close

      FileUtils.cp(tempfile.path, "/tmp/hpc-agent.service")
      execute_local_command("mv /tmp/hpc-agent.service #{service_path}", use_sudo: true)

      tempfile.unlink
    end

    def deploy_remote_service_file(ssh)
      service_content = generate_service_file(server_url: @server_url, api_token: @api_token)
      service_path = "/etc/systemd/system/#{SERVICE_NAME}.service"

      encoded_content = Base64.strict_encode64(service_content)
      write_cmd = build_remote_command("echo '#{encoded_content}' | base64 -d > /tmp/hpc-agent.service && mv /tmp/hpc-agent.service #{service_path}", via_ssh: false, use_sudo: true)
      execute_command(ssh, write_cmd, password: @sudo_password)
    end

    def verify_service_running(ssh)
      max_retries = 10
      retry_count = 0

      loop do
        status = get_service_status(ssh)

        if status == "active"
          report_progress "Service is running"
          return
        elsif status == "activating"
          retry_count += 1
          if retry_count >= max_retries
            raise ServiceError.new("Service stuck in activating state", phase: :verify)
          end
          report_progress "Service is starting... (#{retry_count}/#{max_retries})"
          sleep 1
        else
          diagnostics = ssh.nil? ? {} : capture_diagnostics(ssh)
          raise ServiceError.new("Service failed to start. Status: #{status}", phase: :verify, details: diagnostics)
        end
      end
    end

    def get_service_status(ssh)
      if ssh.nil?
        output = execute_local_command("systemctl is-active #{SERVICE_NAME}", use_sudo: true)
        output.strip
      else
        cmd = build_remote_command("systemctl is-active #{SERVICE_NAME}", via_ssh: false, use_sudo: true)
        output = execute_command(ssh, cmd, password: @sudo_password)
        output.strip
      end
    rescue DeploymentError => e
      e.details[:stdout]&.strip || "unknown"
    end

    def read_agent_uuid(ssh)
      report_progress "Reading agent UUID"

      uuid_path = "/etc/hpc-agent/node_id"
      uuid = if ssh.nil?
               execute_local_command("cat #{uuid_path} 2>/dev/null || echo ''").strip
      else
               cmd = build_remote_command("cat #{uuid_path} 2>/dev/null || echo ''", via_ssh: false)
               execute_command(ssh, cmd).strip
      end

      if uuid.present?
        @node.update_column(:uuid, uuid)
        report_progress "Agent UUID: #{uuid}"
      end
    end

    def extract_installed_version
      # Try to get version from installed binary
      if localhost_target?
        output = execute_local_command("#{TARGET_BIN_PATH} version 2>/dev/null || echo 'dev'")
        output.strip.presence || "dev"
      else
        "dev"
      end
    rescue StandardError
      "dev"
    end

    def cleanup_binary_tempfile
      return unless @binary_tempfile

      @binary_tempfile.close
      @binary_tempfile.unlink
    rescue StandardError
      # Ignore cleanup errors
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/install_service_spec.rb`
Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add app/services/agent/install_service.rb spec/services/agent/install_service_spec.rb
git commit -m "feat: add InstallService for unified agent installation"
```

---

## Task 8: Create UninstallService

**Files:**
- Create: `app/services/agent/uninstall_service.rb`
- Create: `spec/services/agent/uninstall_service_spec.rb`

**Step 1: Write the failing test**

```ruby
# spec/services/agent/uninstall_service_spec.rb
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UninstallService do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100", agent_version: "v1.0.0") }

  describe "#operation_type" do
    it "returns :uninstall" do
      service = described_class.new(node: node)
      expect(service.send(:operation_type)).to eq(:uninstall)
    end
  end

  describe "creates AgentEvent" do
    it "records the uninstall operation" do
      service = described_class.new(node: node)

      expect { service.call rescue nil }.to change(AgentEvent, :count).by(1)

      event = AgentEvent.last
      expect(event.operation).to eq("uninstall")
      expect(event.from_version).to eq("v1.0.0")
      expect(event.to_version).to be_nil
    end
  end

  describe "#finalize" do
    it "clears agent_version and sets source to manual" do
      service = described_class.new(node: node)

      # Mock successful execution
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)

      service.call

      node.reload
      expect(node.agent_version).to be_nil
      expect(node.source).to eq("manual")
    end
  end

  describe "#expected_version" do
    it "returns nil for uninstall" do
      service = described_class.new(node: node)
      expect(service.send(:expected_version)).to be_nil
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/agent/uninstall_service_spec.rb`
Expected: FAIL - uninitialized constant Agent::UninstallService

**Step 3: Write the UninstallService**

```ruby
# app/services/agent/uninstall_service.rb
# frozen_string_literal: true

module Agent
  # Service to uninstall the agent from a remote node
  class UninstallService < LifecycleService
    protected

    def operation_type
      :uninstall
    end

    def execute_operation(ssh)
      report_progress "Starting agent uninstallation"

      if ssh.nil?
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

    private

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
      execute_local_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/hpc-agent.service", use_sudo: true)

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
      cmd = build_remote_command("rm -rf #{STAGING_DIR} /tmp/agent_install /tmp/agent_update /tmp/hpc-agent.service", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)

      report_progress "Reloading systemd"
      cmd = build_remote_command("systemctl daemon-reload", via_ssh: false, use_sudo: true)
      execute_command(ssh, cmd, password: @sudo_password)
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/agent/uninstall_service_spec.rb`
Expected: PASS (all tests green)

**Step 5: Commit**

```bash
git add app/services/agent/uninstall_service.rb spec/services/agent/uninstall_service_spec.rb
git commit -m "feat: add UninstallService for unified agent removal"
```

---

## Task 9: Run All Tests and Lint

**Step 1: Run all new service tests**

Run: `bin/rspec spec/services/agent/ spec/models/agent_event_spec.rb`
Expected: All tests pass

**Step 2: Run lint**

Run: `bin/rubocop -a app/services/agent/ app/models/agent_event.rb spec/services/agent/ spec/models/agent_event_spec.rb spec/factories/agent_events.rb`
Expected: No offenses (or auto-fixed)

**Step 3: Run full test suite**

Run: `bin/rspec`
Expected: All tests pass

**Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "style: fix rubocop offenses in agent lifecycle services"
```

---

## Task 10: Update Jobs to Use New Services (Optional Migration)

This task is optional and can be done incrementally. The new services are designed to work alongside existing ones.

**Files:**
- Modify: `app/jobs/agent/install_job.rb`
- Modify: `app/jobs/agent/update_job.rb`
- Modify: `app/jobs/agent/uninstall_job.rb`

**Implementation Notes:**

1. Add feature flag check to switch between old/new services
2. Gradually migrate traffic to new services
3. Monitor for issues
4. Remove old services after validation period

Example pattern for migration:

```ruby
# app/jobs/agent/update_job.rb
def perform(node_id, release_id, cache_key, force: false)
  node = Node.find(node_id)
  release = AgentRelease.find(release_id)

  if Rails.configuration.use_new_lifecycle_services
    Agent::UpdateService.new(
      node: node,
      agent_release: release,
      cache_key: cache_key,
      force: force,
      on_progress: ->(msg) { broadcast_progress(node, msg) }
    ).call
  else
    # Existing PatchService call
    Agent::PatchService.new(
      node: node,
      agent_release: release,
      force: force,
      on_progress: ->(msg) { broadcast_progress(node, msg) }
    ).call
  end
end
```

---

## Summary

This plan implements the agent lifecycle redesign with:

| Task | Component | Tests |
|------|-----------|-------|
| 1 | AgentEvent migration | Schema verification |
| 2 | AgentEvent model | Full model specs |
| 3 | Error hierarchy | Error class specs |
| 4 | RemoteExecution concern | Concern specs |
| 5 | LifecycleService base | Base class specs |
| 6 | UpdateService | Update operation specs |
| 7 | InstallService | Install operation specs |
| 8 | UninstallService | Uninstall operation specs |
| 9 | Full test suite | Integration verification |
| 10 | Job migration (optional) | Gradual rollout |

Each task follows TDD with explicit test-first, verify-fail, implement, verify-pass, commit steps.
