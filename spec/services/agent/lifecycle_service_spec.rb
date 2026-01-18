# frozen_string_literal: true

require "rails_helper"
require_relative "../../../app/services/agent/errors"
require_relative "../../../app/services/agent/concerns/remote_execution"
require_relative "../../../app/services/agent/lifecycle_service"

# Concrete implementation for testing
class TestLifecycleService < Agent::LifecycleService
  def operation_type
    :install
  end

  def execute_operation(_ssh = nil)
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
        allow(service).to receive(:with_connection).and_yield(nil)
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
        allow(service).to receive(:with_connection).and_yield(nil)
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
