# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../app/services/agent/errors"
require_relative "../../../../app/services/agent/concerns/remote_execution"
require_relative "../../../../app/services/agent/concerns/service_health_check"

RSpec.describe Agent::Concerns::ServiceHealthCheck do
  # Create a test class that includes the concern
  let(:test_class) do
    Class.new do
      include Agent::Concerns::RemoteExecution
      include Agent::Concerns::ServiceHealthCheck

      attr_accessor :sudo_password

      def initialize(sudo_password: nil)
        @sudo_password = sudo_password
      end

      def report_progress(msg)
        # no-op for tests
      end
    end
  end

  let(:instance) { test_class.new(sudo_password: "secret") }

  describe "#clean_sudo_output" do
    it "returns nil for blank input" do
      expect(instance.send(:clean_sudo_output, nil)).to be_nil
      expect(instance.send(:clean_sudo_output, "")).to be_nil
      expect(instance.send(:clean_sudo_output, "   ")).to be_nil
    end

    it "strips sudo password prompt from output" do
      output = "[sudo] password for reidlin: active"
      expect(instance.send(:clean_sudo_output, output)).to eq("active")
    end

    it "handles sudo prompt with different usernames" do
      output = "[sudo] password for deploy_user: inactive"
      expect(instance.send(:clean_sudo_output, output)).to eq("inactive")
    end

    it "returns clean output unchanged" do
      expect(instance.send(:clean_sudo_output, "active")).to eq("active")
      expect(instance.send(:clean_sudo_output, "inactive")).to eq("inactive")
    end

    it "strips surrounding whitespace" do
      expect(instance.send(:clean_sudo_output, "  active  ")).to eq("active")
    end

    it "handles multiline output with sudo prompt" do
      output = "[sudo] password for user: \nactive"
      expect(instance.send(:clean_sudo_output, output)).to eq("active")
    end
  end

  describe "#get_service_status" do
    context "with local execution (ssh is nil)" do
      before do
        allow(instance).to receive(:execute_local_command)
          .with("systemctl is-active qis-agent", use_sudo: true)
          .and_return("[sudo] password for user: active\n")
      end

      it "returns clean service status" do
        expect(instance.send(:get_service_status, nil)).to eq("active")
      end
    end

    context "with remote execution (ssh provided)" do
      let(:ssh) { instance_double("Net::SSH::Connection::Session") }

      before do
        allow(instance).to receive(:build_remote_command)
          .with("systemctl is-active qis-agent", via_ssh: false, use_sudo: true)
          .and_return("echo secret | sudo -S bash -c 'systemctl is-active qis-agent'")
        allow(instance).to receive(:execute_command)
          .and_return("[sudo] password for deploy: active\n")
      end

      it "returns clean service status" do
        expect(instance.send(:get_service_status, ssh)).to eq("active")
      end
    end

    context "when command fails with DeploymentError" do
      before do
        error = Agent::Errors::DeploymentError.new(
          "Command failed",
          phase: :verify,
          details: { stdout: "[sudo] password for user: inactive" }
        )
        allow(instance).to receive(:execute_local_command).and_raise(error)
      end

      it "extracts status from error details" do
        expect(instance.send(:get_service_status, nil)).to eq("inactive")
      end
    end

    context "when command fails with no stdout" do
      before do
        error = Agent::Errors::DeploymentError.new(
          "Command failed",
          phase: :verify,
          details: {}
        )
        allow(instance).to receive(:execute_local_command).and_raise(error)
      end

      it "returns unknown" do
        expect(instance.send(:get_service_status, nil)).to eq("unknown")
      end
    end
  end

  describe "#verify_service_running" do
    context "when service is active" do
      before do
        allow(instance).to receive(:get_service_status).and_return("active")
      end

      it "completes without error" do
        expect { instance.send(:verify_service_running, nil) }.not_to raise_error
      end
    end

    context "when service is activating then becomes active" do
      before do
        call_count = 0
        allow(instance).to receive(:get_service_status) do
          call_count += 1
          call_count < 3 ? "activating" : "active"
        end
        allow(instance).to receive(:sleep)
      end

      it "waits and succeeds" do
        expect { instance.send(:verify_service_running, nil) }.not_to raise_error
      end
    end

    context "when service stays in activating state" do
      before do
        allow(instance).to receive(:get_service_status).and_return("activating")
        allow(instance).to receive(:sleep)
      end

      it "raises ServiceError after max retries" do
        expect { instance.send(:verify_service_running, nil) }
          .to raise_error(Agent::Errors::ServiceError, /stuck in activating state/)
      end
    end

    context "when service fails to start" do
      let(:ssh) { instance_double("Net::SSH::Connection::Session") }

      before do
        allow(instance).to receive(:get_service_status).and_return("failed")
        allow(instance).to receive(:capture_diagnostics).and_return({ logs: "error" })
      end

      it "raises ServiceError with diagnostics" do
        expect { instance.send(:verify_service_running, ssh) }
          .to raise_error(Agent::Errors::ServiceError, /Service failed to start/)
      end
    end

    context "when service is inactive" do
      before do
        allow(instance).to receive(:get_service_status).and_return("inactive")
        allow(instance).to receive(:capture_diagnostics).and_return({})
      end

      it "raises ServiceError" do
        expect { instance.send(:verify_service_running, nil) }
          .to raise_error(Agent::Errors::ServiceError, /Status: inactive/)
      end
    end
  end
end
