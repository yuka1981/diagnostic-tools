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
          Agent::Errors::DeploymentError.new("Deploy failed", phase: :deploy, details: { stderr: "Permission denied" })
        )
      end

      it "creates AgentEvent with failed status" do
        expect { service.call rescue nil }.to change(AgentEvent, :count).by(1)
        event = AgentEvent.last
        expect(event.status).to eq("failed")
        expect(event.error_message).to include("Deploy failed")
      end

      it "raises the error" do
        expect { service.call }.to raise_error(Agent::Errors::DeploymentError)
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

  describe "#connect_direct" do
    let(:node) { create(:node, :direct, hostname: "test.example.com", ip: "192.168.1.100") }
    let(:service) { TestLifecycleService.new(node: node) }

    context "when IP connection fails with network error" do
      before do
        # First call fails with timeout, second succeeds
        call_count = 0
        allow(Net::SSH).to receive(:start) do |host, *_args, &block|
          call_count += 1
          if call_count == 1 && host == "192.168.1.100"
            raise Errno::ETIMEDOUT, "Connection timed out"
          else
            # Simulate successful connection
            mock_ssh = instance_double(Net::SSH::Connection::Session)
            block.call(mock_ssh) if block
          end
        end
      end

      it "retries with hostname after IP fails" do
        expect(Net::SSH).to receive(:start).with("192.168.1.100", anything, anything).ordered
        expect(Net::SSH).to receive(:start).with("test.example.com", anything, anything).ordered

        # Use send to access private method
        service.send(:with_connection) { |_ssh| }
      end

      it "logs the fallback attempt" do
        expect(service).to receive(:report_progress).with(/Connecting directly to 192.168.1.100/)
        expect(service).to receive(:report_progress).with(/Connection to 192.168.1.100 failed/)
        expect(service).to receive(:report_progress).with(/Connecting directly to test.example.com/)

        service.send(:with_connection) { |_ssh| }
      end
    end

    context "when IP connection fails with auth error" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "auth failed")
      end

      it "does not retry with hostname" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |_ssh| }
        }.to raise_error(Agent::Errors::ConnectionError, /authentication failed/i)
      end
    end

    context "when hostname equals IP" do
      let(:node) { create(:node, :direct, hostname: "192.168.1.100", ip: "192.168.1.100") }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ETIMEDOUT, "Connection timed out")
      end

      it "does not retry since no fallback available" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |_ssh| }
        }.to raise_error(Agent::Errors::ConnectionError)
      end
    end

    context "when node has no IP (hostname only)" do
      let(:node) { create(:node, :direct, hostname: "test.example.com", ip: nil) }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED, "Connection refused")
      end

      it "does not retry since no fallback available" do
        expect(Net::SSH).to receive(:start).once

        expect {
          service.send(:with_connection) { |_ssh| }
        }.to raise_error(Agent::Errors::ConnectionError)
      end
    end
  end

  describe "#connect_via_bastion" do
    let(:node) do
      create(:node, :global_bastion,
             hostname: "compute-node.example.com",
             ip: "10.0.0.100")
    end
    let(:service) { TestLifecycleService.new(node: node) }

    before do
      allow(SshConfig).to receive(:jump_host).and_return("bastion.example.com")
      allow(SshConfig).to receive(:jump_user).and_return("bastion_user")
      allow(SshConfig).to receive(:jump_port).and_return(22)
      allow(SshConfig).to receive(:use_jump_host?).and_return(true)
    end

    context "when connection succeeds" do
      let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
      end

      it "connects directly to bastion host" do
        expect(Net::SSH).to receive(:start).with(
          "bastion.example.com",
          "bastion_user",
          hash_including(port: 22)
        ).and_yield(mock_ssh)

        service.send(:with_connection) { |_ssh| }
      end

      it "yields SSH session connected to bastion" do
        # In bastion mode, SSH session is to the bastion
        # Commands use via_ssh: true to SSH from bastion to target
        yielded_ssh = nil
        service.send(:with_connection) { |ssh| yielded_ssh = ssh }

        expect(yielded_ssh).to eq(mock_ssh)
      end

      it "logs connection to bastion with target info" do
        expect(service).to receive(:report_progress).with(
          "Connecting to bastion bastion.example.com (target: 10.0.0.100)"
        )

        service.send(:with_connection) { |_ssh| }
      end
    end

    context "when node uses custom bastion" do
      let(:node) do
        create(:node, :custom_bastion,
               hostname: "compute-node.example.com",
               ip: "10.0.0.100",
               jump_host: "custom-bastion.example.com",
               jump_user: "custom_user",
               jump_port: 2222)
      end

      let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
      end

      it "uses node-specific bastion settings" do
        expect(Net::SSH).to receive(:start).with(
          "custom-bastion.example.com",
          "custom_user",
          hash_including(port: 2222)
        ).and_yield(mock_ssh)

        service.send(:with_connection) { |_ssh| }
      end
    end

    context "when bastion connection fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(
          Errno::ECONNREFUSED, "Connection refused"
        )
      end

      it "raises ConnectionError with bastion and target details" do
        expect {
          service.send(:with_connection) { |_ssh| }
        }.to raise_error(Agent::Errors::ConnectionError) do |error|
          expect(error.message).to include("Bastion connection failed")
          expect(error.details[:bastion]).to eq("bastion.example.com")
          expect(error.details[:target]).to eq("10.0.0.100")
        end
      end
    end

    context "when node has hostname but no IP" do
      let(:node) do
        create(:node, :global_bastion,
               hostname: "compute-node.example.com",
               ip: nil)
      end

      let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

      before do
        allow(Net::SSH).to receive(:start).and_yield(mock_ssh)
      end

      it "uses hostname as target in log message" do
        expect(service).to receive(:report_progress).with(
          "Connecting to bastion bastion.example.com (target: compute-node.example.com)"
        )

        service.send(:with_connection) { |_ssh| }
      end
    end
  end
end
