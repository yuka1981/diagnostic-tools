# frozen_string_literal: true

require "rails_helper"

RSpec.describe InventoryDiscrepancy, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field_path) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:severity).with_values(info: 0, warning: 1, critical: 2) }
  end

  describe "scopes" do
    let(:node) { create(:node) }

    it "returns unresolved discrepancies" do
      unresolved = create(:inventory_discrepancy, node: node)
      create(:inventory_discrepancy, :resolved, node: node)
      expect(InventoryDiscrepancy.unresolved).to contain_exactly(unresolved)
    end

    it "returns resolved discrepancies" do
      create(:inventory_discrepancy, node: node)
      resolved = create(:inventory_discrepancy, :resolved, node: node)
      expect(InventoryDiscrepancy.resolved).to contain_exactly(resolved)
    end
  end

  describe "#resolved?" do
    it "returns true when resolved_at is present" do
      discrepancy = build(:inventory_discrepancy, resolved_at: Time.current)
      expect(discrepancy).to be_resolved
    end

    it "returns false when resolved_at is nil" do
      discrepancy = build(:inventory_discrepancy, resolved_at: nil)
      expect(discrepancy).not_to be_resolved
    end
  end

  describe "#resolve!" do
    it "sets resolved_at and resolution_note" do
      discrepancy = create(:inventory_discrepancy)
      discrepancy.resolve!(note: "Verified correct")
      expect(discrepancy.resolved_at).to be_present
      expect(discrepancy.resolution_note).to eq("Verified correct")
    end
  end
end
