# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshExecutionService, type: :service do
  let(:node) { create(:node, hostname: "localhost", ip: "127.0.0.1") }
  let(:service) { described_class.new(node) }

  describe "#execute_on_session" do
    let(:session) { instance_double(Net::SSH::Connection::Session) }
    let(:channel) { instance_double(Net::SSH::Connection::Channel) }

    before do
      allow(session).to receive(:open_channel).and_yield(channel)
      allow(channel).to receive(:exec).and_yield(channel, true)
      allow(session).to receive(:loop)
    end

    it "correctly captures stdout and stderr" do
      # Simulate stdout data
      allow(channel).to receive(:on_data).and_yield(channel, "some stdout")

      # Simulate stderr data (extended data)
      # Net::SSH yields (channel, type, data)
      allow(channel).to receive(:on_extended_data).and_yield(channel, 1, "some stderr")

      # Simulate exit status
      allow(channel).to receive(:on_request).with("exit-status").and_yield(channel, double(read_long: 0))
      allow(channel).to receive(:on_request).with("exit-signal")

      result = service.send(:execute_on_session, session, "ls")

      expect(result.success?).to be true
      expect(result.output).to eq("some stdout")
      expect(result.error).to eq("some stderr")
    end
  end

  describe "#ssh_options" do
    it "includes password from node if present" do
      node.sudo_credential = "secret"
      service_with_password = described_class.new(node)
      options = service_with_password.send(:ssh_options)
      expect(options[:password]).to eq("secret")
    end

    it "includes key_data from node if present" do
      node.ssh_key = "private_key_content"
      service_with_key = described_class.new(node)
      options = service_with_key.send(:ssh_options)
      expect(options[:key_data]).to include("private_key_content")
    end
  end
end
