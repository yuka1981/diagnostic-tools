# frozen_string_literal: true

module Bmc
  class PrometheusQueryService
    Result = Struct.new(:success, :data, :error, keyword_init: true) do
      def success? = success
    end

    RANGE_DURATIONS = {
      "24h" => 24.hours,
      "7d" => 7.days,
      "30d" => 30.days
    }.freeze

    STEP_INTERVALS = {
      "24h" => "5m",
      "7d" => "30m",
      "30d" => "2h"
    }.freeze

    def initialize(prometheus_url: nil)
      @prometheus_url = prometheus_url || SshSetting.current.prometheus_url
    end

    def temperature_history(node, range: "24h")
      query = "qis_bmc_temperature_celsius{node=\"#{node.hostname}\"}"
      execute_range_query(query, range)
    end

    def fan_history(node, range: "24h")
      query = "qis_bmc_fan_rpm{node=\"#{node.hostname}\"}"
      execute_range_query(query, range)
    end

    def power_history(node, range: "24h")
      query = "qis_bmc_power_watts{node=\"#{node.hostname}\"}"
      execute_range_query(query, range)
    end

    def voltage_history(node, range: "24h")
      query = "qis_bmc_voltage_volts{node=\"#{node.hostname}\"}"
      execute_range_query(query, range)
    end

    def current_sensors(node)
      query = "qis_bmc_sensor_status{node=\"#{node.hostname}\"}"
      execute_instant_query(query)
    end

    private

    def execute_range_query(query, range)
      return Result.new(success: false, error: "Prometheus URL not configured") if @prometheus_url.blank?

      duration = RANGE_DURATIONS[range] || 24.hours
      step = STEP_INTERVALS[range] || "5m"

      end_time = Time.current
      start_time = end_time - duration

      uri = URI.parse("#{@prometheus_url}/api/v1/query_range")
      uri.query = URI.encode_www_form(
        query: query,
        start: start_time.to_i,
        end: end_time.to_i,
        step: step
      )

      response = make_request(uri)
      parse_range_response(response)
    rescue StandardError => e
      Result.new(success: false, error: e.message)
    end

    def execute_instant_query(query)
      return Result.new(success: false, error: "Prometheus URL not configured") if @prometheus_url.blank?

      uri = URI.parse("#{@prometheus_url}/api/v1/query")
      uri.query = URI.encode_www_form(query: query)

      response = make_request(uri)
      parse_instant_response(response)
    rescue StandardError => e
      Result.new(success: false, error: e.message)
    end

    def make_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      http.request(request)
    end

    def parse_range_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        return Result.new(success: false, error: "Prometheus returned #{response.code}")
      end

      json = JSON.parse(response.body)

      unless json["status"] == "success"
        return Result.new(success: false, error: json["error"] || "Unknown Prometheus error")
      end

      data = json.dig("data", "result")&.map do |series|
        {
          metric: series["metric"],
          values: series["values"].map { |ts, val| { timestamp: Time.at(ts).iso8601, value: val.to_f } }
        }
      end || []

      Result.new(success: true, data: data)
    end

    def parse_instant_response(response)
      unless response.is_a?(Net::HTTPSuccess)
        return Result.new(success: false, error: "Prometheus returned #{response.code}")
      end

      json = JSON.parse(response.body)

      unless json["status"] == "success"
        return Result.new(success: false, error: json["error"] || "Unknown Prometheus error")
      end

      data = json.dig("data", "result")&.map do |series|
        {
          metric: series["metric"],
          value: series["value"]&.last&.to_f
        }
      end || []

      Result.new(success: true, data: data)
    end
  end
end
