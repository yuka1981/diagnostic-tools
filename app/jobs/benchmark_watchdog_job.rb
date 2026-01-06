# frozen_string_literal: true

class BenchmarkWatchdogJob < ApplicationJob
  queue_as :default

  STALE_THRESHOLD = 5.minutes
  LOST_MESSAGE = "Agent heartbeat lost"

  def self.schedule_next_run
    set(wait: STALE_THRESHOLD).perform_later
  end

  def perform
    mark_stale_runs_as_lost
    self.class.schedule_next_run unless Rails.env.test?
  end

  private

  def mark_stale_runs_as_lost
    cutoff_time = STALE_THRESHOLD.ago
    BenchmarkRun.active
      .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", cutoff_time)
      .find_each do |run|
        run.update!(
          status: :lost,
          error_message: append_heartbeat_note(run.error_message),
          last_heartbeat_at: Time.current
        )
      end
  end

  def append_heartbeat_note(existing_message)
    return LOST_MESSAGE if existing_message.blank?

    "#{existing_message}\n#{LOST_MESSAGE}"
  end
end
