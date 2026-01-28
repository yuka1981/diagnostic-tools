require "rails_helper"

RSpec.describe Mlc::TriggerInstallService do
  let(:node) { create(:node, :online, :direct) }
  let(:installation) do
    create(:mlc_installation,
      source_path: "/tmp/mlc.tgz",
      binary_path: "Linux/mlc",
      install_dir: "/opt/qct/utils/qis/software",
      module_dir: "/opt/qct/utils/qis/modulefiles"
    )
  end
  let(:installation_node) { create(:mlc_installation_node, mlc_installation: installation, node: node) }

  describe "#build_agent_command" do
    subject(:service) do
      described_class.new(
        installation: installation,
        installation_node: installation_node,
        server_url: "http://localhost:3000",
        agent_token: "test-token"
      )
    end

    it "builds correct agent command" do
      command = service.send(:build_agent_command)

      expect(command).to include("mlc-install")
      expect(command).to include("--tarball")
      expect(command).to include("/tmp/mlc.tgz")
      expect(command).to include("--binary-path")
      expect(command).to include("Linux/mlc")
      expect(command).to include("--server")
      expect(command).to include("http://localhost:3000")
    end

    it "includes install and module directories" do
      command = service.send(:build_agent_command)

      expect(command).to include("--install-dir")
      expect(command).to include("/opt/qct/utils/qis/software")
      expect(command).to include("--module-dir")
      expect(command).to include("/opt/qct/utils/qis/modulefiles")
    end

    it "includes installation ID" do
      command = service.send(:build_agent_command)

      expect(command).to include("--id")
      expect(command).to include(installation.uuid)
    end
  end

  describe "#build_ssh_command" do
    subject(:service) do
      described_class.new(
        installation: installation,
        installation_node: installation_node,
        server_url: "http://localhost:3000",
        agent_token: "test-token"
      )
    end

    it "checks agent binary exists" do
      command = service.send(:build_ssh_command)

      expect(command).to include("if [ ! -x")
      expect(command).to include("STARTUP_ERROR: Agent binary not found")
    end

    it "runs installation in background with nohup" do
      command = service.send(:build_ssh_command)

      expect(command).to include("nohup")
      expect(command).to include("&")
    end

    it "verifies process started successfully" do
      command = service.send(:build_ssh_command)

      expect(command).to include("INSTALL_STARTED")
      expect(command).to include("kill -0")
    end
  end
end
