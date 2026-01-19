# frozen_string_literal: true

require "rails_helper"

RSpec.describe EquipmentRack, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:room).optional }
    it { is_expected.to have_many(:nodes).dependent(:nullify) }
  end

  describe "validations" do
    subject { build(:equipment_rack) }

    it { is_expected.to validate_presence_of(:name) }

    describe "name uniqueness within room scope" do
      context "when rack has a room" do
        let(:room) { create(:room) }
        let!(:existing_rack) { create(:equipment_rack, room: room, name: "R01") }

        it "does not allow duplicate names in the same room" do
          new_rack = build(:equipment_rack, room: room, name: "R01")
          expect(new_rack).not_to be_valid
          expect(new_rack.errors[:name]).to include("has already been taken")
        end

        it "allows same name in different rooms" do
          other_room = create(:room, name: "Other Room")
          new_rack = build(:equipment_rack, room: other_room, name: "R01")
          expect(new_rack).to be_valid
        end
      end

      context "when racks have no room (unassigned)" do
        let!(:existing_rack) { create(:equipment_rack, room: nil, name: "R01") }

        it "does not allow duplicate names among unassigned racks" do
          new_rack = build(:equipment_rack, room: nil, name: "R01")
          expect(new_rack).not_to be_valid
          expect(new_rack.errors[:name]).to include("has already been taken")
        end
      end
    end

    describe "u_height validation" do
      it { is_expected.to validate_numericality_of(:u_height).only_integer }

      it "requires u_height to be greater than 0" do
        rack = build(:equipment_rack, u_height: 0)
        expect(rack).not_to be_valid
        expect(rack.errors[:u_height]).to include("must be greater than 0")
      end

      it "does not allow negative u_height" do
        rack = build(:equipment_rack, u_height: -1)
        expect(rack).not_to be_valid
      end

      it "allows positive u_height" do
        rack = build(:equipment_rack, u_height: 42)
        expect(rack).to be_valid
      end
    end

    describe "width validation" do
      it { is_expected.to validate_numericality_of(:width).only_integer }

      it "requires width to be greater than 0" do
        rack = build(:equipment_rack, width: 0)
        expect(rack).not_to be_valid
        expect(rack.errors[:width]).to include("must be greater than 0")
      end

      it "does not allow negative width" do
        rack = build(:equipment_rack, width: -1)
        expect(rack).not_to be_valid
      end

      it "allows positive width" do
        rack = build(:equipment_rack, width: 19)
        expect(rack).to be_valid
      end
    end
  end

  describe "u_height_not_below_occupied validation" do
    let(:rack) { create(:equipment_rack, u_height: 42) }

    context "when rack has no nodes" do
      it "allows reducing u_height" do
        rack.u_height = 20
        expect(rack).to be_valid
      end
    end

    context "when rack has nodes with rack positions" do
      before do
        create(:node, rack: rack, rack_position: 35, rack_height: 4)
      end

      it "does not allow reducing u_height below highest occupied position" do
        rack.u_height = 37
        expect(rack).not_to be_valid
        expect(rack.errors[:u_height]).to include("cannot be reduced below occupied position 38")
      end

      it "allows reducing u_height above highest occupied position" do
        rack.u_height = 40
        expect(rack).to be_valid
      end

      it "allows u_height equal to highest occupied position" do
        rack.u_height = 38
        expect(rack).to be_valid
      end
    end

    context "when rack has nodes without rack positions" do
      before do
        create(:node, rack: rack, rack_position: nil)
      end

      it "allows reducing u_height" do
        rack.u_height = 20
        expect(rack).to be_valid
      end
    end
  end

  describe "#elevation_data" do
    let(:rack) { create(:equipment_rack, u_height: 10) }

    context "with no nodes" do
      it "returns array of empty units from top to bottom" do
        data = rack.elevation_data(face: :front)

        expect(data.length).to eq(10)
        expect(data.first[:u]).to eq(10)
        expect(data.last[:u]).to eq(1)
        expect(data.all? { |unit| unit[:node].nil? }).to be true
      end
    end

    context "with nodes on front face" do
      let!(:node1) { create(:node, rack: rack, rack_position: 1, rack_height: 2, rack_face: :front) }
      let!(:node2) { create(:node, rack: rack, rack_position: 5, rack_height: 3, rack_face: :front) }

      it "returns units with nodes in correct positions" do
        data = rack.elevation_data(face: :front)

        unit_1 = data.find { |u| u[:u] == 1 }
        unit_2 = data.find { |u| u[:u] == 2 }
        unit_3 = data.find { |u| u[:u] == 3 }
        unit_5 = data.find { |u| u[:u] == 5 }
        unit_6 = data.find { |u| u[:u] == 6 }
        unit_7 = data.find { |u| u[:u] == 7 }

        expect(unit_1[:node]).to eq(node1)
        expect(unit_2[:node]).to eq(node1)
        expect(unit_3[:node]).to be_nil
        expect(unit_5[:node]).to eq(node2)
        expect(unit_6[:node]).to eq(node2)
        expect(unit_7[:node]).to eq(node2)
      end

      it "does not include rear face nodes" do
        create(:node, rack: rack, rack_position: 9, rack_height: 1, rack_face: :rear)
        data = rack.elevation_data(face: :front)

        unit_9 = data.find { |u| u[:u] == 9 }
        expect(unit_9[:node]).to be_nil
      end
    end

    context "with nodes on rear face" do
      let!(:rear_node) { create(:node, rack: rack, rack_position: 3, rack_height: 2, rack_face: :rear) }

      it "returns rear face nodes when face: :rear" do
        data = rack.elevation_data(face: :rear)

        unit_3 = data.find { |u| u[:u] == 3 }
        unit_4 = data.find { |u| u[:u] == 4 }

        expect(unit_3[:node]).to eq(rear_node)
        expect(unit_4[:node]).to eq(rear_node)
      end

      it "does not include rear nodes in front view" do
        data = rack.elevation_data(face: :front)

        unit_3 = data.find { |u| u[:u] == 3 }
        expect(unit_3[:node]).to be_nil
      end
    end

    context "with default face parameter" do
      let!(:front_node) { create(:node, rack: rack, rack_position: 1, rack_height: 1, rack_face: :front) }

      it "defaults to front face" do
        data = rack.elevation_data

        unit_1 = data.find { |u| u[:u] == 1 }
        expect(unit_1[:node]).to eq(front_node)
      end
    end
  end

  describe "#utilization_percentage" do
    let(:rack) { create(:equipment_rack, u_height: 10) }

    context "with no nodes" do
      it "returns 0" do
        expect(rack.utilization_percentage).to eq(0)
      end
    end

    context "with nodes" do
      before do
        create(:node, rack: rack, rack_position: 1, rack_height: 2)
        create(:node, rack: rack, rack_position: 5, rack_height: 3)
      end

      it "returns percentage of occupied space" do
        expect(rack.utilization_percentage).to eq(50.0)
      end
    end

    context "with partial utilization" do
      before do
        create(:node, rack: rack, rack_position: 1, rack_height: 3)
      end

      it "returns correct percentage rounded to 1 decimal" do
        expect(rack.utilization_percentage).to eq(30.0)
      end
    end

    context "with full utilization" do
      before do
        create(:node, rack: rack, rack_position: 1, rack_height: 10)
      end

      it "returns 100" do
        expect(rack.utilization_percentage).to eq(100.0)
      end
    end

    context "when u_height is zero" do
      let(:rack) { build(:equipment_rack, u_height: 1) }

      before do
        rack.save(validate: false)
        rack.update_column(:u_height, 0)
      end

      it "returns 0 to avoid division by zero" do
        expect(rack.utilization_percentage).to eq(0)
      end
    end
  end

  describe "factory" do
    it "creates a valid rack" do
      rack = build(:equipment_rack)
      expect(rack).to be_valid
    end

    it "creates a valid rack with room" do
      room = create(:room)
      rack = build(:equipment_rack, room: room)
      expect(rack).to be_valid
    end

    it "creates a valid rack without room" do
      rack = build(:equipment_rack, room: nil)
      expect(rack).to be_valid
    end

    it "has default u_height of 42" do
      rack = build(:equipment_rack)
      expect(rack.u_height).to eq(42)
    end

    it "has default width of 19" do
      rack = build(:equipment_rack)
      expect(rack.width).to eq(19)
    end
  end

  describe "default values" do
    it "sets u_height to 42 by default" do
      rack = EquipmentRack.new(name: "Test")
      expect(rack.u_height).to eq(42)
    end

    it "sets width to 19 by default" do
      rack = EquipmentRack.new(name: "Test")
      expect(rack.width).to eq(19)
    end
  end
end
