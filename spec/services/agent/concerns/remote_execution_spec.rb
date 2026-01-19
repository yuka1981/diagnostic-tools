# frozen_string_literal: true

require "rails_helper"
require_relative "../../../../app/services/agent/errors"
require_relative "../../../../app/services/agent/concerns/remote_execution"

# Test class to include the concern
class TestExecutionService
  include Agent::Concerns::RemoteExecution

  attr_accessor :node, :ssh_password, :sudo_password, :on_progress

  def initialize(node:, ssh_password: nil, sudo_password: nil)
    @node = node
    @ssh_password = ssh_password
    @sudo_password = sudo_password
  end
end

RSpec.describe Agent::Concerns::RemoteExecution do
  let(:node) { create(:node, :direct, hostname: "test-node", ip: "192.168.1.100") }
  let(:service) { TestExecutionService.new(node: node) }

  describe "#localhost_target?" do
    it "returns true for 127.0.0.1" do
      node.update_column(:ip, "127.0.0.1")
      expect(service.localhost_target?).to be true
    end

    it "returns true for localhost hostname" do
      node.update_columns(ip: nil, hostname: "localhost")
      expect(service.localhost_target?).to be true
    end

    it "returns true for ::1 IPv6" do
      node.update_column(:ip, "::1")
      expect(service.localhost_target?).to be true
    end

    it "returns false for regular IP" do
      expect(service.localhost_target?).to be false
    end
  end

  describe "#use_bastion?" do
    context "with direct connection" do
      let(:node) { create(:node, :direct) }

      it "returns false" do
        expect(service.use_bastion?).to be false
      end
    end

    context "with custom bastion and jump_host" do
      let(:node) { create(:node, :custom_bastion, jump_host: "jump.example.com") }

      it "returns true" do
        expect(service.use_bastion?).to be true
      end
    end

    context "with localhost" do
      let(:node) { build_stubbed(:node, :global_bastion, ip: "127.0.0.1") }

      it "returns false even for bastion mode" do
        expect(service.use_bastion?).to be false
      end
    end
  end

  describe "#resolve_credentials" do
    let(:cache_key) { "lifecycle_creds_test123" }

    it "uses cached credentials when available" do
      Rails.cache.write(cache_key, { ssh_password: "cached_ssh", sudo_password: "cached_sudo" }, expires_in: 5.minutes)
      service.resolve_credentials(cache_key: cache_key)
      expect(service.ssh_password).to eq("cached_ssh")
      expect(service.sudo_password).to eq("cached_sudo")
    end

    it "falls back to node credentials when cache empty" do
      node.update!(ssh_password: "node_ssh", sudo_credential: "node_sudo")
      service.resolve_credentials(cache_key: "nonexistent")
      expect(service.ssh_password).to eq("node_ssh")
      expect(service.sudo_password).to eq("node_sudo")
    end

    it "uses ssh_password as sudo fallback" do
      node.update!(ssh_password: "shared_pass", sudo_credential: nil)
      service.resolve_credentials(cache_key: "nonexistent")
      expect(service.sudo_password).to eq("shared_pass")
    end
  end

  describe "#ssh_user" do
    it "uses node's ssh_user when present" do
      node.ssh_user = "custom_user"
      expect(service.ssh_user).to eq("custom_user")
    end

    it "falls back to SshConfig user" do
      node.ssh_user = nil
      allow(SshConfig).to receive(:user).and_return("config_user")
      expect(service.ssh_user).to eq("config_user")
    end

    it "defaults to root" do
      node.ssh_user = nil
      allow(SshConfig).to receive(:user).and_return(nil)
      expect(service.ssh_user).to eq("root")
    end
  end

  describe "#report_progress" do
    it "calls on_progress callback when set" do
      messages = []
      service.on_progress = ->(msg) { messages << msg }
      service.report_progress("Test message")
      expect(messages).to include("Test message")
    end

    it "broadcasts to ActionCable when node persisted" do
      expect(ActionCable.server).to receive(:broadcast).with(
        "node_logs_#{node.id}",
        hash_including(log: /Test message/, stream: "meta")
      )
      service.report_progress("Test message")
    end
  end

  describe "#generate_service_file" do
    it "generates valid systemd service file content" do
      content = service.generate_service_file(
        server_url: "https://example.com",
        api_token: "test_token",
        node_uuid: "test-uuid-1234",
        inventory_interval: 120,
        heartbeat_interval: 30
      )

      expect(content).to include("[Unit]")
      expect(content).to include("[Service]")
      expect(content).to include("[Install]")
      expect(content).to include("start --server")
      expect(content).to include("--server \"https://example.com\"")
      expect(content).to include("--token \"test_token\"")
      expect(content).to include("--node-uuid \"test-uuid-1234\"")
      expect(content).to include("--heartbeat-interval 30s")
      expect(content).to include("--inventory-interval 120s")
    end
  end

  describe "#set_selinux_context" do
    let(:mock_ssh) { instance_double(Net::SSH::Connection::Session) }

    it "runs restorecon command" do
      expect(service).to receive(:execute_command).with(
        mock_ssh,
        /restorecon.*chcon -t bin_t/,
        password: anything
      )
      service.set_selinux_context(mock_ssh, "/usr/local/bin/hpc-agent", type: "bin_t")
    end
  end
end
