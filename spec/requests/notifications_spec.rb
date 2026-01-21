# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Notifications", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /notifications" do
    context "when not authenticated" do
      it "redirects to login page" do
        get notifications_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns http success" do
        get notifications_path
        expect(response).to have_http_status(:success)
      end

      it "displays the notification list" do
        notification = create(:notification, user: user, title: "Test Notification")
        get notifications_path
        expect(response.body).to include("Test Notification")
      end

      it "only shows current user notifications" do
        create(:notification, user: user, title: "My Notification")
        create(:notification, user: other_user, title: "Other User Notification")

        get notifications_path
        expect(response.body).to include("My Notification")
        expect(response.body).not_to include("Other User Notification")
      end

      it "excludes archived notifications by default" do
        create(:notification, user: user, title: "Active Notification", archived: false)
        create(:notification, :archived, user: user, title: "Archived Notification")

        get notifications_path
        expect(response.body).to include("Active Notification")
        expect(response.body).not_to include("Archived Notification")
      end

      it "includes archived notifications when show_archived is true" do
        create(:notification, :archived, user: user, title: "Archived Notification")

        get notifications_path(show_archived: "true")
        expect(response.body).to include("Archived Notification")
      end

      context "with status filter" do
        before do
          create(:notification, user: user, title: "Pending Notification", status: "pending")
          create(:notification, :completed, user: user, title: "Completed Notification")
        end

        it "filters by status" do
          get notifications_path(status: "completed")
          expect(response.body).to include("Completed Notification")
          expect(response.body).not_to include("Pending Notification")
        end
      end

      context "with type filter" do
        before do
          create(:notification, user: user, title: "Install Notification", notification_type: "agent_install")
          create(:notification, user: user, title: "Benchmark Notification", notification_type: "benchmark")
        end

        it "filters by type" do
          get notifications_path(type: "benchmark")
          expect(response.body).to include("Benchmark Notification")
          expect(response.body).not_to include("Install Notification")
        end
      end

      it "orders notifications by created_at desc" do
        old_notification = create(:notification, user: user, title: "Old", created_at: 2.days.ago)
        new_notification = create(:notification, user: user, title: "New", created_at: 1.hour.ago)

        get notifications_path
        # New should appear before Old in the response
        expect(response.body.index("New")).to be < response.body.index("Old")
      end
    end
  end

  describe "POST /notifications/:id/mark_read" do
    let!(:notification) { create(:notification, user: user, read: false) }

    context "when not authenticated" do
      it "redirects to login page" do
        post mark_read_notification_path(notification)
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "marks the notification as read" do
        expect {
          post mark_read_notification_path(notification)
        }.to change { notification.reload.read }.from(false).to(true)
      end

      it "redirects back with html format" do
        post mark_read_notification_path(notification)
        expect(response).to redirect_to(notifications_path)
      end

      context "with turbo_stream format" do
        it "returns turbo stream response" do
          post mark_read_notification_path(notification), headers: { "Accept" => "text/vnd.turbo-stream.html" }
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end

        it "includes notification replacement in response" do
          post mark_read_notification_path(notification), headers: { "Accept" => "text/vnd.turbo-stream.html" }
          expect(response.body).to include("turbo-stream")
        end
      end

      context "when notification belongs to another user" do
        let!(:other_notification) { create(:notification, user: other_user) }

        it "returns not found" do
          post mark_read_notification_path(other_notification)
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  describe "POST /notifications/mark_all_read" do
    context "when not authenticated" do
      it "redirects to login page" do
        post mark_all_read_notifications_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "marks all user notifications as read" do
        unread1 = create(:notification, user: user, read: false)
        unread2 = create(:notification, user: user, read: false)

        post mark_all_read_notifications_path

        expect(unread1.reload.read).to be true
        expect(unread2.reload.read).to be true
      end

      it "does not mark other user notifications as read" do
        other_notification = create(:notification, user: other_user, read: false)

        post mark_all_read_notifications_path

        expect(other_notification.reload.read).to be false
      end

      it "redirects with success notice for html format" do
        post mark_all_read_notifications_path
        expect(response).to redirect_to(notifications_path)
        expect(flash[:notice]).to eq("All notifications marked as read")
      end

      context "with turbo_stream format" do
        it "returns turbo stream response" do
          post mark_all_read_notifications_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end

        it "includes list and badge replacements in response" do
          post mark_all_read_notifications_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }
          expect(response.body).to include("turbo-stream")
          expect(response.body).to include("notifications_list")
          expect(response.body).to include("notification_badge")
        end
      end
    end
  end

  describe "POST /notifications/archive_read" do
    context "when not authenticated" do
      it "redirects to login page" do
        post archive_read_notifications_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "archives read notifications" do
        read_notification = create(:notification, :read, user: user, archived: false)
        unread_notification = create(:notification, user: user, read: false, archived: false)

        post archive_read_notifications_path

        expect(read_notification.reload.archived).to be true
        expect(unread_notification.reload.archived).to be false
      end

      it "does not archive other user notifications" do
        other_read = create(:notification, :read, user: other_user, archived: false)

        post archive_read_notifications_path

        expect(other_read.reload.archived).to be false
      end

      it "redirects with success notice" do
        post archive_read_notifications_path
        expect(response).to redirect_to(notifications_path)
        expect(flash[:notice]).to eq("Read notifications archived")
      end
    end
  end
end
