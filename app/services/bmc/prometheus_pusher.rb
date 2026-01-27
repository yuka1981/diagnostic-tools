# frozen_string_literal: true

require "net/http"
require "uri"

module Bmc
  class PrometheusPusher
    Result = Struct.new(:success, :error, keyword_init: true) do
      def success? = success
    end

    METRIC_MAPPINGS = {
      "temperature" => "qis_bmc_temperature_celsius",
      "fan" => "qis_bmc_fan_rpm",
      "power" => "qis_bmc_power_watts",
      "voltage" => "qis_bmc_voltage_volts",
      "current" => "qis_bmc_current_amps"
    }.freeze

    STATUS_VALUES = {
      "OK" => 0,
      "Warning" => 1,
      "Critical" => 2
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(node_id:, sensors:)
      @node_id = node_id
      @sensors = sensors || []
    end

    def call
      node = find_node
      return Result.new(success: false, error: "Node not found") unless node

      pushgateway_url = SshSetting.current.prometheus_pushgateway_url
      return Result.new(success: false, error: "Pushgateway URL not configured") if pushgateway_url.blank?

      metrics = format_metrics(node, @sensors)
      push_to_gateway(pushgateway_url, node.hostname, metrics)
    rescue StandardError => e
      Result.new(success: false, error: e.message)
    end

    private

    def find_node
      # Try to find by database id first
      return Node.find_by(id: @node_id) if @node_id.to_s.match?(/\A\d+\z/)

      # Try to find by uuid
      node = Node.find_by(uuid: @node_id)
      return node if node

      # Try to find by hostname
      Node.find_by(hostname: @node_id)
    end

    def format_metrics(node, sensors)
      lines = []

      sensors.each do |sensor|
        metric_name = determine_metric_name(sensor[:unit])
        next unless metric_name

        # Value metric
        lines << "#{metric_name}{node=\"#{node.hostname}\",sensor=\"#{escape_label(sensor[:name])}\"} #{sensor[:value]}"

        # Status metric
        status_value = STATUS_VALUES[sensor[:status]] || 0
        lines << "qis_bmc_sensor_status{node=\"#{node.hostname}\",sensor=\"#{escape_label(sensor[:name])}\",status=\"#{sensor[:status]}\"} #{status_value}"
      end

      lines.join("\n")
    end

    def determine_metric_name(unit)
      case unit&.downcase
      when "celsius", "c", "degrees c" then METRIC_MAPPINGS["temperature"]
      when "rpm" then METRIC_MAPPINGS["fan"]
      when "watts", "w" then METRIC_MAPPINGS["power"]
      when "volts", "v" then METRIC_MAPPINGS["voltage"]
      when "amps", "a" then METRIC_MAPPINGS["current"]
      end
    end

    def escape_label(value)
      value.to_s.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }.gsub("\n") { '\\n' }
    end

    def push_to_gateway(url, job_instance, metrics)
      uri = URI.parse("#{url}/metrics/job/qis_bmc_collector/instance/#{job_instance}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request.body = metrics
      request["Content-Type"] = "text/plain"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        Result.new(success: true)
      else
        Result.new(success: false, error: "Pushgateway returned #{response.code}: #{response.body}")
      end
    end
  end
end
