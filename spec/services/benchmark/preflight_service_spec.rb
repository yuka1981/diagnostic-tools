# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::PreflightService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:service) { described_class.new(node) }

  def mock_ssh_session(stdout: "SSH_OK", stderr: "", exit_code: 0)
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
    context "when all checks pass" do
      before do
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "HPCG_READY")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "returns success" do
        result = service.call
        expect(result.success?).to be true
      end

      it "returns all checks as passed" do
        result = service.call
        expect(result.checks).to all(have_attributes(passed: true))
      end

      it "includes configuration info" do
        result = service.call
        expect(result.config[:work_dir]).to eq(BenchmarkConfig::DEFAULT_WORK_DIR)
        expect(result.config[:work_dir_source]).to eq(:default)
      end
    end

    context "when SSH connection fails" do
      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Auth failed")
      end

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
      end

      it "includes SSH check failure" do
        result = service.call
        ssh_check = result.checks.find { |c| c.name == "SSH Connectivity" }
        expect(ssh_check.passed).to be false
      end
    end

    context "when working directory does not exist" do
      before do
        # First call returns SSH_OK, second returns DIR_NOT_FOUND, third returns AGENT_NOT_FOUND
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_NOT_FOUND")
            when 3 then data_block.call(mock_channel, "AGENT_NOT_FOUND")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "returns failure" do
        result = service.call
        expect(result.success?).to be false
      end

      it "includes working directory check failure" do
        result = service.call
        dir_check = result.checks.find { |c| c.name == "Working Directory" }
        expect(dir_check.passed).to be false
        expect(dir_check.message).to include("not found")
      end

      it "provides helpful details for fixing" do
        result = service.call
        dir_check = result.checks.find { |c| c.name == "Working Directory" }
        expect(dir_check.details).to include("Settings")
      end
    end

    context "when node has custom work_dir" do
      before do
        node.update!(benchmark_work_dir: "/custom/benchmark/path")
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "HPCG_READY")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "uses the node's work_dir" do
        result = service.call
        expect(result.config[:work_dir]).to eq("/custom/benchmark/path")
        expect(result.config[:work_dir_source]).to eq(:node)
      end
    end

    context "when global work_dir is set" do
      before do
        SshSetting.current.update!(benchmark_work_dir: "/global/benchmark")
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "HPCG_READY")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "uses the global work_dir" do
        result = service.call
        expect(result.config[:work_dir]).to eq("/global/benchmark")
        expect(result.config[:work_dir_source]).to eq(:global)
      end
    end
  end

  describe "HPCG source check" do
    context "when HPCG source is properly set up" do
      before do
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "HPCG_READY")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "returns success for HPCG source check" do
        result = service.call
        hpcg_check = result.checks.find { |c| c.name == "HPCG Source" }
        expect(hpcg_check.passed).to be true
        expect(hpcg_check.message).to include("properly configured")
      end
    end

    context "when HPCG source is not cloned" do
      before do
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "NO_SOURCE")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "passes with auto-clone message (agent will clone automatically)" do
        result = service.call
        hpcg_check = result.checks.find { |c| c.name == "HPCG Source" }
        expect(hpcg_check.passed).to be true
        expect(hpcg_check.message).to include("cloned automatically")
        expect(hpcg_check.details).to include("hpcg-benchmark")
      end
    end

    context "when Make.Linux_Serial is missing" do
      before do
        call_count = 0
        ssh_client = mock_ssh_session(stdout: "")
        allow(ssh_client).to receive(:open_channel) do |&block|
          call_count += 1
          mock_channel = instance_double(Net::SSH::Connection::Channel)
          allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
          allow(mock_channel).to receive(:on_data) do |&data_block|
            case call_count
            when 1 then data_block.call(mock_channel, "SSH_OK")
            when 2 then data_block.call(mock_channel, "DIR_EXISTS")
            when 3 then data_block.call(mock_channel, "NO_MAKE_CONFIG")
            when 4 then data_block.call(mock_channel, "AGENT_OK")
            end
          end
          allow(mock_channel).to receive(:on_extended_data)
          allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
          allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
          block.call(mock_channel)
        end
        allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      end

      it "returns failure with re-run suggestion" do
        result = service.call
        hpcg_check = result.checks.find { |c| c.name == "HPCG Source" }
        expect(hpcg_check.passed).to be false
        expect(hpcg_check.message).to include("build configuration not found")
        expect(hpcg_check.details).to include("Delete the directory")
      end
    end
  end

  describe "#token_source" do
    context "when node has direct api_token" do
      let(:node) { create(:node, hostname: "token-node", api_token: "direct-token") }
      let(:service) { described_class.new(node) }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "test")
      end

      it "returns :node as token_source" do
        result = service.call
        expect(result.config[:token_source]).to eq(:node)
      end
    end

    context "when node has ApiKey association" do
      let(:api_key) { create(:api_key) }
      let(:node) { create(:node, hostname: "apikey-node", api_key: api_key) }
      let(:service) { described_class.new(node) }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "test")
      end

      it "returns :node as token_source" do
        result = service.call
        expect(result.config[:token_source]).to eq(:node)
      end
    end

    context "when node has no token but global token is provided" do
      let(:node) { create(:node, hostname: "no-token-node", api_token: nil, api_key: nil) }
      let(:service) { described_class.new(node, agent_token: "global-token") }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "test")
      end

      it "returns :global as token_source" do
        result = service.call
        expect(result.config[:token_source]).to eq(:global)
      end
    end

    context "when no token is configured anywhere" do
      let(:node) { create(:node, hostname: "empty-token-node", api_token: nil, api_key: nil) }
      let(:service) { described_class.new(node) }

      before do
        allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "test")
      end

      it "returns :none as token_source" do
        result = service.call
        expect(result.config[:token_source]).to eq(:none)
      end
    end
  end

  describe "#failed_checks" do
    before do
      call_count = 0
      ssh_client = mock_ssh_session(stdout: "")
      allow(ssh_client).to receive(:open_channel) do |&block|
        call_count += 1
        mock_channel = instance_double(Net::SSH::Connection::Channel)
        allow(mock_channel).to receive(:exec).and_yield(mock_channel, true)
        allow(mock_channel).to receive(:on_data) do |&data_block|
          case call_count
          when 1 then data_block.call(mock_channel, "SSH_OK")
          when 2 then data_block.call(mock_channel, "DIR_NOT_FOUND")
          when 3 then data_block.call(mock_channel, "AGENT_NOT_FOUND")
          end
        end
        allow(mock_channel).to receive(:on_extended_data)
        allow(mock_channel).to receive(:on_request).with("exit-status").and_yield(mock_channel, double(read_long: 0))
        allow(mock_channel).to receive(:on_request).with("exit-signal").and_yield(mock_channel, double(read_long: nil))
        block.call(mock_channel)
      end
      allow(Net::SSH).to receive(:start).and_yield(ssh_client)
    end

    it "returns only failed checks" do
      result = service.call
      failed = result.failed_checks
      expect(failed.length).to eq(2)
      expect(failed.map(&:name)).to contain_exactly("Working Directory", "Agent Binary")
    end
  end
end
