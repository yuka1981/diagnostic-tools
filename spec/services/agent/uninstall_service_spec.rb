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
end
