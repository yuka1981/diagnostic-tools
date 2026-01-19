# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UpdateJob, type: :job do
  let(:node) { create(:node, :direct, hostname: "compute-001", sudo_credential: "saved_password") }
  let(:agent_release) { create(:agent_release, version: "v2.0.0") }

  let(:update_result) { Agent::LifecycleService::Result.new(success: true, message: "Agent updated to v2.0.0") }
  let(:update_service) { instance_double(Agent::UpdateService, call: update_result) }

  before do
    allow(Agent::UpdateService).to receive(:new).and_return(update_service)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "calls UpdateService with correct parameters" do
      described_class.perform_now(node: node, agent_release: agent_release)

      expect(Agent::UpdateService).to have_received(:new).with(
        node: node,
        agent_release: agent_release,
        force: false,
        cache_key: nil,
        on_progress: anything
      )
      expect(update_service).to have_received(:call)
    end

    it "broadcasts success status on completion" do
      described_class.perform_now(node: node, agent_release: agent_release)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_update_#{node.id}",
        hash_including(
          target: "agent_update_status_#{node.id}",
          locals: hash_including(status: "success", message: "Agent updated to v2.0.0")
        )
      )
    end

    it "broadcasts processing status at start" do
      described_class.perform_now(node: node, agent_release: agent_release)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        "agent_update_#{node.id}",
        hash_including(
          locals: hash_including(status: "processing", message: /Starting agent update/)
        )
      )
    end

    context "with force flag" do
      it "passes force to UpdateService" do
        described_class.perform_now(node: node, agent_release: agent_release, force: true)

        expect(Agent::UpdateService).to have_received(:new).with(hash_including(force: true))
      end
    end

    context "with credentials cache key" do
      let(:cache_key) { "test_cache_key" }

      before do
        Rails.cache.write("update_creds_#{cache_key}", { sudo_password: "cached_password" })
      end

      it "transforms credentials_cache_key to lifecycle_cache_key for UpdateService" do
        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        expect(Agent::UpdateService).to have_received(:new).with(
          hash_including(cache_key: "lifecycle_creds_#{cache_key}")
        )
      end

      it "stores credentials in lifecycle format in cache" do
        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        lifecycle_creds = Rails.cache.read("lifecycle_creds_#{cache_key}")
        expect(lifecycle_creds).to include(sudo_password: "cached_password")
      end

      it "cleans up original credentials cache" do
        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        expect(Rails.cache.read("update_creds_#{cache_key}")).to be_nil
      end

      it "does not modify node sudo_credential" do
        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        expect(node.sudo_credential).to eq("saved_password")
      end
    end

    context "when node is busy" do
      before do
        allow(update_service).to receive(:call).and_raise(Agent::Errors::NodeBusyError)
      end

      it "broadcasts error status" do
        described_class.perform_now(node: node, agent_release: agent_release)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          "agent_update_#{node.id}",
          hash_including(
            locals: hash_including(status: "error", message: /busy/)
          )
        )
      end
    end

    context "when update fails" do
      before do
        allow(update_service).to receive(:call).and_raise(
          Agent::Errors::DeploymentError.new("SSH connection failed", phase: :connect)
        )
      end

      it "broadcasts error status with message" do
        described_class.perform_now(node: node, agent_release: agent_release)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          "agent_update_#{node.id}",
          hash_including(
            locals: hash_including(status: "error", message: "SSH connection failed")
          )
        )
      end
    end

    context "when unexpected error occurs" do
      before do
        allow(update_service).to receive(:call).and_raise(StandardError, "Something went wrong")
      end

      it "broadcasts error status" do
        described_class.perform_now(node: node, agent_release: agent_release)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          "agent_update_#{node.id}",
          hash_including(
            locals: hash_including(status: "error", message: /Something went wrong/)
          )
        )
      end
    end
  end
end
