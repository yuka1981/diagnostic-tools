# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcSensorReading, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:sensor_type) }
    it { is_expected.to validate_presence_of(:sensor_name) }
    it { is_expected.to validate_presence_of(:value) }
    it { is_expected.to validate_presence_of(:unit) }
    it { is_expected.to validate_presence_of(:recorded_at) }
    it { is_expected.to validate_inclusion_of(:sensor_type).in_array(%w[temperature fan power health]) }
  end

  describe "scopes" do
    let(:node) { create(:node) }

    before do
      BmcSensorReading.insert_all([
        { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
          value: 52.0, unit: "celsius", recorded_at: 2.hours.ago },
        { node_id: node.id, sensor_type: "fan", sensor_name: "fan1",
          value: 4200, unit: "rpm", recorded_at: 1.hour.ago },
        { node_id: node.id, sensor_type: "temperature", sensor_name: "cpu1",
          value: 55.0, unit: "celsius", recorded_at: 30.minutes.ago }
      ])
    end

    it "filters by sensor_type" do
      expect(BmcSensorReading.where(sensor_type: "temperature").count).to eq(2)
    end

    it "filters by node" do
      expect(BmcSensorReading.where(node_id: node.id).count).to eq(3)
    end
  end
end
