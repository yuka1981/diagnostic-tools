# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room, type: :model do
  describe "validations" do
    subject { build(:room) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:site_id) }
    it { is_expected.to validate_numericality_of(:floor_area_sqm).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:power_capacity_kw).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:cooling_capacity_kw).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_rack_count).only_integer.is_greater_than(0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:site) }
    it { is_expected.to have_many(:server_racks).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:nodes).through(:server_racks) }
  end

  describe "factory" do
    it "creates a valid room" do
      room = build(:room)
      expect(room).to be_valid
    end
  end

  describe "#rack_count" do
    it "returns the number of racks in the room" do
      room = create(:room)
      create_list(:server_rack, 3, room: room)
      expect(room.rack_count).to eq(3)
    end
  end

  describe "#total_u_capacity" do
    it "returns the sum of u_height for all racks" do
      room = create(:room)
      create(:server_rack, room: room, u_height: 42)
      create(:server_rack, room: room, u_height: 48)
      expect(room.total_u_capacity).to eq(90)
    end
  end

  describe "#total_u_used" do
    it "returns the sum of rack_height for all nodes in the room" do
      room = create(:room)
      rack = create(:server_rack, room: room, u_height: 42)
      create(:node, server_rack: rack, rack_height: 2, rack_position: 1)
      create(:node, server_rack: rack, rack_height: 4, rack_position: 5)
      expect(room.total_u_used).to eq(6)
    end
  end

  describe "#utilization_percentage" do
    it "returns percentage of U capacity used" do
      room = create(:room)
      rack = create(:server_rack, room: room, u_height: 10)
      create(:node, server_rack: rack, rack_height: 2, rack_position: 1)
      expect(room.utilization_percentage).to eq(20.0)
    end

    it "returns 0.0 when no capacity" do
      room = create(:room)
      expect(room.utilization_percentage).to eq(0.0)
    end
  end

  describe "#at_capacity?" do
    it "returns false when max_rack_count is nil" do
      room = create(:room, max_rack_count: nil)
      expect(room.at_capacity?).to be false
    end

    it "returns false when rack count is below max" do
      room = create(:room, max_rack_count: 5)
      create_list(:server_rack, 3, room: room)
      expect(room.at_capacity?).to be false
    end

    it "returns true when rack count equals max" do
      room = create(:room, max_rack_count: 3)
      create_list(:server_rack, 3, room: room)
      expect(room.at_capacity?).to be true
    end
  end
end
