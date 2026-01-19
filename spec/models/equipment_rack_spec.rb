# frozen_string_literal: true

require "rails_helper"

RSpec.describe EquipmentRack, type: :model do
  describe "validations" do
    subject { build(:equipment_rack) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:room_id) }
    it { is_expected.to validate_numericality_of(:u_height).only_integer.is_greater_than(0) }
    it { is_expected.to validate_numericality_of(:width).only_integer.is_greater_than(0) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:room).optional }
    it { is_expected.to have_many(:nodes).dependent(:nullify) }
  end

  describe "factory" do
    it "creates a valid equipment rack" do
      rack = build(:equipment_rack)
      expect(rack).to be_valid
    end

    it "creates a valid rack with a room" do
      room = create(:room)
      rack = build(:equipment_rack, room: room)
      expect(rack).to be_valid
      expect(rack.room).to eq(room)
    end

    it "defaults to 42U height" do
      rack = build(:equipment_rack)
      expect(rack.u_height).to eq(42)
    end

    it "defaults to 19-inch width" do
      rack = build(:equipment_rack)
      expect(rack.width).to eq(19)
    end
  end

  describe "table_name" do
    it "uses racks table" do
      expect(described_class.table_name).to eq("racks")
    end
  end

  describe "#u_height_not_below_occupied" do
    let(:rack) { create(:equipment_rack, u_height: 42) }

    context "when rack has no nodes" do
      it "allows reducing u_height" do
        rack.u_height = 20
        expect(rack).to be_valid
      end
    end

    context "when rack has nodes with rack_position" do
      before do
        create(:node, rack: rack, rack_position: 35, rack_height: 3)
        # Occupies U35, U36, U37
      end

      it "allows reducing u_height if nodes still fit" do
        rack.u_height = 40
        expect(rack).to be_valid
      end

      it "prevents reducing u_height below highest occupied position" do
        rack.u_height = 36
        expect(rack).not_to be_valid
        expect(rack.errors[:u_height].first).to match(/cannot be reduced below occupied position/)
      end
    end
  end
end
