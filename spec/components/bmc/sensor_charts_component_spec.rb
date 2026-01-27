# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorChartsComponent, type: :component do
  let(:node) { create(:node) }
  let(:range) { "24h" }

  subject(:component) { described_class.new(node: node, range: range) }

  before do
    # Ensure SshSetting exists with prometheus_url cleared by default
    SshSetting.current.update!(prometheus_url: nil)
  end

  describe "#prometheus_configured?" do
    context "when prometheus_url is present" do
      before { SshSetting.current.update!(prometheus_url: "http://prometheus:9090") }

      it "returns true" do
        expect(component.prometheus_configured?).to be true
      end
    end

    context "when prometheus_url is blank" do
      it "returns false" do
        expect(component.prometheus_configured?).to be false
      end
    end
  end

  describe "#has_bmc_data?" do
    context "when node has bmc inventory" do
      before { create(:bmc_inventory, node: node) }

      it "returns true" do
        expect(component.has_bmc_data?).to be true
      end
    end

    context "when node has no bmc inventory" do
      it "returns false" do
        expect(component.has_bmc_data?).to be false
      end
    end
  end

  describe "#range_options" do
    it "returns array of range options" do
      expect(component.range_options).to eq([
        [ "24 Hours", "24h" ],
        [ "7 Days", "7d" ],
        [ "30 Days", "30d" ]
      ])
    end
  end

  describe "#temperature_data" do
    context "when prometheus is not configured" do
      it "returns empty array" do
        expect(component.temperature_data).to eq([])
      end
    end

    context "when prometheus is configured" do
      let(:query_service) { instance_double(Bmc::PrometheusQueryService) }
      let(:result) { Bmc::PrometheusQueryService::Result.new(success: true, data: prometheus_data) }
      let(:prometheus_data) do
        [
          {
            metric: { "sensor" => "CPU Temp" },
            values: [
              { timestamp: "2026-01-27T10:00:00Z", value: 45.0 },
              { timestamp: "2026-01-27T11:00:00Z", value: 47.0 }
            ]
          }
        ]
      end

      before do
        SshSetting.current.update!(prometheus_url: "http://prometheus:9090")
        allow(Bmc::PrometheusQueryService).to receive(:new).and_return(query_service)
        allow(query_service).to receive(:temperature_history).and_return(result)
      end

      it "returns formatted chart data" do
        data = component.temperature_data
        expect(data).to eq([
          {
            name: "CPU Temp",
            data: [
              [ "2026-01-27T10:00:00Z", 45.0 ],
              [ "2026-01-27T11:00:00Z", 47.0 ]
            ]
          }
        ])
      end
    end
  end

  describe "#fan_data" do
    context "when prometheus is not configured" do
      it "returns empty array" do
        expect(component.fan_data).to eq([])
      end
    end

    context "when prometheus is configured" do
      let(:query_service) { instance_double(Bmc::PrometheusQueryService) }
      let(:result) { Bmc::PrometheusQueryService::Result.new(success: true, data: prometheus_data) }
      let(:prometheus_data) do
        [
          {
            metric: { "sensor" => "Fan 1" },
            values: [
              { timestamp: "2026-01-27T10:00:00Z", value: 3000.0 }
            ]
          }
        ]
      end

      before do
        SshSetting.current.update!(prometheus_url: "http://prometheus:9090")
        allow(Bmc::PrometheusQueryService).to receive(:new).and_return(query_service)
        allow(query_service).to receive(:fan_history).and_return(result)
      end

      it "returns formatted chart data" do
        data = component.fan_data
        expect(data).to eq([
          {
            name: "Fan 1",
            data: [ [ "2026-01-27T10:00:00Z", 3000.0 ] ]
          }
        ])
      end
    end
  end

  describe "#power_data" do
    context "when prometheus is not configured" do
      it "returns empty array" do
        expect(component.power_data).to eq([])
      end
    end

    context "when prometheus is configured" do
      let(:query_service) { instance_double(Bmc::PrometheusQueryService) }
      let(:result) { Bmc::PrometheusQueryService::Result.new(success: true, data: prometheus_data) }
      let(:prometheus_data) do
        [
          {
            metric: { "sensor" => "PSU Power" },
            values: [
              { timestamp: "2026-01-27T10:00:00Z", value: 250.0 }
            ]
          }
        ]
      end

      before do
        SshSetting.current.update!(prometheus_url: "http://prometheus:9090")
        allow(Bmc::PrometheusQueryService).to receive(:new).and_return(query_service)
        allow(query_service).to receive(:power_history).and_return(result)
      end

      it "returns formatted chart data" do
        data = component.power_data
        expect(data).to eq([
          {
            name: "PSU Power",
            data: [ [ "2026-01-27T10:00:00Z", 250.0 ] ]
          }
        ])
      end
    end
  end

  describe "#format_chart_data" do
    context "when result is not successful" do
      let(:result) { Bmc::PrometheusQueryService::Result.new(success: false, error: "Error") }

      it "returns empty array" do
        expect(component.send(:format_chart_data, result)).to eq([])
      end
    end

    context "when result has missing sensor name" do
      let(:result) do
        Bmc::PrometheusQueryService::Result.new(
          success: true,
          data: [
            {
              metric: {},
              values: [ { timestamp: "2026-01-27T10:00:00Z", value: 100.0 } ]
            }
          ]
        )
      end

      it "uses Unknown as sensor name" do
        data = component.send(:format_chart_data, result)
        expect(data.first[:name]).to eq("Unknown")
      end
    end
  end

  describe "#render" do
    subject(:rendered) { render_inline(component) }

    context "when prometheus is not configured" do
      it "shows prometheus not configured message" do
        expect(rendered.text).to include("Prometheus not configured")
      end

      it "shows configuration hint" do
        expect(rendered.text).to include("Configure Prometheus URL in settings")
      end
    end

    context "when prometheus is configured but no BMC data" do
      before { SshSetting.current.update!(prometheus_url: "http://prometheus:9090") }

      it "shows no sensor data message" do
        expect(rendered.text).to include("No sensor data available")
      end

      it "shows collection hint" do
        expect(rendered.text).to include("Collect BMC inventory")
      end
    end

    context "when prometheus is configured and has BMC data" do
      let(:query_service) { instance_double(Bmc::PrometheusQueryService) }
      let(:empty_result) { Bmc::PrometheusQueryService::Result.new(success: true, data: []) }

      before do
        SshSetting.current.update!(prometheus_url: "http://prometheus:9090")
        create(:bmc_inventory, node: node)
        allow(Bmc::PrometheusQueryService).to receive(:new).and_return(query_service)
        allow(query_service).to receive(:temperature_history).and_return(empty_result)
        allow(query_service).to receive(:fan_history).and_return(empty_result)
        allow(query_service).to receive(:power_history).and_return(empty_result)
      end

      it "renders temperature chart section" do
        expect(rendered.text).to include("Temperature")
      end

      it "renders fan speed chart section" do
        expect(rendered.text).to include("Fan Speed")
      end

      it "renders power chart section" do
        expect(rendered.text).to include("Power Consumption")
      end

      it "shows no data message when charts have no data" do
        expect(rendered.text).to include("No temperature data")
        expect(rendered.text).to include("No fan speed data")
        expect(rendered.text).to include("No power data")
      end
    end

    it "renders range selector buttons" do
      expect(rendered.text).to include("24 Hours")
      expect(rendered.text).to include("7 Days")
      expect(rendered.text).to include("30 Days")
    end

    it "renders card with sensor-chart controller" do
      expect(rendered.css("[data-controller='sensor-chart']")).to be_present
    end

    it "renders sensor data title" do
      expect(rendered.text).to include("Sensor Data")
    end

    context "with different range values" do
      let(:range) { "7d" }

      it "highlights the active range button" do
        link = rendered.css("a").find { |a| a.text.strip == "7 Days" }
        expect(link["class"]).to include("bg-primary-6")
      end

      it "does not highlight inactive range buttons" do
        link = rendered.css("a").find { |a| a.text.strip == "24 Hours" }
        expect(link["class"]).to include("bg-neutral-4")
      end
    end
  end
end
