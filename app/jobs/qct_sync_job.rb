# frozen_string_literal: true

class QctSyncJob < ApplicationJob
  queue_as :default

  def perform(user_id: nil)
    notification = nil

    # Create notification if user_id is provided
    if user_id.present?
      user = User.find_by(id: user_id)
      if user
        notification = NotificationService.create(
          user: user,
          type: "product_sync",
          title: "Syncing products from QCT"
        )
        NotificationService.start(notification)
      end
    end

    result = QctScraperService.new.sync_all

    SyncLog.create!(
      source: "qct",
      products_added: result.added_count,
      products_updated: result.updated_count,
      sync_errors: result.errors,
      completed_at: Time.current
    )

    Rails.logger.info "[QctSyncJob] Completed: #{result.added_count} added, #{result.updated_count} updated, #{result.errors.size} errors"

    if notification
      message = "Sync completed: #{result.added_count} added, #{result.updated_count} updated"
      message += ", #{result.errors.size} errors" if result.errors.any?
      NotificationService.complete(notification, success: result.errors.empty?, message: message)
    end
  rescue => e
    NotificationService.complete(notification, success: false, message: e.message) if notification
    raise
  end
end
