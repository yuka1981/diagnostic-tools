# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarHelper, type: :helper do
  describe "#sidebar_rooms" do
    it "returns all rooms ordered by name" do
      room_b = create(:room, name: "Server Room B")
      room_a = create(:room, name: "Data Center A")

      result = helper.sidebar_rooms

      expect(result.map(&:name)).to eq([ "Data Center A", "Server Room B" ])
    end

    it "returns empty array when no rooms exist" do
      expect(helper.sidebar_rooms).to eq([])
    end
  end
end
