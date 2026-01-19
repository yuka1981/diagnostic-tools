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
end
