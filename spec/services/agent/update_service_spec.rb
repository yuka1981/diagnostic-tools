# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/agent/errors"
require_relative "../../../app/services/agent/concerns/remote_execution"
require_relative "../../../app/services/agent/lifecycle_service"
require_relative "../../../app/services/agent/update_service"

RSpec.describe Agent::UpdateService do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100", agent_version: "v0.9.0") }
  let(:agent_release) { create(:agent_release, version: "v1.0.0") }

  describe "#operation_type" do
    it "returns :upgrade" do
      service = described_class.new(node: node, agent_release: agent_release)
      expect(service.send(:operation_type)).to eq(:upgrade)
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
        allow(service).to receive(:with_connection).and_yield(nil)
        expect { service.call }.to raise_error(Agent::NodeBusyError)
      end

      it "allows force bypass" do
        service = described_class.new(node: node, agent_release: agent_release, force: true)
        allow(service).to receive(:with_connection).and_yield(nil)
        allow(service).to receive(:execute_operation)
        allow(service).to receive(:verify_health)
        # Will not raise NodeBusyError - completes successfully
        result = service.call
        expect(result.success?).to be true
      end
    end

    context "when agent_release is recalled" do
      let(:recalled_release) { create(:agent_release, :recalled, version: "v2.0.0") }

      it "raises ValidationError" do
        service = described_class.new(node: node, agent_release: recalled_release)
        allow(service).to receive(:with_connection).and_yield(nil)
        expect { service.call }.to raise_error(Agent::ValidationError, /recalled/)
      end
    end

    context "when agent_release has no binary for architecture" do
      let(:release_without_binary) { create(:agent_release, :without_binary, version: "v3.0.0") }

      it "raises ValidationError" do
        service = described_class.new(node: node, agent_release: release_without_binary)
        allow(service).to receive(:with_connection).and_yield(nil)
        expect { service.call }.to raise_error(Agent::ValidationError, /No binary/)
      end
    end
  end

  describe "creates AgentEvent" do
    it "records the update operation" do
      service = described_class.new(node: node, agent_release: agent_release)
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)
      allow(service).to receive(:verify_health)

      expect { service.call }.to change(AgentEvent, :count).by(1)

      event = AgentEvent.last
      expect(event.operation).to eq("upgrade")
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

  describe "#finalize" do
    it "updates node agent_version" do
      service = described_class.new(node: node, agent_release: agent_release)
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)
      allow(service).to receive(:verify_health)

      service.call
      node.reload
      expect(node.agent_version).to eq("v1.0.0")
    end
  end
end
