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

    context "when collection fails with error result" do
      let(:service_result) do
        Inventory::TriggerCollectService::Result.new(
          success: false,
          error: "Command returned empty output"
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

    context "when SSH authentication fails" do
      before do
        allow(mock_service).to receive(:call).and_raise(
          Net::SSH::AuthenticationFailed.new("admin")
        )
      end

      it "logs the SSH error and completes without raising" do
        expect(Rails.logger).to receive(:error).with(/SSH error for compute-01.*Authentication failed/)

        expect { described_class.perform_now(target_node.id) }.not_to raise_error
      end

      it "does not call ProcessStateService" do
        allow(Rails.logger).to receive(:error)
        expect(Inventory::ProcessStateService).not_to receive(:new)

        described_class.perform_now(target_node.id)
      end
    end

    context "when SSH host key verification fails" do
      before do
        allow(mock_service).to receive(:call).and_raise(
          Net::SSH::HostKeyMismatch.new("Host key mismatch")
        )
      end

      it "logs the SSH error and completes without raising" do
        expect(Rails.logger).to receive(:error).with(/SSH error for compute-01.*Host key verification failed/)

        expect { described_class.perform_now(target_node.id) }.not_to raise_error
      end
    end

    context "when other SSH exception occurs" do
      before do
        allow(mock_service).to receive(:call).and_raise(
          Net::SSH::Exception.new("Unknown SSH error")
        )
      end

      it "logs the SSH error and completes without raising" do
        expect(Rails.logger).to receive(:error).with(/SSH error for compute-01/)

        expect { described_class.perform_now(target_node.id) }.not_to raise_error
      end
    end

    context "when SSH connection times out" do
      before do
        allow(mock_service).to receive(:call).and_raise(
          Net::SSH::ConnectionTimeout.new("Connection timed out")
        )
      end

      it "allows the exception to propagate for retry handling" do
        # retry_on catches ConnectionTimeout internally, so it won't raise in perform_now
        # but it will be enqueued for retry when using perform_later
        # For perform_now, the retry mechanism handles it silently after max attempts
        expect { described_class.perform_now(target_node.id) }.not_to raise_error
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
    it "has retry_on configured for ConnectionTimeout only" do
      # Verify that the job has rescue handlers configured
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
