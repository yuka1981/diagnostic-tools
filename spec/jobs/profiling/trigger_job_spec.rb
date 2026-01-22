# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiling::TriggerJob, type: :job do
  let(:node) { create(:node) }
  let(:run) { create(:profiling_run, node: node, status: :pending) }
  let(:user) { create(:user) }

  describe "#perform" do
    context "when trigger succeeds" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: true, output: "ok"))
      end

      it "updates run to running status" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.status).to eq("running")
      end

      it "sets started_at" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.started_at).to be_present
        expect(run.started_at).to be_within(5.seconds).of(Time.current)
      end

      it "stores output in log_content" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.log_content).to eq("ok")
      end
    end

    context "when trigger fails" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: false, error: "SSH failed", output: "connection log"))
      end

      it "updates run to failed status" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.status).to eq("failed")
      end

      it "stores error message" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.error_message).to include("SSH failed")
      end

      it "stores output in log_content" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        run.reload
        expect(run.log_content).to eq("connection log")
      end
    end

    context "when run status changes during execution" do
      let(:cancelled_run) { create(:profiling_run, :cancelled, node: node) }

      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: true, output: "ok"))
      end

      it "does not update status if run is no longer pending" do
        described_class.perform_now(cancelled_run, "http://localhost:3000", "token", user_id: user.id)
        cancelled_run.reload
        expect(cancelled_run.status).to eq("cancelled")
      end
    end

    context "with user notification" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: true, output: "ok"))
      end

      it "creates a notification for the user" do
        expect {
          described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        }.to change(Notification, :count).by(1)
      end

      it "creates notification with correct title" do
        described_class.perform_now(run, "http://localhost:3000", "token", user_id: user.id)
        notification = Notification.last
        expect(notification.title).to include("Running profiling")
        expect(notification.title).to include(node.hostname)
      end
    end

    context "without user_id" do
      before do
        allow_any_instance_of(Profiling::TriggerService).to receive(:call)
          .and_return(Profiling::TriggerService::Result.new(success: true, output: "ok"))
      end

      it "does not create notification" do
        expect {
          described_class.perform_now(run, "http://localhost:3000", "token")
        }.not_to change(Notification, :count)
      end

      it "still updates run status" do
        described_class.perform_now(run, "http://localhost:3000", "token")
        run.reload
        expect(run.status).to eq("running")
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
