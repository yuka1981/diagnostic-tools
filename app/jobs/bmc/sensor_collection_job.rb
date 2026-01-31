# frozen_string_literal: true

module Bmc
  class SensorCollectionJob < ApplicationJob
    queue_as :default

    LOCK_KEY = "bmc_sensor_collection_scheduled"

    def perform
      # Prevent duplicate execution from multiple enqueued copies
      unless acquire_lock
        Rails.logger.info("[BMC] Sensor collection skipped: another instance is already running")
        return
      end

      begin
        result = Bmc::SaltTriggerService.new.collect_sensors
        Rails.logger.info("[BMC] Sensor collection result: #{result}")
      ensure
        release_lock
      end

      # Re-enqueue with configured interval
      schedule_next_run
    end

    private

    def acquire_lock
      # Returns true if lock was acquired (key did not exist), false otherwise.
      # Uses the cache entry to prevent concurrent execution.
      return false if Rails.cache.read(LOCK_KEY)

      Rails.cache.write(LOCK_KEY, true, expires_in: 10.minutes)
      true
    end

    def release_lock
      Rails.cache.delete(LOCK_KEY)
    end

    def schedule_next_run
      interval = bmc_collection_interval
      return unless interval.positive?

      self.class.set(wait: interval.minutes).perform_later
    end

    def bmc_collection_interval
      global = BmcCredential.global_default
      global&.collection_interval || 5
    end
  end
end
