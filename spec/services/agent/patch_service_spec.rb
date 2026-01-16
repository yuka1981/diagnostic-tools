# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::PatchService do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100") }
  let(:agent_release) { create(:agent_release, version: "v1.0.0") }
  let(:recipe) { create(:benchmark_recipe) }

  describe Agent::NodeBusyError do
    it "has a default message" do
      error = Agent::NodeBusyError.new
      expect(error.message).to eq("Update blocked: Node is currently busy (Pending/Running tasks).")
    end

    it "can have a custom message" do
      error = Agent::NodeBusyError.new("Custom message")
      expect(error.message).to eq("Custom message")
    end

    it "is a StandardError" do
      expect(Agent::NodeBusyError.new).to be_a(StandardError)
    end
  end

  describe Agent::PatchService::PatchError do
    it "is a StandardError" do
      expect(Agent::PatchService::PatchError.new("test")).to be_a(StandardError)
    end

    it "stores the message" do
      error = Agent::PatchService::PatchError.new("Something went wrong")
      expect(error.message).to eq("Something went wrong")
    end
  end

  describe "#call" do
    context "safety checks" do
      context "when node is busy with pending tasks" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
        end

        it "raises NodeBusyError" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::NodeBusyError)
        end

        it "includes descriptive message in error" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::NodeBusyError, /currently busy/)
        end

        it "does not raise error when force is true" do
          service = described_class.new(node: node, agent_release: agent_release, force: true)
          # Will fail at SSH connection, but won't raise NodeBusyError
          expect { service.call }.to raise_error(Agent::PatchService::PatchError)
        end

        it "bypasses safety check with force flag" do
          service = described_class.new(node: node, agent_release: agent_release, force: true)
          expect { service.call }.not_to raise_error(Agent::NodeBusyError)
        end
      end

      context "when node is busy with running tasks" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :running)
        end

        it "raises NodeBusyError" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::NodeBusyError)
        end

        it "allows force update" do
          service = described_class.new(node: node, agent_release: agent_release, force: true)
          expect { service.call }.not_to raise_error(Agent::NodeBusyError)
        end
      end

      context "when node has multiple busy tasks" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending)
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :running)
        end

        it "raises NodeBusyError" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::NodeBusyError)
        end
      end

      context "when node is idle (only completed tasks)" do
        before do
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :success)
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :failed)
          create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :cancelled)
        end

        it "proceeds with update (will fail at SSH connection in test)" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::PatchService::PatchError)
        end

        it "does not raise NodeBusyError" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.not_to raise_error(Agent::NodeBusyError)
        end
      end

      context "when node has no benchmark runs" do
        it "proceeds with update" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.to raise_error(Agent::PatchService::PatchError)
        end

        it "does not raise NodeBusyError" do
          service = described_class.new(node: node, agent_release: agent_release)
          expect { service.call }.not_to raise_error(Agent::NodeBusyError)
        end
      end
    end

    context "prerequisite validation" do
      it "raises error if node is not persisted" do
        unpersisted_node = build(:node)
        service = described_class.new(node: unpersisted_node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /must be persisted/)
      end

      it "raises error if agent_release is not persisted" do
        unpersisted_release = build(:agent_release)
        service = described_class.new(node: node, agent_release: unpersisted_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /must be persisted/)
      end

      it "raises error if agent_release has no binary attached" do
        release_without_binary = create(:agent_release, version: "v2.0.0")
        release_without_binary.binary.purge
        service = described_class.new(node: node, agent_release: release_without_binary)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /must have a binary/)
      end

      it "raises error if agent_release is recalled" do
        recalled_release = create(:agent_release, :recalled, version: "v3.0.0")
        service = described_class.new(node: node, agent_release: recalled_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /recalled/)
      end

      it "allows deprecated releases" do
        deprecated_release = create(:agent_release, :deprecated, version: "v4.0.0")
        service = described_class.new(node: node, agent_release: deprecated_release)
        # Should fail at SSH, not at validation
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Update failed/)
      end

      it "allows active releases" do
        active_release = create(:agent_release, version: "v5.0.0")
        service = described_class.new(node: node, agent_release: active_release)
        # Should fail at SSH, not at validation
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Update failed/)
      end
    end

    context "progress callback" do
      it "calls on_progress with status messages" do
        messages = []
        service = described_class.new(
          node: node,
          agent_release: agent_release,
          on_progress: ->(msg) { messages << msg }
        )

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end

        expect(messages).to include(/Starting agent update/)
        expect(messages).to include(/Downloading binary/)
      end

      it "includes version in progress message" do
        messages = []
        service = described_class.new(
          node: node,
          agent_release: agent_release,
          on_progress: ->(msg) { messages << msg }
        )

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end

        expect(messages.first).to include("v1.0.0")
      end

      it "includes hostname in progress message" do
        messages = []
        service = described_class.new(
          node: node,
          agent_release: agent_release,
          on_progress: ->(msg) { messages << msg }
        )

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end

        expect(messages.first).to include("test-node")
      end

      it "handles nil on_progress callback" do
        service = described_class.new(
          node: node,
          agent_release: agent_release,
          on_progress: nil
        )

        # Should not raise any errors related to nil callback
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end

    context "SSH connection errors" do
      it "wraps connection errors in PatchError" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Update failed/)
      end

      it "logs the error" do
        service = described_class.new(node: node, agent_release: agent_release)

        expect(Rails.logger).to receive(:error).at_least(:once)

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end
      end
    end

    context "ActionCable broadcasting" do
      it "broadcasts progress to node channel" do
        service = described_class.new(node: node, agent_release: agent_release)

        expect(ActionCable.server).to receive(:broadcast).at_least(:once).with(
          "node_logs_#{node.id}",
          hash_including(:log, :stream)
        )

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end
      end
    end

    context "binary download" do
      it "downloads binary content from ActiveStorage" do
        service = described_class.new(node: node, agent_release: agent_release)

        # The binary should be downloaded during the call
        expect(agent_release.binary).to receive(:download).and_call_original

        begin
          service.call
        rescue Agent::PatchService::PatchError
          # Expected
        end
      end
    end
  end

  describe "Result struct" do
    it "responds to success?" do
      result = Agent::PatchService::Result.new(success: true, message: "Done")
      expect(result.success?).to be true
    end

    it "returns false for failed result" do
      result = Agent::PatchService::Result.new(success: false, message: "Failed")
      expect(result.success?).to be false
    end

    it "stores the message" do
      result = Agent::PatchService::Result.new(success: true, message: "Agent updated")
      expect(result.message).to eq("Agent updated")
    end

    it "allows keyword initialization" do
      result = Agent::PatchService::Result.new(success: true, message: "Test")
      expect(result).to be_a(Agent::PatchService::Result)
    end

    it "can access success attribute directly" do
      result = Agent::PatchService::Result.new(success: true, message: "Test")
      expect(result.success).to be true
    end
  end

  describe "constants" do
    it "defines TARGET_BIN_PATH" do
      expect(Agent::PatchService::TARGET_BIN_PATH).to eq("/usr/local/bin/hpc-agent")
    end

    it "defines SERVICE_NAME" do
      expect(Agent::PatchService::SERVICE_NAME).to eq("hpc-agent")
    end
  end

  describe "initialization" do
    it "accepts node parameter" do
      service = described_class.new(node: node, agent_release: agent_release)
      expect(service).to be_a(Agent::PatchService)
    end

    it "accepts agent_release parameter" do
      service = described_class.new(node: node, agent_release: agent_release)
      expect(service).to be_a(Agent::PatchService)
    end

    it "accepts force parameter defaulting to false" do
      service = described_class.new(node: node, agent_release: agent_release)
      expect(service).to be_a(Agent::PatchService)
    end

    it "accepts force: true parameter" do
      service = described_class.new(node: node, agent_release: agent_release, force: true)
      expect(service).to be_a(Agent::PatchService)
    end

    it "accepts on_progress callback" do
      callback = ->(msg) { puts msg }
      service = described_class.new(node: node, agent_release: agent_release, on_progress: callback)
      expect(service).to be_a(Agent::PatchService)
    end
  end

  describe "node connection types" do
    context "with direct connection node" do
      let(:direct_node) { create(:node, :direct, hostname: "direct-node") }

      it "attempts direct SSH connection" do
        service = described_class.new(node: direct_node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end

    context "with global bastion node" do
      let(:bastion_node) { create(:node, :global_bastion, hostname: "bastion-node") }

      before do
        allow(SshConfig).to receive(:use_jump_host?).and_return(true)
        allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
      end

      it "attempts bastion SSH connection" do
        service = described_class.new(node: bastion_node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end

    context "with custom bastion node" do
      let(:custom_bastion_node) do
        create(:node, :custom_bastion, hostname: "custom-bastion-node", jump_host: "custom.bastion.com")
      end

      it "attempts custom bastion SSH connection" do
        service = described_class.new(node: custom_bastion_node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end

    context "with localhost node" do
      let(:localhost_node) { create(:node, ip: "127.0.0.1", hostname: "localhost-node") }

      it "treats localhost as direct connection" do
        service = described_class.new(node: localhost_node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end

    context "with IPv6 localhost" do
      let(:ipv6_localhost) { create(:node, ip: "::1", hostname: "ipv6-localhost") }

      it "treats IPv6 localhost as direct connection" do
        service = described_class.new(node: ipv6_localhost, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError)
      end
    end
  end

  describe "SSH mocked operations" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }
    let(:mock_scp) { instance_double(Net::SCP) }
    let(:mock_channel) { instance_double(Net::SSH::Connection::Channel) }

    before do
      allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
      allow(mock_ssh).to receive(:scp).and_return(mock_scp)
      allow(mock_scp).to receive(:upload!)
      allow(mock_ssh).to receive(:loop)
    end

    def setup_successful_ssh_execution
      allow(mock_ssh).to receive(:open_channel).and_yield(mock_channel)
      allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
      allow(mock_channel).to receive(:on_data)
      allow(mock_channel).to receive(:on_extended_data)
      allow(mock_channel).to receive(:on_request).with("exit-status")
    end

    context "successful direct update" do
      before do
        # Track which command is being executed
        @command_index = 0

        # Mock successful command execution
        allow(mock_ssh).to receive(:open_channel) do |&block|
          block.call(mock_channel)
          mock_ssh
        end

        @current_cmd = nil
        allow(mock_channel).to receive(:exec) do |cmd, &block|
          @current_cmd = cmd
          @command_index += 1
          block.call(mock_channel, true)
        end

        # Capture callbacks
        @data_callback = nil
        @exit_callback = nil

        allow(mock_channel).to receive(:on_data) { |&block| @data_callback = block }
        allow(mock_channel).to receive(:on_extended_data)
        allow(mock_channel).to receive(:on_request).with("exit-status") { |&block| @exit_callback = block }

        allow(mock_ssh).to receive(:loop) do
          # Simulate command output based on command being executed
          if @current_cmd&.include?("sha256sum")
            @data_callback&.call(mock_channel, agent_release.checksum)
          elsif @current_cmd&.include?("is-active")
            @data_callback&.call(mock_channel, "active")
          end
          mock_data = double("exit_data")
          allow(mock_data).to receive(:read_long).and_return(0)
          @exit_callback&.call(mock_channel, mock_data)
        end
      end

      it "returns successful result" do
        service = described_class.new(node: node, agent_release: agent_release)
        result = service.call

        expect(result.success?).to be true
        expect(result.message).to include("v1.0.0")
      end

      it "uploads binary via SCP" do
        expect(mock_scp).to receive(:upload!).with(anything, "/tmp/agent_update")

        service = described_class.new(node: node, agent_release: agent_release)
        service.call
      end

      it "reports all progress steps" do
        messages = []
        service = described_class.new(
          node: node,
          agent_release: agent_release,
          on_progress: ->(msg) { messages << msg }
        )
        service.call

        expect(messages).to include(/Starting agent update/)
        expect(messages).to include(/Downloading binary/)
        expect(messages).to include(/Connecting directly/)
        expect(messages).to include(/Uploading binary/)
        expect(messages).to include(/Stopping agent service/)
        expect(messages).to include(/Verifying binary checksum/)
        expect(messages).to include(/Installing new binary/)
        expect(messages).to include(/Setting file permissions/)
        expect(messages).to include(/Starting agent service/)
        expect(messages).to include(/Verifying service status/)
        expect(messages).to include(/Service is running/)
      end

      it "updates node agent_version after successful patch" do
        expect(node.agent_version).to be_nil

        service = described_class.new(node: node, agent_release: agent_release)
        service.call

        node.reload
        expect(node.agent_version).to eq("v1.0.0")
      end

      it "sets agent_version to the release version" do
        release_v2 = create(:agent_release, version: "v2.5.0")

        # Update mock to use release_v2's checksum
        allow(mock_ssh).to receive(:loop) do
          if @current_cmd&.include?("sha256sum")
            @data_callback&.call(mock_channel, release_v2.checksum)
          elsif @current_cmd&.include?("is-active")
            @data_callback&.call(mock_channel, "active")
          end
          mock_data = double("exit_data")
          allow(mock_data).to receive(:read_long).and_return(0)
          @exit_callback&.call(mock_channel, mock_data)
        end

        service = described_class.new(node: node, agent_release: release_v2)
        service.call

        node.reload
        expect(node.agent_version).to eq("v2.5.0")
      end
    end

    context "SSH command failure" do
      before do
        allow(mock_ssh).to receive(:open_channel) do |&block|
          block.call(mock_channel)
          mock_ssh
        end

        allow(mock_channel).to receive(:exec) do |_cmd, &block|
          block.call(mock_channel, true)
        end

        stderr_callback = nil
        exit_callback = nil

        allow(mock_channel).to receive(:on_data)
        allow(mock_channel).to receive(:on_extended_data) { |&block| stderr_callback = block }
        allow(mock_channel).to receive(:on_request).with("exit-status") { |&block| exit_callback = block }

        allow(mock_ssh).to receive(:loop) do
          stderr_callback&.call(mock_channel, 1, "Command not found")
          mock_data = double("exit_data")
          allow(mock_data).to receive(:read_long).and_return(1)
          exit_callback&.call(mock_channel, mock_data)
        end
      end

      it "raises PatchError with exit code" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /exit 1/)
      end
    end

    context "checksum mismatch" do
      before do
        allow(mock_ssh).to receive(:open_channel) do |&block|
          block.call(mock_channel)
          mock_ssh
        end

        cmd_count = 0
        allow(mock_channel).to receive(:exec) do |_cmd, &block|
          cmd_count += 1
          block.call(mock_channel, true)
        end

        data_callback = nil
        exit_callback = nil

        allow(mock_channel).to receive(:on_data) { |&block| data_callback = block }
        allow(mock_channel).to receive(:on_extended_data)
        allow(mock_channel).to receive(:on_request).with("exit-status") { |&block| exit_callback = block }

        command_index = 0
        allow(mock_ssh).to receive(:loop) do
          command_index += 1
          # First command is systemctl stop (success)
          # Second command is checksum verification (returns wrong checksum)
          if command_index == 2
            data_callback&.call(mock_channel, "wrongchecksum123")
          end
          mock_data = double("exit_data")
          allow(mock_data).to receive(:read_long).and_return(0)
          exit_callback&.call(mock_channel, mock_data)
        end
      end

      it "raises PatchError for checksum mismatch" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Checksum mismatch/)
      end
    end

    context "service fails to start" do
      before do
        allow(mock_ssh).to receive(:open_channel) do |&block|
          block.call(mock_channel)
          mock_ssh
        end

        allow(mock_channel).to receive(:exec) do |_cmd, &block|
          block.call(mock_channel, true)
        end

        data_callback = nil
        exit_callback = nil

        allow(mock_channel).to receive(:on_data) { |&block| data_callback = block }
        allow(mock_channel).to receive(:on_extended_data)
        allow(mock_channel).to receive(:on_request).with("exit-status") { |&block| exit_callback = block }

        command_index = 0
        allow(mock_ssh).to receive(:loop) do
          command_index += 1
          case command_index
          when 2
            # Checksum verification - return correct checksum
            data_callback&.call(mock_channel, agent_release.checksum)
          when 6
            # Service status check - return "failed"
            data_callback&.call(mock_channel, "failed")
          end
          mock_data = double("exit_data")
          allow(mock_data).to receive(:read_long).and_return(0)
          exit_callback&.call(mock_channel, mock_data)
        end
      end

      it "raises PatchError when service is not active" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Service failed to start/)
      end
    end

    context "exec command fails to start" do
      before do
        allow(mock_ssh).to receive(:open_channel) do |&block|
          block.call(mock_channel)
          mock_ssh
        end

        allow(mock_channel).to receive(:exec) do |_cmd, &block|
          block.call(mock_channel, false) # Command failed to execute
        end
      end

      it "raises PatchError" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect { service.call }.to raise_error(Agent::PatchService::PatchError, /Could not execute command/)
      end
    end
  end

  describe "localhost local execution" do
    let(:localhost_node) { create(:node, ip: "127.0.0.1", hostname: "localhost-node") }

    it "detects localhost for 127.0.0.1" do
      service = described_class.new(node: localhost_node, agent_release: agent_release)
      expect(service.send(:localhost_target?)).to be true
    end

    it "detects localhost for localhost hostname" do
      localhost_hostname_node = create(:node, ip: nil, hostname: "localhost")
      service = described_class.new(node: localhost_hostname_node, agent_release: agent_release)
      expect(service.send(:localhost_target?)).to be true
    end

    it "detects localhost for ::1 IPv6" do
      ipv6_node = create(:node, ip: "::1", hostname: "ipv6-local")
      service = described_class.new(node: ipv6_node, agent_release: agent_release)
      expect(service.send(:localhost_target?)).to be true
    end

    context "local update execution" do
      before do
        allow(FileUtils).to receive(:cp)
        allow(Open3).to receive(:capture3) do |cmd|
          status = instance_double(Process::Status, success?: true, exitstatus: 0)

          if cmd.include?("sha256sum")
            [ agent_release.checksum, "", status ]
          elsif cmd.include?("is-active")
            [ "active", "", status ]
          else
            [ "", "", status ]
          end
        end
      end

      it "uses local execution instead of SSH for localhost" do
        expect(Net::SSH).not_to receive(:start)
        expect(FileUtils).to receive(:cp)

        service = described_class.new(node: localhost_node, agent_release: agent_release)
        result = service.call

        expect(result.success?).to be true
      end

      it "updates agent_version after successful local patch" do
        expect(localhost_node.agent_version).to be_nil

        service = described_class.new(node: localhost_node, agent_release: agent_release)
        service.call

        localhost_node.reload
        expect(localhost_node.agent_version).to eq("v1.0.0")
      end

      it "reports progress for local execution" do
        messages = []
        service = described_class.new(
          node: localhost_node,
          agent_release: agent_release,
          on_progress: ->(msg) { messages << msg }
        )
        service.call

        expect(messages).to include(/Executing local update/)
        expect(messages).to include(/Copying binary/)
      end
    end

    context "local command building" do
      let(:service) { described_class.new(node: localhost_node, agent_release: agent_release) }

      it "builds command with sudo when use_sudo is true and password present" do
        localhost_node.update(sudo_credential: "sudo_pass")
        cmd = service.send(:build_local_command, "systemctl stop hpc-agent", use_sudo: true)

        expect(cmd).to include("echo")
        expect(cmd).to include("sudo -S")
        # Command is shell-escaped, so check for the escaped pattern
        expect(cmd).to match(/systemctl.*stop.*hpc-agent/)
      end

      it "builds command with sudo without password when no sudo_credential" do
        localhost_node.update(sudo_credential: nil)
        cmd = service.send(:build_local_command, "systemctl stop hpc-agent", use_sudo: true)

        expect(cmd).to include("sudo bash -c")
        expect(cmd).not_to include("echo")
      end

      it "builds plain command when use_sudo is false" do
        cmd = service.send(:build_local_command, "sha256sum /tmp/file", use_sudo: false)

        expect(cmd).to eq("sha256sum /tmp/file")
        expect(cmd).not_to include("sudo")
      end
    end
  end

  describe "bastion connection" do
    let(:bastion_node) { create(:node, :global_bastion, hostname: "bastion-node", ip: "10.0.0.5") }
    let(:mock_bastion_ssh) { instance_double(Net::SSH::Connection::Session) }
    let(:mock_scp) { instance_double(Net::SCP) }
    let(:mock_channel) { instance_double(Net::SSH::Connection::Channel) }

    before do
      allow(SshConfig).to receive(:use_jump_host?).and_return(true)
      allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
      allow(SshConfig).to receive(:jump_user).and_return("jump_user")
      allow(SshConfig).to receive(:jump_port).and_return(22)
      allow(SshConfig).to receive(:user).and_return("admin")
      allow(SshConfig).to receive(:key_path).and_return("/path/to/key")
    end

    it "connects to bastion host first" do
      expect(Net::SSH).to receive(:start).with(
        "bastion.example.com",
        "jump_user",
        hash_including(port: 22)
      ).and_raise(Errno::ECONNREFUSED)

      service = described_class.new(node: bastion_node, agent_release: agent_release)
      expect { service.call }.to raise_error(Agent::PatchService::PatchError)
    end
  end

  describe "localhost detection" do
    it "returns false for nil host" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, nil)
      expect(result).to be false
    end

    it "returns false for blank host" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, "")
      expect(result).to be false
    end

    it "returns true for 127.0.0.1" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, "127.0.0.1")
      expect(result).to be true
    end

    it "returns true for localhost" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, "localhost")
      expect(result).to be true
    end

    it "returns true for ::1" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, "::1")
      expect(result).to be true
    end

    it "returns false for regular IP" do
      service = described_class.new(node: node, agent_release: agent_release)
      result = service.send(:localhost?, "192.168.1.1")
      expect(result).to be false
    end
  end

  describe "ssh_user" do
    context "when node has ssh_user" do
      let(:node_with_user) { create(:node, :direct, ssh_user: "custom_user") }

      it "uses node's ssh_user" do
        service = described_class.new(node: node_with_user, agent_release: agent_release)
        expect(service.send(:ssh_user)).to eq("custom_user")
      end
    end

    context "when node has no ssh_user but SshConfig has one" do
      before do
        allow(SshConfig).to receive(:user).and_return("config_user")
      end

      it "uses SshConfig user" do
        node_without_user = create(:node, :direct, ssh_user: nil)
        service = described_class.new(node: node_without_user, agent_release: agent_release)
        expect(service.send(:ssh_user)).to eq("config_user")
      end
    end

    context "when neither node nor SshConfig has user" do
      before do
        allow(SshConfig).to receive(:user).and_return(nil)
      end

      it "defaults to root" do
        node_without_user = create(:node, :direct, ssh_user: nil)
        service = described_class.new(node: node_without_user, agent_release: agent_release)
        expect(service.send(:ssh_user)).to eq("root")
      end
    end
  end

  describe "ssh_keys" do
    context "when SshConfig has key_path" do
      before do
        allow(SshConfig).to receive(:key_path).and_return("/path/to/key")
      end

      it "returns array with key path" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect(service.send(:ssh_keys)).to eq([ "/path/to/key" ])
      end
    end

    context "when SshConfig has no key_path" do
      before do
        allow(SshConfig).to receive(:key_path).and_return(nil)
      end

      it "returns empty array" do
        service = described_class.new(node: node, agent_release: agent_release)
        expect(service.send(:ssh_keys)).to eq([])
      end
    end
  end

  describe "build_remote_command" do
    it "builds direct command without sudo" do
      service = described_class.new(node: node, agent_release: agent_release)
      cmd = service.send(:build_remote_command, "echo hello", via_ssh: false, use_sudo: false)
      expect(cmd).to eq("echo hello")
    end

    it "builds direct command with sudo" do
      service = described_class.new(node: node, agent_release: agent_release)
      cmd = service.send(:build_remote_command, "mv file dest", via_ssh: false, use_sudo: true)
      expect(cmd).to include("sudo")
      expect(cmd).to include("mv file dest")
    end

    it "builds via_ssh command without sudo" do
      service = described_class.new(node: node, agent_release: agent_release)
      cmd = service.send(:build_remote_command, "echo test", via_ssh: true, use_sudo: false)
      expect(cmd).to include("ssh")
      expect(cmd).to include("-o StrictHostKeyChecking=no")
    end

    it "builds via_ssh command with IPv6 address" do
      ipv6_node = create(:node, ip: "2001:db8::1", hostname: "ipv6-host")
      service = described_class.new(node: ipv6_node, agent_release: agent_release)
      cmd = service.send(:build_remote_command, "echo test", via_ssh: true, use_sudo: false)
      # The brackets are escaped by Shellwords
      expect(cmd).to include("2001:db8::1")
      expect(cmd).to include("ssh")
    end
  end

  describe "ssh_password" do
    context "when node has ssh_password" do
      let(:node_with_ssh_password) { create(:node, :direct, ssh_password: "ssh_secret") }

      it "returns node's ssh_password" do
        service = described_class.new(node: node_with_ssh_password, agent_release: agent_release)
        expect(service.send(:ssh_password)).to eq("ssh_secret")
      end
    end

    context "when node has no ssh_password" do
      let(:node_without_ssh_password) { create(:node, :direct, ssh_password: nil) }

      it "returns nil" do
        service = described_class.new(node: node_without_ssh_password, agent_release: agent_release)
        expect(service.send(:ssh_password)).to be_nil
      end
    end

    context "ssh_password is separate from sudo_credential" do
      let(:node_with_both) { create(:node, :direct, ssh_password: "ssh_pass", sudo_credential: "sudo_pass") }

      it "ssh_password returns only ssh_password value" do
        service = described_class.new(node: node_with_both, agent_release: agent_release)
        expect(service.send(:ssh_password)).to eq("ssh_pass")
      end

      it "sudo_password returns only sudo_credential value" do
        service = described_class.new(node: node_with_both, agent_release: agent_release)
        expect(service.send(:sudo_password)).to eq("sudo_pass")
      end
    end
  end

  describe "ssh_options password field" do
    it "uses ssh_password for SSH authentication" do
      node_with_ssh = create(:node, :direct, ssh_password: "ssh_auth_password")
      service = described_class.new(node: node_with_ssh, agent_release: agent_release)
      options = service.send(:ssh_options)

      expect(options[:password]).to eq("ssh_auth_password")
    end

    it "does not use sudo_credential for SSH authentication" do
      node_with_sudo_only = create(:node, :direct, ssh_password: nil, sudo_credential: "sudo_only")
      service = described_class.new(node: node_with_sudo_only, agent_release: agent_release)
      options = service.send(:ssh_options)

      # Password should be nil, not the sudo_credential
      expect(options[:password]).to be_nil
    end
  end

  describe "use_bastion?" do
    context "with direct node" do
      let(:direct_node) { create(:node, :direct) }

      it "returns false" do
        service = described_class.new(node: direct_node, agent_release: agent_release)
        expect(service.send(:use_bastion?)).to be false
      end
    end

    context "with localhost" do
      let(:localhost_node) { create(:node, :global_bastion, ip: "127.0.0.1") }

      it "returns false even for global_bastion" do
        service = described_class.new(node: localhost_node, agent_release: agent_release)
        expect(service.send(:use_bastion?)).to be false
      end
    end

    context "with custom bastion and jump_host" do
      let(:custom_node) { create(:node, :custom_bastion, jump_host: "jump.example.com") }

      it "returns true" do
        service = described_class.new(node: custom_node, agent_release: agent_release)
        expect(service.send(:use_bastion?)).to be true
      end
    end

    context "with global bastion and SshConfig enabled" do
      let(:global_node) { create(:node, :global_bastion) }

      before do
        allow(SshConfig).to receive(:use_jump_host?).and_return(true)
      end

      it "returns true" do
        service = described_class.new(node: global_node, agent_release: agent_release)
        expect(service.send(:use_bastion?)).to be true
      end
    end

    context "with global bastion but SshConfig disabled" do
      let(:global_node) { create(:node, :global_bastion) }

      before do
        allow(SshConfig).to receive(:use_jump_host?).and_return(false)
      end

      it "returns false" do
        service = described_class.new(node: global_node, agent_release: agent_release)
        expect(service.send(:use_bastion?)).to be false
      end
    end
  end
end
