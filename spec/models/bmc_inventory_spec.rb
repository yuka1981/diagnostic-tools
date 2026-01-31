# frozen_string_literal: true

require "rails_helper"

RSpec.describe BmcInventory, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:captured_at) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:collection_method).with_values(redfish: 0, ipmi: 1) }
  end

  describe ".latest_for" do
    let(:node) { create(:node) }

    it "returns the most recent inventory for a node" do
      old = create(:bmc_inventory, node: node, captured_at: 2.days.ago)
      latest = create(:bmc_inventory, node: node, captured_at: 1.hour.ago)
      expect(BmcInventory.latest_for(node.id)).to eq(latest)
    end
  end
end
