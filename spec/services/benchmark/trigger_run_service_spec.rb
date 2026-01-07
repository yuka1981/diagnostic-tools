# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerRunService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:service) { described_class.new(node) }

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

  let(:ssh_client) { mock_ssh_session(stdout: "Benchmark started") }

  before do
    allow(Net::SSH).to receive(:start).and_yield(ssh_client)
  end

  describe "#call" do
    it "executes the benchmark command via SSH" do
      result = service.call
      expect(result.success?).to be true
      expect(result.output).to eq("Benchmark started")
    end

    it "handles SSH errors" do
      allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "Auth failed")
      result = service.call
      expect(result.success?).to be false
      expect(result.error).to include("SSH error: Auth failed")
    end

    it "handles empty output" do
      ssh_client = mock_ssh_session(stdout: "")
      allow(Net::SSH).to receive(:start).and_yield(ssh_client)
      result = service.call
      expect(result.success?).to be false
      expect(result.error).to eq("Command returned empty output")
    end
  end
end