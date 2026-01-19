# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UninstallJob, type: :job do
  let(:cache_key) { "test_cache_key" }
  let(:credentials) do
    {
      bastion_password: "password",
      sudo_password: "sudo_password"
    }
  end
  let(:params) do
    {
      target_host: "compute-001",
      bastion_host: "10.0.0.1",
      bastion_user: "admin",
      credentials_cache_key: cache_key
    }
  end

  let(:uninstaller) { instance_double(Agent::RemoteUninstallService, call: true) }

  before do
    allow(Agent::RemoteUninstallService).to receive(:new).and_return(uninstaller)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    Rails.cache.write("install_creds_#{cache_key}", credentials)
  end

  it "uninstalls the agent" do
    described_class.perform_now(**params)

    expect(Agent::RemoteUninstallService).to have_received(:new).with(hash_including(
                                                                     bastion_host: "10.0.0.1",
                                                                     bastion_password: "password",
                                                                     sudo_password: "sudo_password"
                                                                   ))
    expect(uninstaller).to have_received(:call)

    # Verify broadcasts
    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_uninstall_compute-001",
      hash_including(locals: hash_including(status: "success"))
    )
    expect(Rails.cache.read("install_creds_#{cache_key}")).to be_nil
  end

  it "broadcasts error if uninstallation fails" do
    allow(uninstaller).to receive(:call).and_raise(Agent::RemoteUninstallService::UninstallError, "Failed")

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_uninstall_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Failed"))
    )
  end

  context "when node record exists" do
    let!(:existing_node) { create(:node, hostname: "compute-001", source: :agent_push, agent_version: "v1.2.3") }

    it "clears agent_version after successful uninstall" do
      expect(existing_node.agent_version).to eq("v1.2.3")

      described_class.perform_now(**params)

      existing_node.reload
      expect(existing_node.agent_version).to be_nil
    end

    it "sets source to manual after successful uninstall" do
      expect(existing_node.source).to eq("agent_push")

      described_class.perform_now(**params)

      existing_node.reload
      expect(existing_node.source).to eq("manual")
    end

    it "updates both source and agent_version together" do
      described_class.perform_now(**params)

      existing_node.reload
      expect(existing_node.source).to eq("manual")
      expect(existing_node.agent_version).to be_nil
    end
  end

  context "when node record does not exist" do
    it "does not raise error when node is not found" do
      # Ensure no node with this hostname exists
      Node.where(hostname: "compute-001").destroy_all

      expect {
        described_class.perform_now(**params)
      }.not_to raise_error

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_uninstall_compute-001",
        hash_including(locals: hash_including(status: "success"))
      )
    end
  end

  context "when uninstall fails" do
    let!(:existing_node) { create(:node, hostname: "compute-001", source: :agent_push, agent_version: "v1.2.3") }

    before do
      allow(uninstaller).to receive(:call).and_raise(Agent::RemoteUninstallService::UninstallError, "Connection refused")
    end

    it "does not clear agent_version on failure" do
      described_class.perform_now(**params)

      existing_node.reload
      expect(existing_node.agent_version).to eq("v1.2.3")
    end

    it "does not change source on failure" do
      described_class.perform_now(**params)

      existing_node.reload
      expect(existing_node.source).to eq("agent_push")
    end
  end
end
