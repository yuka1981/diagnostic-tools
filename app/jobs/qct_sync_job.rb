# frozen_string_literal: true

class QctSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = QctScraperService.new.sync_all

    SyncLog.create!(
      source: "qct",
      products_added: result.added_count,
      products_updated: result.updated_count,
      sync_errors: result.errors,
      completed_at: Time.current
    )

    Rails.logger.info "[QctSyncJob] Completed: #{result.added_count} added, #{result.updated_count} updated, #{result.errors.size} errors"
  end
end
