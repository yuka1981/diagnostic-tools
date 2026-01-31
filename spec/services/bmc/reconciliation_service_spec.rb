# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::ReconciliationService do
  let(:node) { create(:node) }

  let!(:node_state) do
    create(:node_state, node: node, cpu_info: {
      "model" => "Xeon Gold 6248",
      "cores" => 20,
      "sockets" => 2
    })
  end

  let!(:bmc_inventory) do
    create(:bmc_inventory, node: node, processors: [
      { "model" => "Xeon Gold 6248", "cores_physical" => 20, "serial" => "SN123" },
      { "model" => "Xeon Gold 6248", "cores_physical" => 20, "serial" => "SN456" }
    ])
  end

  describe "#call" do
    context "when data matches" do
      it "does not create discrepancies" do
        expect { described_class.new(node).call }
          .not_to change(InventoryDiscrepancy, :count)
      end
    end

    context "when core count differs" do
      before do
        bmc_inventory.update!(processors: [
          { "model" => "Xeon Gold 6248", "cores_physical" => 24, "serial" => "SN123" }
        ])
      end

      it "creates a discrepancy" do
        expect { described_class.new(node).call }
          .to change(InventoryDiscrepancy, :count).by_at_least(1)
      end
    end

    context "when previous discrepancy is resolved" do
      let!(:old_discrepancy) do
        create(:inventory_discrepancy, node: node, field_path: "processors.0.cores_physical")
      end

      it "auto-resolves discrepancies that no longer exist" do
        described_class.new(node).call
        expect(old_discrepancy.reload).to be_resolved
      end
    end
  end
end
