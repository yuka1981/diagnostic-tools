# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotificationService do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:node) { create(:node) }

  describe ".create" do
    it "creates a notification with all attributes" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      notification = described_class.create(
        user: user,
        type: "agent_install",
        title: "Installing agent on node-1",
        resource: node,
        metadata: { "node_hostname" => "node-1" }
      )

      expect(notification).to be_persisted
      expect(notification.user).to eq(user)
      expect(notification.notification_type).to eq("agent_install")
      expect(notification.status).to eq("pending")
      expect(notification.title).to eq("Installing agent on node-1")
      expect(notification.resource).to eq(node)
      expect(notification.metadata).to eq({ "node_hostname" => "node-1" })
    end

    it "creates a notification without a resource" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

      notification = described_class.create(
        user: user,
        type: "benchmark",
        title: "Running HPCG benchmark"
      )

      expect(notification).to be_persisted
      expect(notification.resource).to be_nil
    end

    it "broadcasts the notification to the user's stream" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: match(/notification_\d+/),
          partial: "notifications/notification"
        )
      )

      described_class.create(
        user: user,
        type: "agent_install",
        title: "Installing agent"
      )
    end
  end

  describe ".start" do
    let(:notification) { create(:notification, user: user) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "updates status to running" do
      described_class.start(notification)

      notification.reload
      expect(notification.status).to eq("running")
    end

    it "sets started_at timestamp" do
      time = Time.current
      travel_to(time) do
        described_class.start(notification)

        notification.reload
        expect(notification.started_at).to be_within(1.second).of(time)
      end
    end

    it "optionally sets progress" do
      described_class.start(notification, progress: 10)

      notification.reload
      expect(notification.progress_percent).to eq(10)
    end

    it "broadcasts the updated notification" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_#{notification.id}",
          partial: "notifications/notification"
        )
      )

      described_class.start(notification)
    end
  end

  describe ".progress" do
    let(:notification) { create(:notification, :running, user: user) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "updates progress_percent in metadata" do
      described_class.progress(notification, percent: 50)

      notification.reload
      expect(notification.progress_percent).to eq(50)
    end

    it "optionally updates message" do
      described_class.progress(notification, percent: 75, message: "Building dependencies...")

      notification.reload
      expect(notification.progress_percent).to eq(75)
      expect(notification.message).to eq("Building dependencies...")
    end

    it "broadcasts the updated notification" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_#{notification.id}",
          partial: "notifications/notification"
        )
      )

      described_class.progress(notification, percent: 50)
    end
  end

  describe ".complete" do
    let(:notification) { create(:notification, :running, user: user) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    context "when successful" do
      it "updates status to completed" do
        described_class.complete(notification, success: true)

        notification.reload
        expect(notification.status).to eq("completed")
      end

      it "sets completed_at timestamp" do
        time = Time.current
        travel_to(time) do
          described_class.complete(notification, success: true)

          notification.reload
          expect(notification.completed_at).to be_within(1.second).of(time)
        end
      end
    end

    context "when failed" do
      it "updates status to failed" do
        described_class.complete(notification, success: false)

        notification.reload
        expect(notification.status).to eq("failed")
      end
    end

    it "optionally sets message" do
      described_class.complete(notification, success: true, message: "Agent installed successfully")

      notification.reload
      expect(notification.message).to eq("Agent installed successfully")
    end

    it "merges additional metadata" do
      notification.update!(metadata: { "initial" => "value" })

      described_class.complete(notification, success: true, metadata: { "result" => "success" })

      notification.reload
      expect(notification.metadata).to eq({ "initial" => "value", "result" => "success" })
    end

    it "broadcasts the notification update" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_#{notification.id}",
          partial: "notifications/notification"
        )
      )

      described_class.complete(notification, success: true)
    end

    it "broadcasts the badge update" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_badge",
          partial: "notifications/badge"
        )
      )

      described_class.complete(notification, success: true)
    end
  end

  describe ".mark_read" do
    let(:notification) { create(:notification, user: user, read: false) }

    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "updates read to true" do
      described_class.mark_read(notification)

      notification.reload
      expect(notification.read).to be true
    end

    it "broadcasts the notification update" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_#{notification.id}",
          partial: "notifications/notification"
        )
      )

      described_class.mark_read(notification)
    end

    it "broadcasts the badge update" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_badge",
          partial: "notifications/badge"
        )
      )

      described_class.mark_read(notification)
    end
  end

  describe ".mark_all_read" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "marks all unread notifications as read" do
      unread1 = create(:notification, user: user, read: false)
      unread2 = create(:notification, user: user, read: false)
      already_read = create(:notification, user: user, read: true)
      archived = create(:notification, user: user, read: false, archived: true)

      described_class.mark_all_read(user)

      expect(unread1.reload.read).to be true
      expect(unread2.reload.read).to be true
      expect(already_read.reload.read).to be true
      # Archived notifications are not in the unread scope
      expect(archived.reload.read).to be false
    end

    it "broadcasts list update" do
      create(:notification, user: user, read: false)

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notifications_list",
          partial: "notifications/list"
        )
      )

      described_class.mark_all_read(user)
    end

    it "broadcasts badge update" do
      create(:notification, user: user, read: false)

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        "notifications_user_#{user.id}",
        hash_including(
          target: "notification_badge",
          partial: "notifications/badge"
        )
      )

      described_class.mark_all_read(user)
    end
  end

  describe ".archive_read" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

    it "archives read notifications" do
      read_notification = create(:notification, user: user, read: true, archived: false)
      unread_notification = create(:notification, user: user, read: false, archived: false)
      already_archived = create(:notification, user: user, read: true, archived: true)

      described_class.archive_read(user)

      expect(read_notification.reload.archived).to be true
      expect(unread_notification.reload.archived).to be false
      expect(already_archived.reload.archived).to be true
    end
  end
end
