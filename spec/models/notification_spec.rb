# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notification, type: :model do
  describe "validations" do
    subject { build(:notification) }

    it { is_expected.to validate_presence_of(:notification_type) }
    it { is_expected.to validate_inclusion_of(:notification_type).in_array(Notification::TYPES) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:resource).optional }
  end

  describe "enum status" do
    it "defines pending, running, completed, and failed statuses" do
      expect(Notification.statuses).to eq({
        "pending" => "pending",
        "running" => "running",
        "completed" => "completed",
        "failed" => "failed"
      })
    end

    it "defaults to pending status" do
      notification = Notification.new
      expect(notification.status).to eq("pending")
    end

    it "can be set to running" do
      notification = build(:notification, :running)
      expect(notification).to be_running
    end

    it "can be set to completed" do
      notification = build(:notification, :completed)
      expect(notification).to be_completed
    end

    it "can be set to failed" do
      notification = build(:notification, :failed)
      expect(notification).to be_failed
    end
  end

  describe "scopes" do
    describe ".unread" do
      let!(:unread_notification) { create(:notification) }
      let!(:read_notification) { create(:notification, :read) }
      let!(:archived_notification) { create(:notification, :archived) }

      it "returns unread and non-archived notifications" do
        expect(Notification.unread).to include(unread_notification)
        expect(Notification.unread).not_to include(read_notification)
        expect(Notification.unread).not_to include(archived_notification)
      end
    end

    describe ".active" do
      let!(:active_notification) { create(:notification) }
      let!(:archived_notification) { create(:notification, :archived) }

      it "returns non-archived notifications" do
        expect(Notification.active).to include(active_notification)
        expect(Notification.active).not_to include(archived_notification)
      end
    end

    describe ".for_dropdown" do
      let!(:notifications) { create_list(:notification, 15) }
      let!(:archived_notification) { create(:notification, :archived) }

      it "returns active notifications ordered by created_at desc, limited to 10" do
        result = Notification.for_dropdown
        expect(result.count).to eq(10)
        expect(result).not_to include(archived_notification)
        expect(result).to eq(result.sort_by(&:created_at).reverse)
      end
    end

    describe ".recent" do
      let!(:older) { create(:notification, created_at: 2.days.ago) }
      let!(:newer) { create(:notification, created_at: 1.day.ago) }

      it "orders by created_at descending" do
        expect(Notification.recent.first).to eq(newer)
        expect(Notification.recent.last).to eq(older)
      end
    end

    describe ".by_type" do
      let!(:agent_install) { create(:notification, notification_type: "agent_install") }
      let!(:benchmark) { create(:notification, notification_type: "benchmark") }

      it "filters by notification_type when type is present" do
        expect(Notification.by_type("agent_install")).to include(agent_install)
        expect(Notification.by_type("agent_install")).not_to include(benchmark)
      end

      it "returns all notifications when type is blank" do
        expect(Notification.by_type(nil)).to include(agent_install, benchmark)
        expect(Notification.by_type("")).to include(agent_install, benchmark)
      end
    end

    describe ".by_status" do
      let!(:pending_notification) { create(:notification, status: "pending") }
      let!(:completed_notification) { create(:notification, :completed) }

      it "filters by status when status is present" do
        expect(Notification.by_status("pending")).to include(pending_notification)
        expect(Notification.by_status("pending")).not_to include(completed_notification)
      end

      it "returns all notifications when status is blank" do
        expect(Notification.by_status(nil)).to include(pending_notification, completed_notification)
        expect(Notification.by_status("")).to include(pending_notification, completed_notification)
      end
    end
  end

  describe "instance methods" do
    describe "#progress_percent" do
      it "returns progress_percent from metadata" do
        notification = build(:notification, :with_progress)
        expect(notification.progress_percent).to eq(50)
      end

      it "returns nil when progress_percent is not set" do
        notification = build(:notification)
        expect(notification.progress_percent).to be_nil
      end
    end

    describe "#in_progress?" do
      it "returns true for pending notifications" do
        notification = build(:notification, status: "pending")
        expect(notification.in_progress?).to be true
      end

      it "returns true for running notifications" do
        notification = build(:notification, :running)
        expect(notification.in_progress?).to be true
      end

      it "returns false for completed notifications" do
        notification = build(:notification, :completed)
        expect(notification.in_progress?).to be false
      end

      it "returns false for failed notifications" do
        notification = build(:notification, :failed)
        expect(notification.in_progress?).to be false
      end
    end

    describe "#terminal?" do
      it "returns false for pending notifications" do
        notification = build(:notification, status: "pending")
        expect(notification.terminal?).to be false
      end

      it "returns false for running notifications" do
        notification = build(:notification, :running)
        expect(notification.terminal?).to be false
      end

      it "returns true for completed notifications" do
        notification = build(:notification, :completed)
        expect(notification.terminal?).to be true
      end

      it "returns true for failed notifications" do
        notification = build(:notification, :failed)
        expect(notification.terminal?).to be true
      end
    end
  end

  describe "factory" do
    it "creates a valid notification" do
      notification = build(:notification)
      expect(notification).to be_valid
    end

    it "creates a valid notification with running trait" do
      notification = build(:notification, :running)
      expect(notification).to be_valid
      expect(notification).to be_running
      expect(notification.started_at).to be_present
    end

    it "creates a valid notification with completed trait" do
      notification = build(:notification, :completed)
      expect(notification).to be_valid
      expect(notification).to be_completed
      expect(notification.completed_at).to be_present
    end

    it "creates a valid notification with failed trait" do
      notification = build(:notification, :failed)
      expect(notification).to be_valid
      expect(notification).to be_failed
      expect(notification.message).to eq("Something went wrong")
    end

    it "creates a valid notification with read trait" do
      notification = build(:notification, :read)
      expect(notification).to be_valid
      expect(notification.read).to be true
    end

    it "creates a valid notification with archived trait" do
      notification = build(:notification, :archived)
      expect(notification).to be_valid
      expect(notification.archived).to be true
    end

    it "creates a valid notification with with_progress trait" do
      notification = build(:notification, :with_progress)
      expect(notification).to be_valid
      expect(notification.progress_percent).to eq(50)
    end

    it "creates a valid notification with with_resource trait" do
      notification = build(:notification, :with_resource)
      expect(notification).to be_valid
      expect(notification.resource).to be_a(Node)
    end
  end

  describe "notification types" do
    it "includes all expected types" do
      expect(Notification::TYPES).to contain_exactly(
        "agent_install",
        "agent_update",
        "agent_uninstall",
        "benchmark",
        "inventory_collect",
        "product_sync",
        "profiling"
      )
    end

    Notification::TYPES.each do |type|
      it "allows #{type} as notification_type" do
        notification = build(:notification, notification_type: type)
        expect(notification).to be_valid
      end
    end

    it "rejects invalid notification types" do
      notification = build(:notification, notification_type: "invalid_type")
      expect(notification).not_to be_valid
      expect(notification.errors[:notification_type]).to be_present
    end
  end
end
