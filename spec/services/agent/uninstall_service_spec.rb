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

  describe "WebSocket uninstall" do
    let(:node) { create(:node, :direct, hostname: "test-node", uuid: "abc-123", agent_version: "v1.0.0") }
    let(:service) { described_class.new(node: node) }

    context "when node is online with UUID" do
      before do
        node.update!(last_heartbeat_at: 1.minute.ago)
        # Allow all broadcasts (for node_logs progress reporting)
        allow(ActionCable.server).to receive(:broadcast)
      end

      it "uses WebSocket instead of SSH" do
        expect(Net::SSH).not_to receive(:start)
        # Verify it broadcasts to the agent channel with correct payload
        expect(ActionCable.server).to receive(:broadcast).with(
          "agent_abc-123",
          hash_including(type: "command", action: "uninstall")
        ).at_least(:once)

        service.call
      end

      it "includes correlation_id in broadcast" do
        agent_broadcast_received = false

        allow(ActionCable.server).to receive(:broadcast) do |channel, payload|
          if channel == "agent_abc-123"
            agent_broadcast_received = true
            expect(payload[:correlation_id]).to be_present
            expect(payload[:correlation_id]).to match(/\A[0-9a-f-]{36}\z/)
          end
        end

        service.call
        expect(agent_broadcast_received).to be true
      end

      it "creates AgentEvent with success status" do
        expect { service.call }.to change(AgentEvent, :count).by(1)

        event = AgentEvent.last
        expect(event.operation).to eq("uninstall")
        expect(event.status).to eq("success")
      end

      it "reports progress about WebSocket path" do
        progress_messages = []
        allow(service).to receive(:report_progress).and_wrap_original do |method, message|
          progress_messages << message
          method.call(message)
        end

        service.call

        expect(progress_messages).to include(match(/online.*WebSocket/i))
      end
    end

    context "when node is online but has no UUID" do
      let(:node) { create(:node, :direct, hostname: "test-node", agent_version: "v1.0.0") }

      before do
        # Clear UUID after creation (since factory generates one)
        node.update_columns(uuid: nil, last_heartbeat_at: 1.minute.ago)
        # Allow progress broadcasts but expect no agent channel broadcasts
        allow(ActionCable.server).to receive(:broadcast)
        allow(Net::SSH).to receive(:start).and_yield(instance_double(Net::SSH::Connection::Session))
        allow(service).to receive(:perform_remote_uninstall)
      end

      it "falls back to SSH" do
        # Should NOT broadcast to any agent channel
        expect(ActionCable.server).not_to receive(:broadcast).with(/^agent_/, anything)
        expect(Net::SSH).to receive(:start)

        service.call rescue nil  # May fail due to mock, that's ok
      end
    end

    context "when node is offline" do
      before do
        node.update!(last_heartbeat_at: 10.minutes.ago)
        # Allow progress broadcasts but expect no agent channel broadcasts
        allow(ActionCable.server).to receive(:broadcast)
        allow(Net::SSH).to receive(:start).and_yield(instance_double(Net::SSH::Connection::Session))
        allow(service).to receive(:perform_remote_uninstall)
      end

      it "uses SSH instead of WebSocket" do
        # Should NOT broadcast to any agent channel
        expect(ActionCable.server).not_to receive(:broadcast).with(/^agent_/, anything)
        expect(Net::SSH).to receive(:start)

        service.call rescue nil
      end
    end
  end
end
