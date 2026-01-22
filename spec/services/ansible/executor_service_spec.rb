# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ansible::ExecutorService do
  let(:admin_config) do
    {
      host: "admin.example.com",
      user: "ansible",
      playbooks_path: "/opt/playbooks"
    }
  end

  let(:service) do
    described_class.new(
      admin_config: admin_config,
      playbook: "perfspect/report.yml",
      extra_vars: { target_host: "compute-001", run_uuid: "abc-123" }
    )
  end

  describe "#call" do
    context "when SSH execution succeeds" do
      before do
        allow_any_instance_of(SshExecutionService).to receive(:execute_ssh_command)
          .and_return(SshExecutionService::Result.new(success: true, output: "ok", exit_code: 0))
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be true
      end

      it "includes output in result" do
        result = service.call
        expect(result.output).to eq("ok")
      end
    end

    context "when SSH execution fails" do
      before do
        allow_any_instance_of(SshExecutionService).to receive(:execute_ssh_command)
          .and_return(SshExecutionService::Result.new(success: false, error: "Connection refused", exit_code: 1))
      end

      it "returns failure result" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Connection refused")
      end
    end

    context "when an exception is raised" do
      before do
        allow_any_instance_of(SshExecutionService).to receive(:execute_ssh_command)
          .and_raise(StandardError.new("Unexpected error"))
      end

      it "returns failure result with exception message" do
        result = service.call
        expect(result.success?).to be false
        expect(result.error).to include("Unexpected error")
      end
    end
  end

  describe "#build_command" do
    it "builds ansible-playbook command with extra vars" do
      cmd = service.send(:build_command)
      expect(cmd).to include("ansible-playbook")
      expect(cmd).to include("perfspect/report.yml")
      expect(cmd).to include("--extra-vars")
    end

    it "includes the playbooks path from config" do
      cmd = service.send(:build_command)
      expect(cmd).to include("cd /opt/playbooks")
    end

    it "includes extra vars as JSON" do
      cmd = service.send(:build_command)
      expect(cmd).to include("target_host")
      expect(cmd).to include("compute-001")
      expect(cmd).to include("run_uuid")
      expect(cmd).to include("abc-123")
    end

    it "uses default playbooks path when not specified" do
      service_without_path = described_class.new(
        admin_config: { host: "admin.example.com", user: "ansible" },
        playbook: "test.yml",
        extra_vars: {}
      )
      cmd = service_without_path.send(:build_command)
      expect(cmd).to include("cd /opt/ansible")
    end
  end

  describe "#build_admin_node" do
    it "creates admin node with correct hostname" do
      admin_node = service.send(:build_admin_node)
      expect(admin_node.hostname).to eq("admin.example.com")
    end

    it "creates admin node with correct user" do
      admin_node = service.send(:build_admin_node)
      expect(admin_node.ssh_user).to eq("ansible")
    end

    it "uses default port 22 when not specified" do
      admin_node = service.send(:build_admin_node)
      expect(admin_node.ssh_port).to eq(22)
    end

    it "uses custom port when specified" do
      config_with_port = admin_config.merge(port: 2222)
      service_with_port = described_class.new(
        admin_config: config_with_port,
        playbook: "test.yml",
        extra_vars: {}
      )
      admin_node = service_with_port.send(:build_admin_node)
      expect(admin_node.ssh_port).to eq(2222)
    end
  end
end
