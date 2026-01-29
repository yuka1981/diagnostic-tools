# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::CancelRunService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:recipe) { create(:benchmark_recipe, :hpcg) }

  def mock_ssh_session(stdout: "{}", stderr: "", exit_code: 0)
    mock_channel = instance_double(Net::SSH::Connection::Channel)
    mock_session = instance_double(Net::SSH::Connection::Session, loop: true)

    allow(mock_session).to receive(:open_channel).and_yield(mock_channel)
    allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
    allow(mock_channel).to receive(:on_data) do |&block|
      block.call(mock_channel, stdout) if stdout.present?
    end
    allow(mock_channel).to receive(:on_extended_data) do |&block|
      block.call(mock_channel, "", stderr) if stderr.present?
    end
    allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: exit_code))
    allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))

    mock_session
  end

  describe "#call" do
    context "when benchmark run is nil" do
      it "raises an error during initialization" do
        expect { described_class.new(nil) }.to raise_error(NoMethodError)
      end
    end

    context "when benchmark run is already completed (success)" do
      let(:benchmark_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }

      it "returns error result" do
        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to eq("Cannot cancel completed run")
      end

      it "does not change the run status" do
        service = described_class.new(benchmark_run)
        expect { service.call }.not_to change { benchmark_run.reload.status }
      end
    end

    context "when benchmark run is already completed (failed)" do
      let(:benchmark_run) { create(:benchmark_run, :failed, node: node, benchmark_recipe: recipe) }

      it "returns error result" do
        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to eq("Cannot cancel completed run")
      end
    end

    context "when benchmark run is already cancelled" do
      let(:benchmark_run) { create(:benchmark_run, :cancelled, node: node, benchmark_recipe: recipe) }

      it "returns error result" do
        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to eq("Cannot cancel completed run")
      end
    end

    context "when benchmark run is pending" do
      let(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }

      it "returns success without making SSH connection" do
        # Should NOT call Net::SSH at all for pending runs
        expect(Net::SSH).not_to receive(:start)

        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.success?).to be true
      end

      it "updates status to cancelled" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.status).to eq("cancelled")
      end

      it "sets finished_at timestamp" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.finished_at).to be_within(1.second).of(Time.current)
      end

      it "sets appropriate error message" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.error_message).to eq("Cancelled from queue before execution")
      end

      it "returns success message" do
        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.output).to eq("Cancelled pending run")
      end
    end

    context "when benchmark run is running" do
      let(:benchmark_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }
      let(:ssh_client) { mock_ssh_session(stdout: '{"status":"ok","message":"Process 12345 killed","pid":12345}') }

      before do
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "makes SSH connection to execute cancel command" do
        expect(Net::SSH).to receive(:start).and_yield(ssh_client)

        service = described_class.new(benchmark_run)
        service.call
      end

      it "returns success when agent reports ok" do
        service = described_class.new(benchmark_run)
        result = service.call
        expect(result.success?).to be true
      end

      it "updates status to cancelled" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.status).to eq("cancelled")
      end

      it "sets finished_at timestamp" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.finished_at).to be_within(1.second).of(Time.current)
      end

      it "sets error_message to indicate user cancellation" do
        service = described_class.new(benchmark_run)
        service.call
        expect(benchmark_run.reload.error_message).to eq("Cancelled by user")
      end

      context "when agent reports process not found" do
        let(:ssh_client) { mock_ssh_session(stdout: '{"status":"not_found","message":"No PID file found"}') }

        it "returns success (process already gone is acceptable)" do
          service = described_class.new(benchmark_run)
          result = service.call
          expect(result.success?).to be true
        end

        it "updates status to cancelled" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.status).to eq("cancelled")
        end

        it "sets appropriate error message" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.error_message).to include("may have already completed")
        end
      end

      context "when SSH authentication fails" do
        before do
          allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Auth failed")
        end

        it "returns error result" do
          service = described_class.new(benchmark_run)
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to include("SSH authentication failed")
        end

        it "still marks run as cancelled for UI consistency" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.status).to eq("cancelled")
        end

        it "includes SSH error in error_message" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.error_message).to include("SSH authentication failed")
        end
      end

      context "when SSH connection fails" do
        before do
          allow(Net::SSH).to receive(:start).and_raise(Net::SSH::ConnectionTimeout, "Connection timed out")
        end

        it "returns error result" do
          service = described_class.new(benchmark_run)
          result = service.call
          expect(result.success?).to be false
          expect(result.error).to include("SSH error")
        end

        it "still marks run as cancelled" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.status).to eq("cancelled")
        end
      end

      context "when SSH command fails (non-zero exit)" do
        let(:ssh_client) { mock_ssh_session(stdout: "", stderr: "Connection refused", exit_code: 1) }

        it "returns error result" do
          service = described_class.new(benchmark_run)
          result = service.call
          expect(result.success?).to be false
        end

        it "still marks run as cancelled for consistency" do
          service = described_class.new(benchmark_run)
          service.call
          expect(benchmark_run.reload.status).to eq("cancelled")
        end
      end
    end
  end

  describe "#build_cancel_command" do
    let(:benchmark_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }

    it "includes the benchmark run UUID" do
      service = described_class.new(benchmark_run)
      cmd = service.send(:build_cancel_command)
      expect(cmd).to include("cancel")
      expect(cmd).to include("--uuid #{benchmark_run.uuid}")
    end

    it "uses default agent path when not specified" do
      service = described_class.new(benchmark_run)
      cmd = service.send(:build_cancel_command)
      expect(cmd).to include("/usr/local/bin/qis-agent")
    end

    it "uses custom agent path when specified" do
      service = described_class.new(benchmark_run, agent_path: "/opt/custom/agent")
      cmd = service.send(:build_cancel_command)
      expect(cmd).to include("/opt/custom/agent cancel")
    end
  end

  describe "#resolve_agent_path" do
    let(:benchmark_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }

    it "resolves relative path by prepending /usr/local/bin" do
      service = described_class.new(benchmark_run, agent_path: "qis-agent")
      expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/qis-agent")
    end

    it "keeps absolute paths unchanged" do
      service = described_class.new(benchmark_run, agent_path: "/opt/bin/qis-agent")
      expect(service.send(:resolve_agent_path)).to eq("/opt/bin/qis-agent")
    end

    it "prepends /usr/local/bin to relative paths" do
      service = described_class.new(benchmark_run, agent_path: "custom-agent")
      expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/custom-agent")
    end
  end

  describe "integration with node agent_path" do
    let(:benchmark_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }

    context "when node has custom agent path" do
      before do
        allow(node).to receive(:agent_path).and_return("/custom/path/agent")
      end

      it "uses node's effective_agent_path" do
        service = described_class.new(benchmark_run)
        expect(service.send(:resolve_agent_path)).to eq("/custom/path/agent")
      end
    end
  end
end
