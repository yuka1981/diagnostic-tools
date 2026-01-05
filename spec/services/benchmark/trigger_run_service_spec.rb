# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerRunService do
  let(:node) { create(:node, hostname: "test-node", ssh_port: 22, ssh_user: "user") }
  let(:service) { described_class.new(node) }
  let(:ssh_client) { instance_double(Net::SSH::Connection::Session) }

  before do
    allow(Net::SSH).to receive(:start).and_yield(ssh_client)
    allow(ssh_client).to receive(:exec!).and_return("Benchmark started")
  end

  describe "#call" do
    it "executes the benchmark command via SSH" do
      expect(ssh_client).to receive(:exec!).with(/cd hpcg_source && nohup agent hpcg --id hpcg-source-.* > \/dev\/null 2>&1 & echo 'Benchmark started'/)
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
      allow(ssh_client).to receive(:exec!).and_return("")
      result = service.call
      expect(result.success?).to be false
      expect(result.error).to eq("Command returned empty output")
    end
  end
end
