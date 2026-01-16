# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::InstallJob, type: :job do
  let(:cache_key) { "test_cache_key" }
  let(:credentials) do
    {
      bastion_password: "password",
      sudo_password: "sudo_password"
    }
  end
  let!(:node) { create(:node, hostname: "compute-001", source: :agent_push, arch: "x86_64") }
  let(:params) do
    {
      node: node,
      target_host: "compute-001",
      arch: "x86_64",
      bastion_host: "10.0.0.1",
      bastion_user: "admin",
      credentials_cache_key: cache_key,
      server_url: "http://test.com"
    }
  end

    let(:agent_uuid) { "agent-uuid-12345" }
    let(:install_result) { Agent::RemoteInstallService::Result.new(success: true, agent_uuid: agent_uuid) }
    let(:compiler) { instance_double(Agent::CompilerService, call: "/tmp/hpc-agent") }
    let(:installer) { instance_double(Agent::RemoteInstallService, call: install_result) }

    before do
      allow(Agent::CompilerService).to receive(:new).with(arch: "x86_64").and_return(compiler)
      allow(Agent::RemoteInstallService).to receive(:new).and_return(installer)
      allow(FileUtils).to receive(:rm_f)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(File).to receive(:exist?).and_return(true)
      Rails.cache.write("install_creds_#{cache_key}", credentials)
    end

    it "compiles and installs the agent" do
      described_class.perform_now(**params)

      expect(compiler).to have_received(:call)
      expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
                                                                       bastion_host: "10.0.0.1",
                                                                       bastion_password: "password",
                                                                       sudo_password: "sudo_password",
                                                                       node: node
                                                                     ))
      expect(installer).to have_received(:call)

      node.reload
      expect(node.hostname).to eq("compute-001")
      expect(node.arch).to eq("x86_64")
      expect(node.source).to eq("agent_push")
      expect(node.uuid).to eq(agent_uuid) # UUID synced from agent

      # Verify intermediate broadcasts
      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_install_compute-001",
        hash_including(
          target: "agent_install_status_compute-001",
          locals: hash_including(status: "processing", message: "Compiling Go agent for x86_64")
        )
      )

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_install_compute-001",
        hash_including(
          target: "agent_install_status_compute-001",
          locals: hash_including(status: "success")
        )
      )

      expect(Rails.cache.read("install_creds_#{cache_key}")).to be_nil
    end

    it "sets agent_version to 'dev' after successful install" do
      node.update(agent_version: nil)

      described_class.perform_now(**params)

      node.reload
      expect(node.agent_version).to eq("dev")
    end

    it "syncs both UUID and agent_version after successful install" do
      node.update(uuid: nil, agent_version: nil)

      described_class.perform_now(**params)

      node.reload
      expect(node.uuid).to eq(agent_uuid)
      expect(node.agent_version).to eq("dev")
    end

    context "when agent_uuid is not returned" do
      let(:install_result_no_uuid) { Agent::RemoteInstallService::Result.new(success: true, agent_uuid: nil) }

      before do
        allow(installer).to receive(:call).and_return(install_result_no_uuid)
      end

      it "does not update agent_version when UUID is missing" do
        node.update(agent_version: nil)

        described_class.perform_now(**params)

        node.reload
        # UUID not synced, so agent_version should also not be updated
        expect(node.agent_version).to be_nil
      end
    end
  it "uses custom agent_token from credentials if provided" do
    credentials_with_token = credentials.merge(agent_token: "custom-token-123")
    Rails.cache.write("install_creds_#{cache_key}", credentials_with_token)

    described_class.perform_now(**params)

    expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
                                                                     agent_token: "custom-token-123"
                                                                   ))
  end

  it "handles empty string api_key_id gracefully" do
    # When api_key_id is empty string (e.g. from prompt select), it should NOT try to look it up
    # and should result in nil agent_token (falling back to credentials/env)

    # We deliberately don't put token in credentials here to verify it becomes nil

    described_class.perform_now(**params.merge(api_key_id: ""))

    expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
      agent_token: nil
    ))
  end

  it "broadcasts error if installation fails" do
    allow(installer).to receive(:call).and_raise(Agent::RemoteInstallService::InstallError, "Failed")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Failed"))
    )

    expect(node.reload.source).to eq("manual")
  end

  it "broadcasts error if credentials expired" do
    Rails.cache.delete("install_creds_#{cache_key}")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_install_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Installation failed: Credentials expired or not found. Please try again."))
    )
  end

  context "when api_key_id is provided" do
    let!(:api_key) { create(:api_key, :active) }

    it "uses token from ApiKey record" do
      described_class.perform_now(**params.merge(api_key_id: api_key.id))

      expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
        agent_token: api_key.token
      ))
    end

    it "uses nil when api_key_id does not match any active key" do
      described_class.perform_now(**params.merge(api_key_id: 99999))

      expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
        agent_token: nil
      ))
    end

    it "uses nil when api_key is revoked" do
      revoked_key = create(:api_key, :revoked)

      described_class.perform_now(**params.merge(api_key_id: revoked_key.id))

      expect(Agent::RemoteInstallService).to have_received(:new).with(hash_including(
        agent_token: nil
      ))
    end
  end

  context "cleanup behavior" do
    it "cleans up local binary after successful installation" do
      described_class.perform_now(**params)

      expect(FileUtils).to have_received(:rm_f).with("/tmp/hpc-agent")
    end

    it "cleans up local binary after failed installation" do
      allow(installer).to receive(:call).and_raise(StandardError, "Connection failed")

      described_class.perform_now(**params)

      expect(FileUtils).to have_received(:rm_f).with("/tmp/hpc-agent")
    end

    it "does not attempt cleanup if binary was never created" do
      allow(compiler).to receive(:call).and_raise(StandardError, "Compilation failed")
      allow(File).to receive(:exist?).and_return(false)

      described_class.perform_now(**params)

      expect(FileUtils).not_to have_received(:rm_f)
    end
  end

  context "node source reversion on failure" do
    it "does not revert source if node is nil" do
      allow(installer).to receive(:call).and_raise(StandardError, "Failed")

      expect {
        described_class.perform_now(**params.merge(node: nil))
      }.not_to raise_error

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_install_compute-001",
        hash_including(locals: hash_including(status: "error"))
      )
    end

    it "does not revert source if node is not persisted" do
      unsaved_node = build(:node, hostname: "new-node")
      allow(installer).to receive(:call).and_raise(StandardError, "Failed")

      expect {
        described_class.perform_now(**params.merge(node: unsaved_node))
      }.not_to raise_error
    end
  end
end
