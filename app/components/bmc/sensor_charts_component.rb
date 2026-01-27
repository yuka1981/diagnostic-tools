# frozen_string_literal: true

module Bmc
  class SensorChartsComponent < ViewComponent::Base
    def initialize(node:, range: "24h")
      @node = node
      @range = range
    end

    def prometheus_configured?
      SshSetting.current.prometheus_url.present?
    end

    def has_bmc_data?
      @node.latest_bmc_inventory.present?
    end

    def temperature_data
      return [] unless prometheus_configured?

      result = query_service.temperature_history(@node, range: @range)
      format_chart_data(result)
    end

    def fan_data
      return [] unless prometheus_configured?

      result = query_service.fan_history(@node, range: @range)
      format_chart_data(result)
    end

    def power_data
      return [] unless prometheus_configured?

      result = query_service.power_history(@node, range: @range)
      format_chart_data(result)
    end

    def range_options
      [
        [ "24 Hours", "24h" ],
        [ "7 Days", "7d" ],
        [ "30 Days", "30d" ]
      ]
    end

    private

    def query_service
      @query_service ||= Bmc::PrometheusQueryService.new
    end

    def format_chart_data(result)
      return [] unless result.success?

      result.data.map do |series|
        sensor_name = series[:metric]["sensor"] || "Unknown"
        data = series[:values].map { |v| [ v[:timestamp], v[:value] ] }
        { name: sensor_name, data: data }
      end
    end
  end
end
