# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/agent/errors"
require_relative "../../../app/services/agent/concerns/remote_execution"
require_relative "../../../app/services/agent/lifecycle_service"
require_relative "../../../app/services/agent/uninstall_service"

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
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)

      expect { service.call }.to change(AgentEvent, :count).by(1)

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

  describe "#success_message" do
    it "returns appropriate message" do
      service = described_class.new(node: node)
      expect(service.send(:success_message)).to eq("Agent uninstalled successfully")
    end
  end

  describe "always uses SSH for uninstall" do
    let(:ssh_session) { instance_double(Net::SSH::Connection::Session) }
    let(:service) { described_class.new(node: node) }

    context "when node is online with UUID" do
      let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100", uuid: "abc-123", agent_version: "v1.0.0") }

      before do
        node.update!(last_heartbeat_at: 1.minute.ago)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "uses SSH instead of WebSocket" do
        expect(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(service).to receive(:perform_remote_uninstall)

        service.call
      end

      it "does not broadcast uninstall command to agent channel" do
        allow(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(service).to receive(:perform_remote_uninstall)

        expect(ActionCable.server).not_to receive(:broadcast).with(
          "agent_abc-123",
          hash_including(action: "uninstall")
        )

        service.call
      end

      it "creates AgentEvent with success status" do
        allow(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(service).to receive(:perform_remote_uninstall)

        expect { service.call }.to change(AgentEvent, :count).by(1)

        event = AgentEvent.last
        expect(event.operation).to eq("uninstall")
        expect(event.status).to eq("success")
      end
    end

    context "when node is offline" do
      before do
        node.update!(last_heartbeat_at: 10.minutes.ago)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "uses SSH for uninstall" do
        expect(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(service).to receive(:perform_remote_uninstall)

        service.call
      end
    end

    context "when node has no UUID" do
      let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100", agent_version: "v1.0.0") }

      before do
        node.update_columns(uuid: nil, last_heartbeat_at: 1.minute.ago)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "uses SSH for uninstall" do
        expect(Net::SSH).to receive(:start).and_yield(ssh_session)
        allow(service).to receive(:perform_remote_uninstall)

        service.call
      end
    end
  end

  describe "SSH uninstall operations" do
    let(:ssh_session) { instance_double(Net::SSH::Connection::Session) }
    let(:service) { described_class.new(node: node) }

    before do
      allow(Net::SSH).to receive(:start).and_yield(ssh_session)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "stops the agent service" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/systemctl stop qis-agent/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end

    it "disables the agent service" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/systemctl disable qis-agent/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end

    it "removes the agent binary" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/rm -f.*\/usr\/local\/bin\/qis-agent/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end

    it "removes the service file" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/rm -f.*qis-agent\.service/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end

    it "reloads systemd" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/systemctl daemon-reload/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end

    it "removes the configuration directory" do
      expect(service).to receive(:execute_command).with(
        ssh_session,
        match(/rm -rf.*\/etc\/qis-agent/),
        anything
      ).and_return("")
      allow(service).to receive(:execute_command).and_return("")

      service.call
    end
  end
end
