# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorQueryService do
  let(:node) { create(:node) }

  before do
    readings = (1..24).map do |hour|
      { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
        value: 50.0 + rand(10), unit: "celsius", status: "ok",
        recorded_at: hour.hours.ago + 1.minute }
    end
    BmcSensorReading.insert_all(readings)
  end

  describe "#chart_data" do
    it "returns data grouped by sensor name" do
      service = described_class.new(node, sensor_type: "temperature", range: "24h")
      data = service.chart_data
      expect(data).to be_a(Array)
      expect(data.first[:name]).to eq("cpu1")
      expect(data.first[:data].length).to eq(24)
    end
  end

  describe "#current_readings" do
    it "returns the latest reading per sensor" do
      service = described_class.new(node, sensor_type: "temperature")
      readings = service.current_readings
      expect(readings.length).to eq(1)
      expect(readings.first.sensor_name).to eq("cpu1")
    end
  end
end
