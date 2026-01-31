# frozen_string_literal: true

module Bmc
  class SensorCollectionJob < ApplicationJob
    queue_as :default

    def perform
      result = Bmc::SaltTriggerService.new.collect_sensors
      Rails.logger.info("[BMC] Sensor collection result: #{result}")

      # Re-enqueue with configured interval
      interval = bmc_collection_interval
      self.class.set(wait: interval.minutes).perform_later if interval.positive?
    end

    private

    def bmc_collection_interval
      global = BmcCredential.global_default
      global&.collection_interval || 5
    end
  end
end
