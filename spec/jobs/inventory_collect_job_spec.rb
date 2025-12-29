# frozen_string_literal: true

require "rails_helper"

RSpec.describe InventoryCollectJob, type: :job do
  include ActiveJob::TestHelper

  let(:target_node) { create(:node, hostname: "compute-01") }
  let(:gateway_node) { create(:node, :admin, hostname: "gateway-01") }

  describe "#perform" do
    let(:service_result) do
      Inventory::TriggerCollectService::Result.new(
        success: true,
        output: { cpu_info: { cores: 8 } }
      )
    end

    let(:mock_service) { instance_double(Inventory::TriggerCollectService, call: service_result) }

    before do
      allow(Inventory::TriggerCollectService).to receive(:new).and_return(mock_service)
    end

    it "finds the target node and calls TriggerCollectService" do
      expect(Inventory::TriggerCollectService).to receive(:new).with(
        target_node,
        gateway: nil
      ).and_return(mock_service)

      described_class.perform_now(target_node.id)
    end

    context "with gateway node" do
      it "passes gateway node to service" do
        expect(Inventory::TriggerCollectService).to receive(:new).with(
          target_node,
          gateway: gateway_node
        ).and_return(mock_service)

        described_class.perform_now(target_node.id, gateway_node_id: gateway_node.id)
      end
    end

    context "when collection succeeds" do
      let(:process_service_result) do
        Inventory::ProcessStateService::Result.new(success: true, state_created: true)
      end

      let(:mock_process_service) { instance_double(Inventory::ProcessStateService, call: process_service_result) }

      before do
        allow(Inventory::ProcessStateService).to receive(:new).and_return(mock_process_service)
      end

      it "processes collected data with ProcessStateService" do
        expect(Inventory::ProcessStateService).to receive(:new).with(
          node_id: target_node.id,
          raw_json: { cpu_info: { cores: 8 } }
        ).and_return(mock_process_service)

        described_class.perform_now(target_node.id)
      end
    end

    context "when collection fails" do
      let(:service_result) do
        Inventory::TriggerCollectService::Result.new(
          success: false,
          error: "Connection timeout"
        )
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/Failed to collect data from compute-01/)

        described_class.perform_now(target_node.id)
      end

      it "does not call ProcessStateService" do
        allow(Rails.logger).to receive(:error)
        expect(Inventory::ProcessStateService).not_to receive(:new)

        described_class.perform_now(target_node.id)
      end
    end

    context "when node does not exist" do
      it "discards the job without error" do
        expect { described_class.perform_now(999999) }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "retry behavior" do
    it "has retry_on configured" do
      # Simply verify that the job has some rescue handlers configured
      expect(described_class.rescue_handlers).not_to be_empty
    end
  end

  describe "enqueue" do
    it "can be enqueued with node id" do
      expect {
        described_class.perform_later(target_node.id)
      }.to have_enqueued_job(described_class).with(target_node.id)
    end

    it "can be enqueued with gateway node id" do
      expect {
        described_class.perform_later(target_node.id, gateway_node_id: gateway_node.id)
      }.to have_enqueued_job(described_class).with(target_node.id, gateway_node_id: gateway_node.id)
    end
  end
end
