# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room, type: :model do
  describe "validations" do
    subject { build(:room) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:equipment_racks).dependent(:restrict_with_error) }
  end

  describe "factory" do
    it "creates a valid room" do
      room = build(:room)
      expect(room).to be_valid
    end

    it "creates a valid room with description" do
      room = build(:room, description: "Main server room")
      expect(room).to be_valid
      expect(room.description).to eq("Main server room")
    end
  end

  describe "restrict_with_error behavior" do
    context "when room has associated racks" do
      let(:room) { create(:room) }
      let!(:rack) { create(:equipment_rack, room: room) }

      it "prevents deletion and adds error" do
        expect(room.destroy).to be false
        expect(room.errors[:base]).to include(/Cannot delete record because dependent equipment racks exist/)
      end
    end

    context "when room has no associated racks" do
      let(:room) { create(:room) }

      it "allows deletion" do
        expect(room.destroy).to be_truthy
        expect(Room.exists?(room.id)).to be false
      end
    end
  end

  describe "#racks_by_row" do
    let(:room) { create(:room) }

    context "when room has racks with rows assigned" do
      before do
        create(:equipment_rack, name: "R01", row: "A", room: room)
        create(:equipment_rack, name: "R02", row: "A", room: room)
        create(:equipment_rack, name: "R03", row: "B", room: room)
      end

      it "returns racks grouped by row name" do
        result = room.racks_by_row

        expect(result.keys).to contain_exactly("A", "B")
        expect(result["A"].map(&:name)).to eq(%w[R01 R02])
        expect(result["B"].map(&:name)).to eq(%w[R03])
      end
    end

    context "when room has racks without row assigned" do
      before do
        create(:equipment_rack, name: "R01", row: nil, room: room)
        create(:equipment_rack, name: "R02", row: "", room: room)
        create(:equipment_rack, name: "R03", row: "A", room: room)
      end

      it "returns racks without row grouped under 'Unassigned'" do
        result = room.racks_by_row

        expect(result.keys).to contain_exactly("Unassigned", "A")
        expect(result["Unassigned"].map(&:name)).to contain_exactly("R01", "R02")
        expect(result["A"].map(&:name)).to eq(%w[R03])
      end
    end

    context "when ordering racks" do
      before do
        create(:equipment_rack, name: "R03", row: "B", room: room)
        create(:equipment_rack, name: "R01", row: "A", room: room)
        create(:equipment_rack, name: "R02", row: "A", room: room)
        create(:equipment_rack, name: "R04", row: "B", room: room)
      end

      it "orders racks by row, then by name within each group" do
        result = room.racks_by_row

        expect(result.keys).to eq(%w[A B])
        expect(result["A"].map(&:name)).to eq(%w[R01 R02])
        expect(result["B"].map(&:name)).to eq(%w[R03 R04])
      end
    end

    context "when room has no racks" do
      it "returns an empty hash" do
        expect(room.racks_by_row).to eq({})
      end
    end
  end
end
