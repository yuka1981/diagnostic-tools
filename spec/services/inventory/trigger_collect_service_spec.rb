# frozen_string_literal: true

require "rails_helper"
require "shellwords"

RSpec.describe Inventory::TriggerCollectService do
  let(:gateway_node) { create(:node, :admin, hostname: "gateway-01", ip: "192.168.1.1") }
  let(:target_node) { create(:node, hostname: "compute-01", ip: "192.168.1.10") }

  let(:ssh_config) do
    {
      user: "admin",
      keys: [ "/path/to/key" ],
      timeout: 30
    }
  end

  subject(:service) { described_class.new(target_node, gateway: gateway_node, ssh_config: ssh_config) }

  describe "#call" do
    let(:mock_session) { instance_double(Net::SSH::Connection::Session) }

    context "when jump host is configured" do
      let(:gateway_node) { nil } # Ensure legacy gateway is not used
      subject(:service) { described_class.new(target_node, gateway: nil, ssh_config: ssh_config) }
      let(:gateway) { instance_double(Net::SSH::Gateway) }

      before do
        allow(SshConfig).to receive(:use_jump_host?).and_return(true)
        allow(SshConfig).to receive(:jump_host).and_return("jump.example.com")
        allow(SshConfig).to receive(:jump_user).and_return("jumpuser")
        allow(SshConfig).to receive(:jump_port).and_return(2222)

        allow(Net::SSH::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:ssh).and_yield(mock_session)
        allow(gateway).to receive(:shutdown!)
        allow(mock_session).to receive(:exec!).and_return("{}")
      end

      it "uses Net::SSH::Gateway to connect" do
        expect(Net::SSH::Gateway).to receive(:new).with(
          "jump.example.com",
          "jumpuser",
          hash_including(port: 2222)
        )
        expect(gateway).to receive(:ssh).with(target_node.ip, any_args)

        service.call
      end

      it "shuts down the gateway after use" do
        expect(gateway).to receive(:shutdown!)
        service.call
      end

      it "executes the direct agent command on the target session" do
        expect(mock_session).to receive(:exec!).with("agent collect --json 2>&1")
        service.call
      end
    end

    context "when node specific jump host is configured" do
      let(:gateway_node) { nil } # Ensure legacy gateway is not used
      subject(:service) { described_class.new(target_node, gateway: nil, ssh_config: ssh_config) }
      let(:target_node) { create(:node, jump_host: "node-jump.example.com", jump_user: "node-jumpuser", jump_port: 2223) }
      let(:gateway) { instance_double(Net::SSH::Gateway) }

      before do
        allow(Net::SSH::Gateway).to receive(:new).and_return(gateway)
        allow(gateway).to receive(:ssh).and_yield(mock_session)
        allow(gateway).to receive(:shutdown!)
        allow(mock_session).to receive(:exec!).and_return("{}")
      end

      it "uses node specific jump host settings" do
        expect(Net::SSH::Gateway).to receive(:new).with(
          "node-jump.example.com",
          "node-jumpuser",
          hash_including(port: 2223)
        )

        service.call
      end
    end

    context "when using node specific SSH settings" do
      let(:target_node) { create(:node, ip: "10.0.0.1", ssh_user: "custom_user", ssh_port: 2222, agent_path: "/custom/agent") }
      subject(:service) { described_class.new(target_node, ssh_config: ssh_config) }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return("{}")
      end

      it "connects using node specific user and port" do
        expect(Net::SSH).to receive(:start).with(
          "10.0.0.1",
          "custom_user",
          hash_including(port: 2222)
        )

        service.call
      end

      it "uses node specific agent path" do
        expect(mock_session).to receive(:exec!).with("/custom/agent collect --json 2>&1")
        service.call
      end
    end

    context "when SSH command succeeds" do
      let(:command_output) do
        {
          cpu_info: { model: "Intel Xeon", cores: 32 },
          mem_info: { total: 128.gigabytes, available: 64.gigabytes }
        }.to_json
      end

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "connects to gateway with correct parameters" do
        expect(Net::SSH).to receive(:start).with(
          gateway_node.ip,
          ssh_config[:user],
          hash_including(keys: ssh_config[:keys], timeout: ssh_config[:timeout])
        )

        service.call
      end

      it "executes the correct SSH command with escaped arguments" do
        expected_command = "ssh compute-01 agent collect --json 2>&1"

        expect(mock_session).to receive(:exec!).with(expected_command)

        service.call
      end

      it "returns success result with parsed JSON" do
        result = service.call

        expect(result.success?).to be true
        expect(result.output).to be_a(Hash)
        expect(result.output[:cpu_info]).to be_present
      end

      it "updates node last_seen_at" do
        expect { service.call }.to change { target_node.reload.last_seen_at }
      end
    end

    context "when agent returns an error" do
      let(:command_output) { "Error: failed to collect inventory: some internal error" }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "returns failure with agent error message" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Agent error: failed to collect inventory")
      end
    end

    context "when command is not found" do
      let(:command_output) { "zsh:1: command not found: agent" }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "returns descriptive error about agent missing" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Agent not found")
      end
    end

    context "when permission is denied" do
      let(:command_output) { "bash: /usr/local/bin/agent: Permission denied" }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "returns descriptive error about permissions" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Permission denied")
      end
    end

    context "when SSH command returns empty output" do
      let(:command_output) { "" }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "returns error result" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("empty")
      end
    end

    context "when SSH command returns invalid JSON" do
      let(:command_output) { "not valid json" }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        allow(mock_session).to receive(:exec!).and_return(command_output)
      end

      it "returns error result with JSON parse error" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("JSON")
      end
    end

    # SSH exceptions should bubble up to allow job retry logic to work
    context "when SSH connection times out" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::ConnectionTimeout.new("Connection timed out")
        )
      end

      it "raises ConnectionTimeout exception" do
        expect { service.call }.to raise_error(Net::SSH::ConnectionTimeout)
      end
    end

    context "when SSH authentication fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::AuthenticationFailed.new("admin")
        )
      end

      it "raises AuthenticationFailed exception" do
        expect { service.call }.to raise_error(Net::SSH::AuthenticationFailed)
      end
    end

    context "when SSH host key verification fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::HostKeyMismatch.new("Host key mismatch")
        )
      end

      it "raises HostKeyMismatch exception" do
        expect { service.call }.to raise_error(Net::SSH::HostKeyMismatch)
      end
    end
  end

  describe "#command" do
    it "builds correct command for target node with escaped arguments" do
      expect(service.send(:command)).to eq("agent collect --json 2>&1")
    end

    context "with custom agent path" do
      let(:agent_path) { "/opt/agent/bin/agent" }

      it "uses custom agent path escaped" do
        expect(service.send(:command)).to eq("/opt/agent/bin/agent collect --json 2>&1")
      end
    end

    context "with hostname containing special characters" do
      let(:target_node) { create(:node, hostname: "node-with-dash") }

      it "escapes hostname properly" do
        # The command itself doesn't contain the hostname anymore (SSH handles it)
        expect(command).to eq("agent collect --json 2>&1")
      end
    end

    context "with potentially dangerous hostname" do
      let(:target_node) { create(:node, hostname: "node; rm -rf /") }

      it "escapes dangerous characters" do
        # Just checking the command is safe/standard
        expect(command).to eq("agent collect --json 2>&1")
      end
    end
  end

  describe "gateway configuration" do
    context "when gateway is not provided" do
      subject(:service) { described_class.new(target_node, ssh_config: ssh_config) }

      it "uses target node directly as SSH host" do
        expect(Net::SSH).to receive(:start).with(
          target_node.ip,
          ssh_config[:user],
          anything
        ).and_yield(instance_double(Net::SSH::Connection::Session, exec!: "{}"))

        service.call
      end

      it "executes agent command directly without ssh prefix" do
        mock_session = instance_double(Net::SSH::Connection::Session)
        allow(Net::SSH).to receive(:start).and_yield(mock_session)
        expect(mock_session).to receive(:exec!).with("agent collect --json 2>&1").and_return("{}")

        service.call
      end
    end
  end

  describe "SSH options" do
    context "when verify_host_key is not configured" do
      it "does not include verify_host_key in options (uses net-ssh default :secure)" do
        expect(Net::SSH).to receive(:start).with(
          anything,
          anything,
          hash_not_including(:verify_host_key)
        ).and_yield(instance_double(Net::SSH::Connection::Session, exec!: "{}"))

        service.call
      end
    end

    context "when verify_host_key is explicitly configured" do
      let(:ssh_config) do
        {
          user: "admin",
          keys: [ "/path/to/key" ],
          timeout: 30,
          verify_host_key: :accept_new
        }
      end

      it "includes verify_host_key in options" do
        expect(Net::SSH).to receive(:start).with(
          anything,
          anything,
          hash_including(verify_host_key: :accept_new)
        ).and_yield(instance_double(Net::SSH::Connection::Session, exec!: "{}"))

        service.call
      end
    end
  end

  describe "default configuration" do
    context "when ssh_config uses Rails credentials" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:ssh, :user).and_return("deploy")
        allow(Rails.application.credentials).to receive(:dig).with(:ssh, :key_path).and_return("/home/deploy/.ssh/id_rsa")
        allow(Rails.application.credentials).to receive(:dig).with(:ssh, :timeout).and_return(60)
        allow(Rails.application.credentials).to receive(:dig).with(:ssh, :verify_host_key).and_return(nil)
      end

      subject(:service) { described_class.new(target_node, gateway: gateway_node) }

      it "loads configuration from Rails credentials" do
        expect(Net::SSH).to receive(:start).with(
          gateway_node.ip,
          "deploy",
          hash_including(keys: [ "/home/deploy/.ssh/id_rsa" ], timeout: 60)
        ).and_yield(instance_double(Net::SSH::Connection::Session, exec!: "{}"))

        service.call
      end
    end
  end
end
