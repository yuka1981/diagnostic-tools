# frozen_string_literal: true

module Bmc
  class SensorQueryService
    RANGES = {
      "24h" => 24.hours,
      "7d" => 7.days,
      "30d" => 30.days,
      "90d" => 90.days
    }.freeze

    def initialize(node, sensor_type: nil, range: "24h")
      @node = node
      @sensor_type = sensor_type
      @range = RANGES.fetch(range, 24.hours)
    end

    def chart_data
      readings = BmcSensorReading
        .for_node(@node.id)
        .since(@range.ago)

      readings = readings.of_type(@sensor_type) if @sensor_type

      readings
        .group_by(&:sensor_name)
        .map do |name, records|
          {
            name: name,
            data: records.sort_by(&:recorded_at).map { |r| [ r.recorded_at, r.value ] }
          }
        end
    end

    def current_readings
      subquery = BmcSensorReading
        .for_node(@node.id)
        .select("DISTINCT ON (sensor_type, sensor_name) *")
        .order(:sensor_type, :sensor_name, recorded_at: :desc)

      records = BmcSensorReading.from(subquery, :bmc_sensor_readings)
      records = records.where(sensor_type: @sensor_type) if @sensor_type
      records.to_a
    end
  end
end
