# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorIngestionService do
  let(:node) { create(:node) }

  let(:event_data) do
    {
      "results" => [
        {
          "node_id" => node.id,
          "node_hostname" => node.hostname,
          "protocol" => "redfish",
          "collected_at" => "2026-01-30T10:00:00Z",
          "readings" => [
            { "type" => "temperature", "name" => "cpu1", "value" => 52.0,
              "unit" => "celsius", "status" => "ok" },
            { "type" => "fan", "name" => "fan1", "value" => 4200,
              "unit" => "rpm", "status" => "ok" },
            { "type" => "power", "name" => "psu_total", "value" => 450,
              "unit" => "watts", "status" => "ok" }
          ]
        }
      ],
      "errors" => []
    }
  end

  describe "#call" do
    it "creates sensor readings for the node" do
      expect { described_class.new(event_data).call }
        .to change(BmcSensorReading, :count).by(3)
    end

    it "stores correct sensor values" do
      described_class.new(event_data).call
      temp = BmcSensorReading.find_by(node: node, sensor_type: "temperature")
      expect(temp.value).to eq(52.0)
      expect(temp.unit).to eq("celsius")
    end

    it "skips nodes that do not exist" do
      event_data["results"][0]["node_id"] = 99999
      expect { described_class.new(event_data).call }
        .not_to change(BmcSensorReading, :count)
    end
  end
end
