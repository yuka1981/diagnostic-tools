# frozen_string_literal: true

require "rails_helper"

RSpec.describe InventoryCollectJob, type: :job do
  include ActiveJob::TestHelper

  let(:node) { create(:node, hostname: "node-01") }

  describe "#perform" do
    let(:success_result) do
      Inventory::SaltCollectService::Result.new(
        success: true,
        state_created: true,
        node_state: nil
      )
    end

    let(:mock_service) { instance_double(Inventory::SaltCollectService, call: success_result) }

    before do
      allow(Inventory::SaltCollectService).to receive(:new).and_return(mock_service)
    end

    it "delegates to Inventory::SaltCollectService" do
      expect(Inventory::SaltCollectService).to receive(:new)
        .with(node)
        .and_return(mock_service)

      described_class.perform_now(node.id)

      expect(mock_service).to have_received(:call)
    end

    context "when collection succeeds" do
      it "does not log an error" do
        expect(Rails.logger).not_to receive(:error)

        described_class.perform_now(node.id)
      end
    end

    context "when collection fails" do
      let(:failure_result) do
        Inventory::SaltCollectService::Result.new(
          success: false,
          error: "Minion 'node-01' did not return a result"
        )
      end

      before do
        allow(mock_service).to receive(:call).and_return(failure_result)
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error)
          .with(/Failed to collect from node-01/)

        described_class.perform_now(node.id)
      end
    end

    context "when node does not exist" do
      it "discards the job without error" do
        expect { described_class.perform_now(999_999) }.not_to raise_error
      end
    end

    context "with user_id for notifications" do
      let(:user) { create(:user) }

      it "creates and completes a notification on success" do
        notification = instance_double(Notification)

        allow(NotificationService).to receive(:create).and_return(notification)
        allow(NotificationService).to receive(:start)
        allow(NotificationService).to receive(:complete)

        described_class.perform_now(node.id, user_id: user.id)

        expect(NotificationService).to have_received(:create).with(
          user: user,
          type: "inventory_collect",
          title: "Collecting inventory from node-01",
          resource: node
        )
        expect(NotificationService).to have_received(:start).with(notification)
        expect(NotificationService).to have_received(:complete).with(
          notification, success: true, message: "Inventory collected successfully"
        )
      end

      it "completes notification as failure on collection error" do
        failure_result = Inventory::SaltCollectService::Result.new(
          success: false,
          error: "Salt API authentication failed"
        )
        allow(mock_service).to receive(:call).and_return(failure_result)

        notification = instance_double(Notification)
        allow(NotificationService).to receive(:create).and_return(notification)
        allow(NotificationService).to receive(:start)
        allow(NotificationService).to receive(:complete)
        allow(Rails.logger).to receive(:error)

        described_class.perform_now(node.id, user_id: user.id)

        expect(NotificationService).to have_received(:complete).with(
          notification, success: false, message: "Salt API authentication failed"
        )
      end
    end

    context "without user_id" do
      it "does not create a notification" do
        expect(NotificationService).not_to receive(:create)

        described_class.perform_now(node.id)
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "enqueue" do
    it "can be enqueued with node id" do
      expect {
        described_class.perform_later(node.id)
      }.to have_enqueued_job(described_class).with(node.id)
    end

    it "can be enqueued with user_id" do
      expect {
        described_class.perform_later(node.id, user_id: 42)
      }.to have_enqueued_job(described_class).with(node.id, user_id: 42)
    end
  end
end
