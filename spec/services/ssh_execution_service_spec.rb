# frozen_string_literal: true

require "rails_helper"

RSpec.describe SshExecutionService, type: :service do
  let(:node) { build_stubbed(:node, hostname: "localhost", ip: "127.0.0.1") }
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
    it "includes password from node if override is enabled" do
      node_with_override = build_stubbed(:node, sudo_credential: "secret", sudo_credential_override: true)
      service_with_password = described_class.new(node_with_override)
      options = service_with_password.send(:ssh_options)
      expect(options[:password]).to eq("secret")
    end

    it "includes key_data from node if override is enabled" do
      node_with_key = build_stubbed(:node, ssh_key: "private_key_content", ssh_key_override: true)
      service_with_key = described_class.new(node_with_key)
      options = service_with_key.send(:ssh_options)
      expect(options[:key_data]).to include("private_key_content")
    end
  end

  describe "#localhost_target?" do
    it "returns true for 127.0.0.1 IP" do
      localhost_node = build_stubbed(:node, ip: "127.0.0.1", hostname: "test-host")
      service = described_class.new(localhost_node)
      expect(service.send(:localhost_target?)).to be true
    end

    it "returns true for localhost hostname" do
      localhost_node = build_stubbed(:node, ip: nil, hostname: "localhost")
      service = described_class.new(localhost_node)
      expect(service.send(:localhost_target?)).to be true
    end

    it "returns true for ::1 IPv6 localhost" do
      ipv6_node = build_stubbed(:node, ip: "::1", hostname: "test-host")
      service = described_class.new(ipv6_node)
      expect(service.send(:localhost_target?)).to be true
    end

    it "returns false for remote IP" do
      remote_node = create(:node, ip: "192.168.1.100", hostname: "remote-host")
      service = described_class.new(remote_node)
      expect(service.send(:localhost_target?)).to be false
    end

    it "returns false for remote hostname" do
      remote_node = create(:node, ip: nil, hostname: "remote.example.com")
      service = described_class.new(remote_node)
      expect(service.send(:localhost_target?)).to be false
    end
  end

  describe "#execute_local" do
    let(:localhost_node) { build_stubbed(:node, ip: "127.0.0.1", hostname: "localhost") }
    let(:local_service) { described_class.new(localhost_node) }

    it "executes command locally using Open3" do
      allow(Open3).to receive(:capture3).with("echo hello").and_return([ "hello\n", "", instance_double(Process::Status, success?: true, exitstatus: 0) ])

      result = local_service.send(:execute_local, "echo hello")

      expect(result.success?).to be true
      expect(result.output).to eq("hello\n")
      expect(result.exit_code).to eq(0)
    end

    it "captures stderr for failed commands" do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3).with("false_cmd").and_return([ "", "command not found", status ])

      result = local_service.send(:execute_local, "false_cmd")

      expect(result.success?).to be false
      expect(result.error).to eq("command not found")
      expect(result.exit_code).to eq(1)
    end

    it "yields stdout to block when provided" do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return([ "output data", "", status ])

      yielded_data = []
      local_service.send(:execute_local, "test") do |data, stream|
        yielded_data << [ data, stream ]
      end

      expect(yielded_data).to include([ "output data", :stdout ])
    end

    it "yields stderr to block when provided" do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return([ "", "error data", status ])

      yielded_data = []
      local_service.send(:execute_local, "test") do |data, stream|
        yielded_data << [ data, stream ]
      end

      expect(yielded_data).to include([ "error data", :stderr ])
    end

    it "handles exceptions gracefully" do
      allow(Open3).to receive(:capture3).and_raise(StandardError.new("Execution failed"))

      result = local_service.send(:execute_local, "bad_command")

      expect(result.success?).to be false
      expect(result.error).to eq("Execution failed")
    end

    it "sets exit_signal to nil for local execution" do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return([ "", "", status ])

      result = local_service.send(:execute_local, "test")

      expect(result.exit_signal).to be_nil
    end
  end

  describe "#execute_ssh_command routing" do
    context "when target is localhost" do
      let(:localhost_node) { build_stubbed(:node, ip: "127.0.0.1", hostname: "localhost") }
      let(:local_service) { described_class.new(localhost_node) }

      it "routes to execute_local instead of SSH" do
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        allow(Open3).to receive(:capture3).and_return([ "", "", status ])

        # Should NOT call Net::SSH.start
        expect(Net::SSH).not_to receive(:start)

        local_service.send(:execute_ssh_command, "test_command")
      end
    end

    context "when target is remote" do
      let(:remote_node) { create(:node, :direct, ip: "192.168.1.100", hostname: "remote") }
      let(:remote_service) { described_class.new(remote_node) }

      it "routes to execute_direct for SSH" do
        expect(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)

        expect { remote_service.send(:execute_ssh_command, "test_command") }.to raise_error(Errno::ECONNREFUSED)
      end
    end
  end
end
