# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/agent/errors"
require_relative "../../../app/services/agent/concerns/remote_execution"
require_relative "../../../app/services/agent/lifecycle_service"
require_relative "../../../app/services/agent/update_service"
require_relative "../../../app/services/agent/install_service"

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
      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)
      allow(service).to receive(:verify_health)

      expect { service.call }.to change(AgentEvent, :count).by(1)

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

    it "sets source to agent_push" do
      service = described_class.new(node: node, agent_release: agent_release, server_url: "http://localhost", api_token: "token")

      allow(service).to receive(:with_connection).and_yield(nil)
      allow(service).to receive(:execute_operation)
      allow(service).to receive(:verify_health)

      service.call

      node.reload
      expect(node.source).to eq("agent_push")
    end
  end

  describe "with dev binary (no release)" do
    it "accepts binary_path instead of agent_release" do
      # Create a temp file to simulate a binary
      tempfile = Tempfile.new("test-agent")
      tempfile.write("#!/bin/bash\necho 'test'")
      tempfile.close

      service = described_class.new(
        node: node,
        binary_path: tempfile.path,
        server_url: "http://localhost",
        api_token: "token"
      )

      expect(service.send(:expected_version)).to eq("dev")

      tempfile.unlink
    end
  end

  describe "#run_preflight_checks" do
    context "when neither agent_release nor binary_path provided" do
      it "raises ValidationError" do
        service = described_class.new(
          node: node,
          server_url: "http://localhost",
          api_token: "token"
        )
        allow(service).to receive(:with_connection).and_yield(nil)
        expect { service.call }.to raise_error(Agent::Errors::ValidationError, /binary_path must be provided/)
      end
    end

    context "when agent_release has no binary" do
      let(:release_without_binary) { create(:agent_release, :without_binary, version: "v2.0.0") }

      it "raises ValidationError" do
        service = described_class.new(
          node: node,
          agent_release: release_without_binary,
          server_url: "http://localhost",
          api_token: "token"
        )
        allow(service).to receive(:with_connection).and_yield(nil)
        expect { service.call }.to raise_error(Agent::Errors::ValidationError, /No binary/)
      end
    end
  end
end
