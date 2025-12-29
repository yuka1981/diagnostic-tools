# frozen_string_literal: true

require "rails_helper"

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
    let(:mock_channel) { instance_double(Net::SSH::Connection::Channel) }

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

      it "executes the correct SSH command" do
        expected_command = "ssh #{target_node.hostname} agent collect --json"

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

    context "when SSH connection fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::ConnectionTimeout.new("Connection timed out")
        )
      end

      it "returns error result with connection error" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Connection")
      end
    end

    context "when SSH authentication fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::AuthenticationFailed.new("admin")
        )
      end

      it "returns error result with authentication error" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Authentication")
      end
    end

    context "when SSH host key verification fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Net::SSH::HostKeyMismatch.new("Host key mismatch")
        )
      end

      it "returns error result with host key error" do
        result = service.call

        expect(result.success?).to be false
        expect(result.error).to include("Host key")
      end
    end
  end

  describe "#command" do
    it "builds correct command for target node" do
      expect(service.send(:command)).to eq("ssh compute-01 agent collect --json")
    end

    context "with custom agent path" do
      subject(:service) do
        described_class.new(target_node, gateway: gateway_node, ssh_config: ssh_config, agent_path: "/opt/agent/bin/agent")
      end

      it "uses custom agent path" do
        expect(service.send(:command)).to eq("ssh compute-01 /opt/agent/bin/agent collect --json")
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
        expect(mock_session).to receive(:exec!).with("agent collect --json").and_return("{}")

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
