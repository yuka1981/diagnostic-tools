# frozen_string_literal: true

require "rails_helper"

RSpec.describe InventoryDiscrepancy, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  describe "associations" do
    it { is_expected.to belong_to(:node) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field_path) }
  end

  describe "enums" do
    describe "severity" do
      it "defines info, warning, and critical severities" do
        expect(InventoryDiscrepancy.severities).to eq({ "info" => 0, "warning" => 1, "critical" => 2 })
      end

      it "defaults to info severity" do
        discrepancy = InventoryDiscrepancy.new
        expect(discrepancy.severity).to eq("info")
      end

      it "can be set to warning" do
        discrepancy = build(:inventory_discrepancy, :warning)
        expect(discrepancy).to be_warning
      end

      it "can be set to critical" do
        discrepancy = build(:inventory_discrepancy, :critical)
        expect(discrepancy).to be_critical
      end
    end
  end

  describe "factory" do
    it "creates a valid inventory_discrepancy" do
      discrepancy = build(:inventory_discrepancy)
      expect(discrepancy).to be_valid
    end

    it "creates a valid discrepancy with warning trait" do
      discrepancy = build(:inventory_discrepancy, :warning)
      expect(discrepancy).to be_valid
      expect(discrepancy).to be_warning
    end

    it "creates a valid discrepancy with critical trait" do
      discrepancy = build(:inventory_discrepancy, :critical)
      expect(discrepancy).to be_valid
      expect(discrepancy).to be_critical
    end

    it "creates a valid discrepancy with resolved trait" do
      discrepancy = build(:inventory_discrepancy, :resolved)
      expect(discrepancy).to be_valid
      expect(discrepancy.resolved_at).to be_present
      expect(discrepancy.resolution_note).to be_present
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let!(:unresolved_discrepancy) { create(:inventory_discrepancy, node: node, resolved_at: nil) }
    let!(:resolved_discrepancy) { create(:inventory_discrepancy, :resolved, node: node) }

    describe ".unresolved" do
      it "returns only discrepancies where resolved_at is nil" do
        expect(InventoryDiscrepancy.unresolved).to eq([ unresolved_discrepancy ])
      end
    end

    describe ".resolved" do
      it "returns only discrepancies where resolved_at is present" do
        expect(InventoryDiscrepancy.resolved).to eq([ resolved_discrepancy ])
      end
    end
  end

  describe "#resolved?" do
    it "returns true when resolved_at is present" do
      discrepancy = build(:inventory_discrepancy, :resolved)
      expect(discrepancy.resolved?).to be true
    end

    it "returns false when resolved_at is nil" do
      discrepancy = build(:inventory_discrepancy, resolved_at: nil)
      expect(discrepancy.resolved?).to be false
    end
  end

  describe "#resolve!" do
    let(:discrepancy) { create(:inventory_discrepancy, resolved_at: nil, resolution_note: nil) }

    it "sets resolved_at to current time" do
      freeze_time do
        discrepancy.resolve!
        expect(discrepancy.resolved_at).to eq(Time.current)
      end
    end

    it "persists the change" do
      discrepancy.resolve!
      expect(discrepancy.reload.resolved_at).to be_present
    end

    context "with a note" do
      it "sets the resolution_note" do
        discrepancy.resolve!("Fixed by manual inspection")
        expect(discrepancy.resolution_note).to eq("Fixed by manual inspection")
      end
    end

    context "without a note" do
      it "leaves resolution_note as nil" do
        discrepancy.resolve!
        expect(discrepancy.resolution_note).to be_nil
      end
    end
  end

  describe "Node#inventory_discrepancies association" do
    let(:node) { create(:node) }

    it "allows node to have multiple discrepancies" do
      create_list(:inventory_discrepancy, 3, node: node)
      expect(node.inventory_discrepancies.count).to eq(3)
    end

    it "destroys discrepancies when node is destroyed" do
      create(:inventory_discrepancy, node: node)
      expect { node.destroy }.to change(InventoryDiscrepancy, :count).by(-1)
    end
  end
end
