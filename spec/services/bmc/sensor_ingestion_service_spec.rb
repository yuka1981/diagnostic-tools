# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::SensorIngestionService do
  include ActiveSupport::Testing::TimeHelpers

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

    it "returns inserted and skipped counts" do
      result = described_class.new(event_data).call
      expect(result[:inserted]).to eq(3)
      expect(result[:skipped]).to eq(0)
    end

    context "when collected_at is nil" do
      before { event_data["results"][0]["collected_at"] = nil }

      it "falls back to Time.current and still creates readings" do
        travel_to(Time.zone.local(2026, 1, 30, 12, 0, 0)) do
          expect { described_class.new(event_data).call }
            .to change(BmcSensorReading, :count).by(3)
          expect(BmcSensorReading.order(:recorded_at).last.recorded_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "when collected_at is malformed" do
      before { event_data["results"][0]["collected_at"] = "not-a-date" }

      it "falls back to Time.current and still creates readings" do
        travel_to(Time.zone.local(2026, 1, 30, 12, 0, 0)) do
          expect { described_class.new(event_data).call }
            .to change(BmcSensorReading, :count).by(3)
          expect(BmcSensorReading.order(:recorded_at).last.recorded_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "when a reading has an invalid sensor_type" do
      before do
        event_data["results"][0]["readings"] << {
          "type" => "voltage", "name" => "vrm1", "value" => 1.2,
          "unit" => "volts", "status" => "ok"
        }
      end

      it "skips the invalid reading and inserts valid ones" do
        result = described_class.new(event_data).call
        expect(result[:inserted]).to eq(3)
        expect(result[:skipped]).to eq(1)
      end
    end

    context "when a reading is missing required fields" do
      before do
        event_data["results"][0]["readings"] << {
          "type" => "temperature", "name" => nil, "value" => 50.0,
          "unit" => "celsius", "status" => "ok"
        }
      end

      it "skips readings with missing sensor_name" do
        result = described_class.new(event_data).call
        expect(result[:inserted]).to eq(3)
        expect(result[:skipped]).to eq(1)
      end
    end

    context "when a reading is missing unit" do
      before do
        event_data["results"][0]["readings"] << {
          "type" => "temperature", "name" => "cpu2", "value" => 55.0,
          "unit" => nil, "status" => "ok"
        }
      end

      it "skips readings with missing unit" do
        result = described_class.new(event_data).call
        expect(result[:inserted]).to eq(3)
        expect(result[:skipped]).to eq(1)
      end
    end
  end
end
