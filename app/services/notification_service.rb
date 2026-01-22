# frozen_string_literal: true

class NotificationService
  class << self
    include ActionView::RecordIdentifier

    # Create a new notification and broadcast to user
    def create(user:, type:, title:, resource: nil, metadata: {})
      notification = Notification.create!(
        user: user,
        notification_type: type,
        status: "pending",
        title: title,
        resource_type: resource&.class&.name,
        resource_id: resource&.id,
        metadata: metadata
      )
      broadcast_notification(notification)
      notification
    end

    # Mark as running with optional progress
    def start(notification, progress: nil)
      notification.status = "running"
      notification.started_at = Time.current
      notification.metadata["progress_percent"] = progress if progress
      notification.save!
      broadcast_notification(notification)
    end

    # Update progress during execution
    def progress(notification, percent:, message: nil)
      notification.metadata["progress_percent"] = percent
      notification.message = message if message
      notification.save!
      broadcast_notification(notification)
    end

    # Mark completed (success or failure)
    def complete(notification, success:, message: nil, metadata: {})
      notification.update!(
        status: success ? "completed" : "failed",
        message: message,
        metadata: notification.metadata.merge(metadata),
        completed_at: Time.current
      )
      broadcast_notification(notification)
      broadcast_badge_update(notification.user)
    end

    # Mark single notification as read
    def mark_read(notification)
      notification.update!(read: true)
      broadcast_notification(notification)
      broadcast_badge_update(notification.user)
    end

    # Mark all unread notifications as read for a user
    def mark_all_read(user)
      user.notifications.unread.update_all(read: true, updated_at: Time.current)
      broadcast_list_update(user)
      broadcast_badge_update(user)
    end

    # Archive read notifications for a user
    def archive_read(user)
      user.notifications.where(read: true, archived: false).update_all(archived: true, updated_at: Time.current)
    end

    private

    def broadcast_notification(notification)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(notification.user),
        target: dom_id(notification),
        partial: "notifications/notification",
        locals: { notification: notification }
      )
    end

    def broadcast_badge_update(user)
      count = user.notifications.unread.count
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(user),
        target: "notification_badge",
        partial: "notifications/badge",
        locals: { count: count }
      )
    end

    def broadcast_list_update(user)
      Turbo::StreamsChannel.broadcast_replace_to(
        stream_name(user),
        target: "notifications_list",
        partial: "notifications/list",
        locals: { notifications: user.notifications.for_dropdown }
      )
    end

    def stream_name(user)
      "notifications_user_#{user.id}"
    end
  end
end
