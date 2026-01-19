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
  let!(:existing_node) { create(:node, hostname: "compute-001", source: :agent_push, agent_version: "v1.2.3") }
  let(:params) do
    {
      target_host: "compute-001",
      bastion_host: "10.0.0.1",
      bastion_user: "admin",
      credentials_cache_key: cache_key
    }
  end

  let(:uninstall_result) { Agent::LifecycleService::Result.new(success: true, message: "Agent uninstalled successfully") }
  let(:uninstaller) { instance_double(Agent::UninstallService, call: uninstall_result) }

  before do
    allow(Agent::UninstallService).to receive(:new).and_return(uninstaller)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    Rails.cache.write("install_creds_#{cache_key}", credentials)
  end

  it "uninstalls the agent" do
    described_class.perform_now(**params)

    expect(Agent::UninstallService).to have_received(:new).with(hash_including(
                                                                  node: existing_node,
                                                                  cache_key: anything,
                                                                  on_progress: anything
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
    allow(uninstaller).to receive(:call).and_raise(
      Agent::Errors::DeploymentError.new("Failed", phase: :execute)
    )

    described_class.perform_now(**params)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      "agent_uninstall_compute-001",
      hash_including(locals: hash_including(status: "error", message: "Failed"))
    )
  end

  context "when node record does not exist" do
    before do
      # Ensure no node with this hostname exists
      Node.where(hostname: "compute-001").destroy_all
    end

    it "broadcasts error when node is not found" do
      described_class.perform_now(**params)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_uninstall_compute-001",
        hash_including(locals: hash_including(
          status: "error",
          message: "Uninstallation failed: Node not found."
        ))
      )
    end
  end

  context "when credentials are missing" do
    before do
      Rails.cache.delete("install_creds_#{cache_key}")
    end

    it "broadcasts error when credentials expired" do
      described_class.perform_now(**params)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_uninstall_compute-001",
        hash_including(locals: hash_including(
          status: "error",
          message: "Uninstallation failed: Credentials expired or not found. Please try again."
        ))
      )
    end
  end

  context "when uninstall fails" do
    before do
      allow(uninstaller).to receive(:call).and_raise(
        Agent::Errors::DeploymentError.new("Connection refused", phase: :connect)
      )
    end

    it "broadcasts error status" do
      described_class.perform_now(**params)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_uninstall_compute-001",
        hash_including(locals: hash_including(status: "error", message: "Connection refused"))
      )
    end
  end

  it "passes lifecycle credentials to the cache" do
    described_class.perform_now(**params)

    # Verify credentials were transformed to lifecycle format
    expect(Agent::UninstallService).to have_received(:new).with(hash_including(
      cache_key: match(/^lifecycle_creds_/)
    ))
  end

  it "writes lifecycle credentials in expected format" do
    # Track what gets written to cache
    lifecycle_cache_key = nil
    allow(Agent::UninstallService).to receive(:new) do |args|
      lifecycle_cache_key = args[:cache_key]
      uninstaller
    end

    described_class.perform_now(**params)

    lifecycle_creds = Rails.cache.read(lifecycle_cache_key)
    expect(lifecycle_creds).to include(
      ssh_password: "password",
      sudo_password: "sudo_password"
    )
  end
end
