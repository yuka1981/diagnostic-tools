# frozen_string_literal: true

# Kick off the recurring watchdog loop after boot.
unless Rails.env.test?
  Rails.application.config.after_initialize do
    BenchmarkWatchdogJob.schedule_next_run
  end
end
