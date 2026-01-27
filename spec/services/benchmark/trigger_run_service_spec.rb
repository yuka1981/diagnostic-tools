# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerRunService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:run_id) { "test-run-123" }
  let(:recipe) { create(:benchmark_recipe, :hpcg) }
  let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: recipe) }

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

    context "when SSH connection times out" do
      it "returns error for connection timeout" do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::ConnectionTimeout, "Connection timed out")
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH connection timeout")
      end

      it "returns error for Errno::ETIMEDOUT" do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ETIMEDOUT)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH connection timeout")
      end
    end

    context "when SSH connection is refused" do
      it "returns error with connection refused details" do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH connection refused")
        expect(result.output).to include("SSH Connection Refused")
      end
    end

    context "when host is unreachable" do
      it "returns error for EHOSTUNREACH" do
        allow(Net::SSH).to receive(:start).and_raise(Errno::EHOSTUNREACH)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH host unreachable")
        expect(result.output).to include("Host Unreachable")
      end

      it "returns error for ENETUNREACH" do
        allow(Net::SSH).to receive(:start).and_raise(Errno::ENETUNREACH)
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH host unreachable")
      end
    end

    context "when DNS/socket error occurs" do
      it "returns error for SocketError" do
        allow(Net::SSH).to receive(:start).and_raise(SocketError, "getaddrinfo: Name or service not known")
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH DNS/socket error")
        expect(result.output).to include("DNS/Socket Error")
      end
    end

    context "when generic SSH error occurs" do
      it "returns error for Net::SSH::Exception" do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::Exception, "Key exchange failed")
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH error")
        expect(result.output).to include("SSH Error")
      end
    end

    context "when unexpected error occurs" do
      it "returns error for StandardError" do
        allow(Net::SSH).to receive(:start).and_raise(StandardError, "Something unexpected")
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Unexpected error")
        expect(result.output).to include("Unexpected Error")
      end
    end

    context "when SSH command fails with non-zero exit code" do
      let(:ssh_client) { mock_ssh_session(stdout: "some output", stderr: "error occurred", exit_code: 1) }

      it "returns error with exit code details" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("SSH command failed")
        expect(result.error).to include("exit_code=1")
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
      service = described_class.new(node, agent_path: "hpc-agent", benchmark_recipe: recipe)
      expect(service.send(:resolve_agent_path)).to eq("../hpc-agent")
    end

    it "keeps absolute paths unchanged" do
      service = described_class.new(node, agent_path: "/usr/local/bin/hpc-agent", benchmark_recipe: recipe)
      expect(service.send(:resolve_agent_path)).to eq("/usr/local/bin/hpc-agent")
    end

    it "prepends parent directory to relative paths" do
      service = described_class.new(node, agent_path: "bin/hpc-agent", benchmark_recipe: recipe)
      expect(service.send(:resolve_agent_path)).to eq("../bin/hpc-agent")
    end
  end

  describe "#build_agent_command" do
    it "includes run_id" do
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--id #{run_id}")
    end

    it "includes server URL when provided" do
      service = described_class.new(node, run_id: run_id, benchmark_recipe: recipe, server_url: "https://example.com")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--server")
      expect(cmd).to include("https://example.com")
    end

    it "includes token when provided" do
      service = described_class.new(node, run_id: run_id, benchmark_recipe: recipe, agent_token: "secret-token")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--token")
    end

    it "includes log path when provided" do
      service = described_class.new(node, run_id: run_id, benchmark_recipe: recipe, log_path: "/var/log/hpcg")
      cmd = service.send(:build_agent_command, "../hpc-agent")
      expect(cmd).to include("--log-path")
      expect(cmd).to include("/var/log/hpcg")
    end

    context "with recipe" do
      it "uses recipe command as subcommand" do
        cmd = service.send(:build_agent_command, "../hpc-agent")
        expect(cmd).to include(" hpcg")
      end

      it "uses recipe timeout when provided" do
        recipe.update!(timeout_seconds: 7200)
        cmd = service.send(:build_agent_command, "../hpc-agent")
        expect(cmd).to include("--rt 7200")
      end

      it "uses recipe default profile values" do
        cmd = service.send(:build_agent_command, "../hpc-agent")
        expect(cmd).to include("--nx=104")
        expect(cmd).to include("--ny=104")
        expect(cmd).to include("--nz=104")
      end
    end

    context "with argument overrides" do
      let(:overrides) { { "nx" => 128, "ny" => 128 } }
      let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: recipe, argument_overrides: overrides) }

      it "merges overrides with recipe defaults" do
        cmd = service.send(:build_agent_command, "../hpc-agent")
        expect(cmd).to include("--nx=128")
        expect(cmd).to include("--ny=128")
        expect(cmd).to include("--nz=104") # From default
      end

      it "excludes array values from CLI flags" do
        # The recipe has "modules" as array which should be excluded
        cmd = service.send(:build_agent_command, "../hpc-agent")
        expect(cmd).not_to include("--modules")
      end
    end
  end

  describe "#exit_code_hint" do
    it "returns hint for general error (1)" do
      expect(service.send(:exit_code_hint, 1)).to include("general error")
    end

    it "returns hint for permission denied (126)" do
      expect(service.send(:exit_code_hint, 126)).to include("permission denied")
    end

    it "returns hint for command not found (127)" do
      expect(service.send(:exit_code_hint, 127)).to include("command not found")
    end

    it "returns hint for SIGKILL (137)" do
      expect(service.send(:exit_code_hint, 137)).to include("SIGKILL")
    end

    it "returns hint for segmentation fault (139)" do
      expect(service.send(:exit_code_hint, 139)).to include("segmentation fault")
    end

    it "returns hint for SSH error (255)" do
      expect(service.send(:exit_code_hint, 255)).to include("SSH error")
    end

    it "returns nil for unknown exit codes" do
      expect(service.send(:exit_code_hint, 42)).to be_nil
    end
  end

  describe "#build_error_detail" do
    it "returns message for nil result" do
      expect(service.send(:build_error_detail, nil)).to eq("No result returned")
    end

    it "includes exit code in detail" do
      result = double(exit_code: 127, exit_signal: nil, error: "", output: "")
      detail = service.send(:build_error_detail, result)
      expect(detail).to include("exit_code=127")
      expect(detail).to include("command not found")
    end

    it "includes exit signal when present" do
      result = double(exit_code: nil, exit_signal: "KILL", error: "", output: "")
      detail = service.send(:build_error_detail, result)
      expect(detail).to include("signal=KILL")
    end

    it "prefers stderr over stdout" do
      result = double(exit_code: 1, exit_signal: nil, error: "Stderr message", output: "Stdout message")
      detail = service.send(:build_error_detail, result)
      expect(detail).to include("Stderr message")
    end

    it "falls back to stdout when stderr is empty" do
      result = double(exit_code: 1, exit_signal: nil, error: "", output: "First line\nSecond line")
      detail = service.send(:build_error_detail, result)
      expect(detail).to include("stdout: First line")
    end
  end

  describe "#build_log_content" do
    it "returns empty string for nil result" do
      expect(service.send(:build_log_content, nil)).to eq("")
    end

    it "includes SSH connection info" do
      result = double(exit_code: 0, exit_signal: nil, error: "", output: "test")
      content = service.send(:build_log_content, result)
      expect(content).to include("=== SSH Connection Info ===")
      expect(content).to include("Target:")
      expect(content).to include("Working Dir:")
    end

    it "includes exit status when present" do
      result = double(exit_code: 0, exit_signal: nil, error: "", output: "test")
      content = service.send(:build_log_content, result)
      expect(content).to include("=== Exit Status ===")
      expect(content).to include("Exit Code: 0")
    end

    it "includes stdout section" do
      result = double(exit_code: 0, exit_signal: nil, error: "", output: "command output")
      content = service.send(:build_log_content, result)
      expect(content).to include("=== SSH Stdout ===")
      expect(content).to include("command output")
    end

    it "includes stderr section when present" do
      result = double(exit_code: 0, exit_signal: nil, error: "warning message", output: "output")
      content = service.send(:build_log_content, result)
      expect(content).to include("=== SSH Stderr ===")
      expect(content).to include("warning message")
    end
  end

  describe "#merged_arguments" do
    context "with recipe defaults only" do
      it "returns recipe default profile" do
        args = service.send(:merged_arguments)
        expect(args["nx"]).to eq(104)
        expect(args["ny"]).to eq(104)
        expect(args["nz"]).to eq(104)
      end
    end

    context "with argument overrides" do
      let(:overrides) { { "nx" => 256, "custom_flag" => "value" } }
      let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: recipe, argument_overrides: overrides) }

      it "merges overrides with recipe defaults" do
        args = service.send(:merged_arguments)
        expect(args["nx"]).to eq(256) # Override
        expect(args["ny"]).to eq(104) # Default
        expect(args["custom_flag"]).to eq("value") # New from override
      end
    end

    context "without recipe" do
      let(:service) { described_class.new(node, run_id: run_id) }

      it "returns empty hash when no recipe provided" do
        args = service.send(:merged_arguments)
        expect(args).to eq({})
      end
    end
  end

  describe "#command_builder_class" do
    context "with HPCG recipe" do
      let(:hpcg_recipe) { create(:benchmark_recipe, command: "hpcg") }
      let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: hpcg_recipe) }

      it "returns HpcgCommandBuilder" do
        expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::HpcgCommandBuilder)
      end
    end

    context "with MLC recipe" do
      let(:mlc_recipe) { create(:benchmark_recipe, command: "mlc") }
      let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: mlc_recipe) }

      it "returns MlcCommandBuilder" do
        expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::MlcCommandBuilder)
      end
    end

    context "without recipe" do
      let(:service) { described_class.new(node, run_id: run_id) }

      it "defaults to HpcgCommandBuilder for backward compatibility" do
        expect(service.send(:command_builder_class)).to eq(Benchmark::CommandBuilders::HpcgCommandBuilder)
      end
    end

    context "with unknown command" do
      let(:unknown_recipe) { create(:benchmark_recipe, command: "unknown_benchmark") }
      let(:service) { described_class.new(node, run_id: run_id, benchmark_recipe: unknown_recipe) }

      it "raises ArgumentError" do
        expect { service.send(:command_builder_class) }.to raise_error(ArgumentError, /Unknown benchmark command: unknown_benchmark/)
      end
    end
  end
end
