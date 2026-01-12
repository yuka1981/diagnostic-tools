# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::TriggerCollectService, type: :service do
  let(:node) { create(:node, hostname: "test-node") }
  let(:service) { described_class.new(node) }

  describe "#process_result" do
    it "successfully parses JSON from stdout even if stderr has warnings" do
      json_output = { host: { hostname: "test-node" } }.to_json
      warning_output = "2026/01/08 12:10:41 Warning: failed to collect DMI information: exit status 1"

      result = SshExecutionService::Result.new(
        success: true,
        output: json_output,
        error: warning_output
      )

      processed = service.send(:process_result, result)

      expect(processed.success?).to be true
      expect(processed.output[:host][:hostname]).to eq("test-node")
    end

    it "reports an error if JSON parsing fails" do
      result = SshExecutionService::Result.new(
        success: true,
        output: "Not a JSON",
        error: "Some error"
      )

      processed = service.send(:process_result, result)

      expect(processed.success?).to be false
      expect(processed.error).to include("JSON parse error")
      expect(processed.error).to include("Some error")
      expect(processed.error).to include("Not a JSON")
    end
  end

  describe "#execute_ssh_command" do
    let(:gateway) { create(:node, hostname: "gateway-node") }
    let(:target_node) { create(:node, hostname: "target-node", ip: "192.168.1.100") }
    let(:service_with_gateway) { described_class.new(target_node, gateway: gateway) }

    it "uses node IP for nested SSH command when using legacy gateway" do
      # Mock the super call (SshExecutionService#execute_ssh_command)
      # We can't easily mock super, but we can verify what's passed to it by mocking where it goes.
      # SshExecutionService calls Net::SSH.start

      # We expect the command string passed to the gateway to use the IP
      expected_ssh_cmd = "ssh 192.168.1.100 hpc-agent collect --json"

      # Allow connection to gateway
      ssh_session = instance_double(Net::SSH::Connection::Session)
      channel = instance_double(Net::SSH::Connection::Channel)

      allow(Net::SSH).to receive(:start).with(gateway.ip, any_args).and_yield(ssh_session)
      allow(ssh_session).to receive(:loop)
      allow(ssh_session).to receive(:open_channel).and_yield(channel)

      # Verify the command executed on the gateway includes the target IP
      expect(channel).to receive(:exec).with(expected_ssh_cmd).and_yield(channel, true)
      allow(channel).to receive(:on_data)
      allow(channel).to receive(:on_extended_data)
      allow(channel).to receive(:on_request)

      service_with_gateway.call
    end
  end
end
