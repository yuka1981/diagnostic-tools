# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::PrometheusQueryService do
  include ActiveSupport::Testing::TimeHelpers

  let(:prometheus_url) { "http://prometheus.example.com:9090" }
  let(:node) { create(:node, hostname: "compute-001") }
  let(:service) { described_class.new(prometheus_url: prometheus_url) }

  describe "#temperature_history" do
    let(:prometheus_response) do
      {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "__name__" => "qis_bmc_temperature_celsius", "node" => "compute-001", "sensor" => "CPU0" },
              values: [
                [ 1704067200, "45.5" ],
                [ 1704070800, "46.2" ]
              ]
            }
          ]
        }
      }.to_json
    end

    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "returns formatted temperature data" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.success?).to be true
      expect(result.data).to be_an(Array)
      expect(result.data.first[:metric]).to include("sensor" => "CPU0")
      expect(result.data.first[:values]).to be_an(Array)
      expect(result.data.first[:values].first[:value]).to eq(45.5)
    end

    it "uses correct query format" do
      stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .with(query: hash_including("query" => 'qis_bmc_temperature_celsius{node="compute-001"}'))
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      service.temperature_history(node)

      expect(stub).to have_been_requested
    end
  end

  describe "#fan_history" do
    let(:prometheus_response) do
      {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "__name__" => "qis_bmc_fan_rpm", "node" => "compute-001", "sensor" => "FAN1" },
              values: [
                [ 1704067200, "3500" ],
                [ 1704070800, "3600" ]
              ]
            }
          ]
        }
      }.to_json
    end

    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "returns formatted fan data" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      result = service.fan_history(node)

      expect(result.success?).to be true
      expect(result.data.first[:metric]).to include("sensor" => "FAN1")
      expect(result.data.first[:values].first[:value]).to eq(3500.0)
    end

    it "uses correct query format" do
      stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .with(query: hash_including("query" => 'qis_bmc_fan_rpm{node="compute-001"}'))
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      service.fan_history(node)

      expect(stub).to have_been_requested
    end
  end

  describe "#power_history" do
    let(:prometheus_response) do
      {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "__name__" => "qis_bmc_power_watts", "node" => "compute-001", "sensor" => "Total Power" },
              values: [
                [ 1704067200, "450" ],
                [ 1704070800, "475" ]
              ]
            }
          ]
        }
      }.to_json
    end

    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "returns formatted power data" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      result = service.power_history(node)

      expect(result.success?).to be true
      expect(result.data.first[:metric]).to include("sensor" => "Total Power")
      expect(result.data.first[:values].first[:value]).to eq(450.0)
    end

    it "uses correct query format" do
      stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .with(query: hash_including("query" => 'qis_bmc_power_watts{node="compute-001"}'))
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      service.power_history(node)

      expect(stub).to have_been_requested
    end
  end

  describe "#voltage_history" do
    let(:prometheus_response) do
      {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "__name__" => "qis_bmc_voltage_volts", "node" => "compute-001", "sensor" => "12V Rail" },
              values: [
                [ 1704067200, "12.1" ],
                [ 1704070800, "12.0" ]
              ]
            }
          ]
        }
      }.to_json
    end

    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "returns formatted voltage data" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

      result = service.voltage_history(node)

      expect(result.success?).to be true
      expect(result.data.first[:metric]).to include("sensor" => "12V Rail")
      expect(result.data.first[:values].first[:value]).to eq(12.1)
    end
  end

  describe "time range handling" do
    let(:prometheus_response) do
      {
        status: "success",
        data: { resultType: "matrix", result: [] }
      }.to_json
    end

    before do
      travel_to Time.zone.local(2024, 1, 15, 12, 0, 0)
    end

    context "with 24h range" do
      it "uses 5m step interval" do
        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("step" => "5m"))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "24h")

        expect(stub).to have_been_requested
      end

      it "queries 24 hours of data" do
        expected_start = (Time.current - 24.hours).to_i.to_s
        expected_end = Time.current.to_i.to_s

        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("start" => expected_start, "end" => expected_end))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "24h")

        expect(stub).to have_been_requested
      end
    end

    context "with 7d range" do
      it "uses 30m step interval" do
        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("step" => "30m"))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "7d")

        expect(stub).to have_been_requested
      end

      it "queries 7 days of data" do
        expected_start = (Time.current - 7.days).to_i.to_s
        expected_end = Time.current.to_i.to_s

        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("start" => expected_start, "end" => expected_end))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "7d")

        expect(stub).to have_been_requested
      end
    end

    context "with 30d range" do
      it "uses 2h step interval" do
        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("step" => "2h"))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "30d")

        expect(stub).to have_been_requested
      end

      it "queries 30 days of data" do
        expected_start = (Time.current - 30.days).to_i.to_s
        expected_end = Time.current.to_i.to_s

        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("start" => expected_start, "end" => expected_end))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "30d")

        expect(stub).to have_been_requested
      end
    end

    context "with unknown range" do
      it "defaults to 24h duration and 5m step" do
        stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .with(query: hash_including("step" => "5m"))
          .to_return(status: 200, body: prometheus_response, headers: { "Content-Type" => "application/json" })

        service.temperature_history(node, range: "unknown")

        expect(stub).to have_been_requested
      end
    end
  end

  describe "error handling" do
    context "when Prometheus is unavailable" do
      before do
        travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
      end

      it "returns error when connection fails" do
        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_raise(Errno::ECONNREFUSED)

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to include("Connection refused")
      end

      it "returns error when request times out" do
        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_raise(Net::ReadTimeout)

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to include("Net::ReadTimeout")
      end

      it "returns error when Prometheus returns HTTP error" do
        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_return(status: 500, body: "Internal Server Error")

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Prometheus returned 500")
      end

      it "returns error when Prometheus returns 503 Service Unavailable" do
        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_return(status: 503, body: "Service Unavailable")

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Prometheus returned 503")
      end
    end

    context "when Prometheus URL is not configured" do
      let(:service) { described_class.new(prometheus_url: nil) }

      before do
        allow(SshSetting).to receive(:current).and_return(
          instance_double(SshSetting, prometheus_url: nil)
        )
      end

      it "returns error for range queries" do
        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Prometheus URL not configured")
      end

      it "returns error for instant queries" do
        result = service.current_sensors(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Prometheus URL not configured")
      end
    end

    context "when Prometheus URL is empty string" do
      let(:service) { described_class.new(prometheus_url: "") }

      before do
        allow(SshSetting).to receive(:current).and_return(
          instance_double(SshSetting, prometheus_url: "")
        )
      end

      it "returns error" do
        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Prometheus URL not configured")
      end
    end

    context "when Prometheus returns error status" do
      before do
        travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
      end

      it "returns Prometheus error message" do
        error_response = {
          status: "error",
          errorType: "bad_data",
          error: "invalid query syntax"
        }.to_json

        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_return(status: 200, body: error_response, headers: { "Content-Type" => "application/json" })

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("invalid query syntax")
      end

      it "returns unknown error when no error message provided" do
        error_response = { status: "error" }.to_json

        stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
          .to_return(status: 200, body: error_response, headers: { "Content-Type" => "application/json" })

        result = service.temperature_history(node)

        expect(result.success?).to be false
        expect(result.error).to eq("Unknown Prometheus error")
      end
    end
  end

  describe "parsing Prometheus response" do
    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "parses multiple time series correctly" do
      multi_series_response = {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "sensor" => "CPU0" },
              values: [ [ 1704067200, "45.5" ] ]
            },
            {
              metric: { "sensor" => "CPU1" },
              values: [ [ 1704067200, "46.0" ] ]
            }
          ]
        }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: multi_series_response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.success?).to be true
      expect(result.data.length).to eq(2)
      expect(result.data[0][:metric]).to include("sensor" => "CPU0")
      expect(result.data[1][:metric]).to include("sensor" => "CPU1")
    end

    it "converts timestamp to ISO8601 format" do
      response = {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "sensor" => "CPU0" },
              values: [ [ 1704067200, "45.5" ] ]
            }
          ]
        }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.data.first[:values].first[:timestamp]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
    end

    it "converts string values to floats" do
      response = {
        status: "success",
        data: {
          resultType: "matrix",
          result: [
            {
              metric: { "sensor" => "CPU0" },
              values: [ [ 1704067200, "45.5" ] ]
            }
          ]
        }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.data.first[:values].first[:value]).to be_a(Float)
      expect(result.data.first[:values].first[:value]).to eq(45.5)
    end
  end

  describe "handling empty results" do
    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "returns empty array when no data found" do
      empty_response = {
        status: "success",
        data: { resultType: "matrix", result: [] }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: empty_response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.success?).to be true
      expect(result.data).to eq([])
    end

    it "handles nil result gracefully" do
      nil_response = {
        status: "success",
        data: { resultType: "matrix", result: nil }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: nil_response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.success?).to be true
      expect(result.data).to eq([])
    end

    it "handles missing data key gracefully" do
      no_data_response = { status: "success" }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: no_data_response, headers: { "Content-Type" => "application/json" })

      result = service.temperature_history(node)

      expect(result.success?).to be true
      expect(result.data).to eq([])
    end
  end

  describe "#current_sensors" do
    let(:instant_response) do
      {
        status: "success",
        data: {
          resultType: "vector",
          result: [
            {
              metric: { "__name__" => "qis_bmc_sensor_status", "node" => "compute-001", "sensor" => "CPU0_Temp" },
              value: [ 1704067200, "1" ]
            },
            {
              metric: { "__name__" => "qis_bmc_sensor_status", "node" => "compute-001", "sensor" => "FAN1" },
              value: [ 1704067200, "0" ]
            }
          ]
        }
      }.to_json
    end

    it "returns instant query data" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query})
        .to_return(status: 200, body: instant_response, headers: { "Content-Type" => "application/json" })

      result = service.current_sensors(node)

      expect(result.success?).to be true
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(2)
    end

    it "uses correct query format for instant query" do
      stub = stub_request(:get, %r{#{prometheus_url}/api/v1/query})
        .with(query: hash_including("query" => 'qis_bmc_sensor_status{node="compute-001"}'))
        .to_return(status: 200, body: instant_response, headers: { "Content-Type" => "application/json" })

      service.current_sensors(node)

      expect(stub).to have_been_requested
    end

    it "parses metric and value correctly" do
      stub_request(:get, %r{#{prometheus_url}/api/v1/query})
        .to_return(status: 200, body: instant_response, headers: { "Content-Type" => "application/json" })

      result = service.current_sensors(node)

      expect(result.data.first[:metric]).to include("sensor" => "CPU0_Temp")
      expect(result.data.first[:value]).to eq(1.0)
    end

    it "handles empty results" do
      empty_response = {
        status: "success",
        data: { resultType: "vector", result: [] }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query})
        .to_return(status: 200, body: empty_response, headers: { "Content-Type" => "application/json" })

      result = service.current_sensors(node)

      expect(result.success?).to be true
      expect(result.data).to eq([])
    end

    it "handles nil value gracefully" do
      nil_value_response = {
        status: "success",
        data: {
          resultType: "vector",
          result: [
            {
              metric: { "sensor" => "CPU0_Temp" },
              value: nil
            }
          ]
        }
      }.to_json

      stub_request(:get, %r{#{prometheus_url}/api/v1/query})
        .to_return(status: 200, body: nil_value_response, headers: { "Content-Type" => "application/json" })

      result = service.current_sensors(node)

      expect(result.success?).to be true
      expect(result.data.first[:value]).to be_nil
    end
  end

  describe "HTTPS support" do
    let(:https_prometheus_url) { "https://prometheus.example.com:9090" }
    let(:https_service) { described_class.new(prometheus_url: https_prometheus_url) }

    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "uses SSL for HTTPS URLs" do
      response = {
        status: "success",
        data: { resultType: "matrix", result: [] }
      }.to_json

      stub_request(:get, %r{#{https_prometheus_url}/api/v1/query_range})
        .to_return(status: 200, body: response, headers: { "Content-Type" => "application/json" })

      result = https_service.temperature_history(node)

      expect(result.success?).to be true
    end
  end

  describe "default prometheus_url from SshSetting" do
    before do
      travel_to Time.zone.local(2024, 1, 1, 12, 0, 0)
    end

    it "uses SshSetting.current.prometheus_url when not provided" do
      allow(SshSetting).to receive(:current).and_return(
        instance_double(SshSetting, prometheus_url: "http://default-prometheus:9090")
      )

      response = {
        status: "success",
        data: { resultType: "matrix", result: [] }
      }.to_json

      stub = stub_request(:get, %r{http://default-prometheus:9090/api/v1/query_range})
        .to_return(status: 200, body: response, headers: { "Content-Type" => "application/json" })

      service_without_url = described_class.new
      service_without_url.temperature_history(node)

      expect(stub).to have_been_requested
    end
  end
end
