# frozen_string_literal: true

module Bmc
  class SensorIngestionService
    def initialize(event_data)
      @results = event_data["results"] || []
      @errors = event_data["errors"] || []
    end

    def call
      records = []

      @results.each do |result|
        node = Node.find_by(id: result["node_id"])
        next unless node

        collected_at = Time.zone.parse(result["collected_at"])

        result["readings"].each do |reading|
          records << {
            node_id: node.id,
            sensor_type: reading["type"],
            sensor_name: reading["name"],
            value: reading["value"].to_f,
            unit: reading["unit"],
            status: reading["status"],
            recorded_at: collected_at
          }
        end
      end

      BmcSensorReading.insert_all(records) if records.any?

      { inserted: records.size, errors: @errors }
    end
  end
end
