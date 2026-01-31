# frozen_string_literal: true

module Bmc
  class SensorIngestionService
    VALID_SENSOR_TYPES = %w[temperature fan power health].freeze

    def initialize(event_data)
      @results = event_data["results"] || []
      @errors = event_data["errors"] || []
    end

    def call
      records = []
      skipped = 0

      @results.each do |result|
        node = Node.find_by(id: result["node_id"])
        next unless node

        collected_at = parse_collected_at(result["collected_at"])

        Array(result["readings"]).each do |reading|
          record = build_record(node, reading, collected_at)

          if valid_record?(record)
            records << record
          else
            skipped += 1
          end
        end
      end

      BmcSensorReading.insert_all(records) if records.any?

      { inserted: records.size, skipped: skipped, errors: @errors }
    end

    private

    def parse_collected_at(value)
      Time.zone.parse(value) || Time.current
    rescue TypeError, ArgumentError
      Time.current
    end

    def build_record(node, reading, collected_at)
      {
        node_id: node.id,
        sensor_type: reading["type"],
        sensor_name: reading["name"],
        value: reading["value"]&.to_f,
        unit: reading["unit"],
        status: reading["status"],
        recorded_at: collected_at
      }
    end

    def valid_record?(record)
      VALID_SENSOR_TYPES.include?(record[:sensor_type]) &&
        record[:sensor_name].present? &&
        record[:value].present? &&
        record[:unit].present? &&
        record[:recorded_at].present?
    end
  end
end
