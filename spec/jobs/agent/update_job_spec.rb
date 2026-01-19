# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agent::UpdateJob, type: :job do
  let(:node) { create(:node, :direct, hostname: "compute-001", sudo_credential: "saved_password") }
  let(:agent_release) { create(:agent_release, version: "v2.0.0") }

  let(:patch_result) { Agent::PatchService::Result.new(success: true, message: "Agent updated to v2.0.0") }
  let(:patch_service) { instance_double(Agent::PatchService, call: patch_result) }

  before do
    allow(Agent::PatchService).to receive(:new).and_return(patch_service)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  describe "#perform" do
    it "calls PatchService with correct parameters" do
      described_class.perform_now(node: node, agent_release: agent_release)

      expect(Agent::PatchService).to have_received(:new).with(
        node: node,
        agent_release: agent_release,
        force: false,
        on_progress: anything
      )
      expect(patch_service).to have_received(:call)
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
      it "passes force to PatchService" do
        described_class.perform_now(node: node, agent_release: agent_release, force: true)

        expect(Agent::PatchService).to have_received(:new).with(hash_including(force: true))
      end
    end

    context "with credentials cache key" do
      let(:cache_key) { "test_cache_key" }

      before do
        Rails.cache.write("update_creds_#{cache_key}", { sudo_password: "cached_password" })
      end

      it "uses sudo password from cache during PatchService call" do
        # Capture the sudo_credential at the time PatchService.new is called
        captured_credential = nil
        allow(Agent::PatchService).to receive(:new) do |args|
          captured_credential = args[:node].sudo_credential
          patch_service
        end

        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        expect(captured_credential).to eq("cached_password")
      end

      it "cleans up cache after use" do
        described_class.perform_now(
          node: node,
          agent_release: agent_release,
          credentials_cache_key: cache_key
        )

        expect(Rails.cache.read("update_creds_#{cache_key}")).to be_nil
      end

      it "restores original sudo_credential after job" do
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
        allow(patch_service).to receive(:call).and_raise(Agent::Errors::NodeBusyError)
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

    context "when patch fails" do
      before do
        allow(patch_service).to receive(:call).and_raise(
          Agent::PatchService::PatchError, "SSH connection failed"
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
        allow(patch_service).to receive(:call).and_raise(StandardError, "Something went wrong")
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
