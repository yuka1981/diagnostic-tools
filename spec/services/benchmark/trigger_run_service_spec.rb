# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerRunService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:run_id) { "test-run-123" }
  let(:service) { described_class.new(node, run_id: run_id) }

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

  let(:ssh_client) { mock_ssh_session(stdout: "BENCHMARK_STARTED PID=12345") }

  before do
    allow(Net::SSH).to receive(:start).and_yield(ssh_client)
  end

  describe "#call" do
    context "when benchmark starts successfully" do
      it "returns success with PID information" do
        result = service.call
        expect(result.success?).to be true
        expect(result.output).to include("BENCHMARK_STARTED")
        expect(result.output).to include("PID=12345")
      end
    end

    context "when SSH authentication fails" do
      it "returns error with SSH details" do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Auth failed")
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH authentication failed")
      end

      it "includes error information in output for debugging" do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Auth failed")
        result = service.call
        expect(result.output).to include("SSH Authentication Error")
      end
    end

    context "when command returns empty output" do
      let(:ssh_client) { mock_ssh_session(stdout: "") }

      it "returns error for empty output" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to eq("Command returned empty output")
      end
    end

    context "when working directory is not found" do
      let(:ssh_client) { mock_ssh_session(stdout: "STARTUP_ERROR: Working directory hpcg_source not found") }

      it "returns error indicating missing directory" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Benchmark failed to start")
        expect(result.error).to include("Working directory hpcg_source not found")
      end

      it "preserves SSH output in result for log_content" do
        result = service.call
        expect(result.output).to include("STARTUP_ERROR: Working directory hpcg_source not found")
      end
    end

    context "when agent binary is not found" do
      let(:ssh_client) { mock_ssh_session(stdout: "STARTUP_ERROR: Agent binary not found or not executable at ../hpc-agent") }

      it "returns error indicating missing agent" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Benchmark failed to start")
        expect(result.error).to include("Agent binary not found")
      end
    end

    context "when process exits immediately after starting" do
      let(:ssh_client) do
        mock_ssh_session(stdout: "STARTUP_ERROR: Process exited immediately. Log: Error: invalid flag")
      end

      it "returns error with startup log content" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Benchmark failed to start")
        expect(result.error).to include("Process exited immediately")
      end
    end

    context "when output is unexpected format" do
      let(:ssh_client) { mock_ssh_session(stdout: "Some random output") }

      it "returns error for unexpected output" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Unexpected output")
      end
    end

    context "when SSH command has stderr output" do
      let(:ssh_client) { mock_ssh_session(stdout: "BENCHMARK_STARTED PID=12345", stderr: "Warning: something happened") }

      it "includes stderr in output for debugging" do
        result = service.call
        expect(result.success?).to be true
        expect(result.output).to include("Warning: something happened")
        expect(result.output).to include("SSH Stderr")
      end
    end
  end

  describe "#direct_command" do
    it "includes working directory validation with default" do
      command = service.send(:direct_command)
      expect(command).to include("if [ ! -d hpcg_source ]")
      expect(command).to include("Working directory hpcg_source not found")
    end

    it "uses custom work directory from node" do
      node.update!(benchmark_work_dir: "/opt/benchmarks/hpcg")
      custom_service = described_class.new(node, run_id: run_id)
      command = custom_service.send(:direct_command)
      expect(command).to include("if [ ! -d /opt/benchmarks/hpcg ]")
      expect(command).to include("cd /opt/benchmarks/hpcg")
    end

    it "includes agent binary validation" do
      command = service.send(:direct_command)
      expect(command).to include("if [ ! -x")
      expect(command).to include("Agent binary not found")
    end

    it "includes process startup validation with sleep" do
      command = service.send(:direct_command)
      expect(command).to include("sleep 2")
      expect(command).to include("kill -0 $HPCG_PID")
    end

    it "captures startup log to temp file" do
      command = service.send(:direct_command)
      expect(command).to include("/tmp/hpcg_startup_#{run_id}.log")
    end

    it "outputs structured success message with PID" do
      command = service.send(:direct_command)
      expect(command).to include("BENCHMARK_STARTED PID=")
    end
  end

  describe "#resolve_agent_path" do
    it "resolves default hpc-agent to parent directory" do
      service = described_class.new(node, agent_path: "hpc-agent")
      expect(service.send(:resolve_agent_path)).to eq("../hpc-agent")
    end

    it "keeps absolute paths unchanged" do
      service = described_class.new(node, agent_path: "/usr/local/bin/hpc-agent")
      expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/hpc-agent")
    end

    it "prepends parent directory to relative paths" do
      service = described_class.new(node, agent_path: "bin/hpc-agent")
      expect(service.send(:resolve_agent_path)).to eq("../bin/hpc-agent")
    end
  end

  describe "#build_agent_command" do
    it "includes run_id" do
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--id #{run_id}")
    end

    it "includes server URL when provided" do
      service = described_class.new(node, run_id: run_id, server_url: "https://example.com")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--server")
      expect(cmd).to include("https://example.com")
    end

    it "includes token when provided" do
      service = described_class.new(node, run_id: run_id, agent_token: "secret-token")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--token")
    end

    it "includes log path when provided" do
      service = described_class.new(node, run_id: run_id, log_path: "/var/log/hpcg")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--log-path")
      expect(cmd).to include("/var/log/hpcg")
    end
  end
end
