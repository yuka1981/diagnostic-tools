# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::ReconciliationService do
  describe ".call" do
    let(:node) { create(:node) }

    subject(:result) { described_class.call(node) }

    context "when no data exists" do
      it "returns empty discrepancies when no inband data exists" do
        create(:bmc_inventory, :with_processors, node: node)

        expect(result.success?).to be true
        expect(result.discrepancies).to eq([])
      end

      it "returns empty discrepancies when no BMC data exists" do
        create(:node_state, :with_cpu_info, node: node)

        expect(result.success?).to be true
        expect(result.discrepancies).to eq([])
      end

      it "returns empty discrepancies when neither data exists" do
        expect(result.success?).to be true
        expect(result.discrepancies).to eq([])
      end
    end

    context "when comparing processor data" do
      it "compares processor cores correctly" do
        # Inband: 20 cores
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        # BMC: 16 cores
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        expect(result.success?).to be true
        expect(result.discrepancies.length).to eq(2)

        core_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.cores" }
        expect(core_discrepancies.length).to eq(2)

        inband_values = core_discrepancies.map(&:inband_value).compact
        bmc_values = core_discrepancies.map(&:bmc_value).compact

        expect(inband_values).to include("20")
        expect(bmc_values).to include("16")
      end

      it "compares processor model correctly and assigns warning severity" do
        create(:node_state, node: node, cpu_info: { "model" => "Intel Xeon Gold 6248" })
        create(:bmc_inventory, node: node, processors: [ { "model" => "Intel Xeon Gold 6248R" } ])

        expect(result.success?).to be true

        model_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.model" }
        expect(model_discrepancies.length).to eq(2)
        expect(model_discrepancies.all? { |d| d.severity == "warning" }).to be true
      end

      it "creates no discrepancies when processor data matches" do
        create(:node_state, node: node, cpu_info: { "model" => "Intel Xeon", "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "model" => "Intel Xeon", "cores" => 20 } ])

        expect(result.success?).to be true

        # Only check model and cores - serial might create discrepancies
        model_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.model" }
        core_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.cores" }

        expect(model_discrepancies).to be_empty
        expect(core_discrepancies).to be_empty
      end
    end

    context "when comparing memory data" do
      it "compares memory sizes correctly" do
        # Inband: memory from dmi_info
        create(:node_state, node: node, dmi_info: {
          "memory" => [
            { "size" => "32 GB", "size_gb" => 32, "serial_number" => "SN001" }
          ]
        })
        # BMC: different size
        create(:bmc_inventory, node: node, memory: [
          { "size_gb" => 64, "serial" => "SN002" }
        ])

        expect(result.success?).to be true

        size_discrepancies = result.discrepancies.select { |d| d.field_path == "memory.*.size_gb" }
        expect(size_discrepancies.length).to eq(2)
        expect(size_discrepancies.all? { |d| d.severity == "warning" }).to be true
      end

      it "compares memory serial numbers with critical severity" do
        create(:node_state, node: node, dmi_info: {
          "memory" => [ { "serial_number" => "MEM001" } ]
        })
        create(:bmc_inventory, node: node, memory: [ { "serial" => "MEM002" } ])

        serial_discrepancies = result.discrepancies.select { |d| d.field_path == "memory.*.serial" }
        expect(serial_discrepancies.length).to eq(2)
        expect(serial_discrepancies.all? { |d| d.severity == "critical" }).to be true
      end
    end

    context "when comparing BIOS data" do
      it "compares BIOS version correctly" do
        create(:node_state, node: node, dmi_info: {
          "bios" => { "version" => "1.0.0" }
        })
        create(:bmc_inventory, node: node, bios: { "version" => "2.0.0" })

        expect(result.success?).to be true

        version_discrepancies = result.discrepancies.select { |d| d.field_path == "bios.version" }
        expect(version_discrepancies.length).to eq(2)
        expect(version_discrepancies.all? { |d| d.severity == "warning" }).to be true
      end

      it "compares BIOS vendor with info severity" do
        create(:node_state, node: node, dmi_info: {
          "bios" => { "vendor" => "AMI" }
        })
        create(:bmc_inventory, node: node, bios: { "vendor" => "Phoenix" })

        vendor_discrepancies = result.discrepancies.select { |d| d.field_path == "bios.vendor" }
        expect(vendor_discrepancies.length).to eq(2)
        expect(vendor_discrepancies.all? { |d| d.severity == "info" }).to be true
      end
    end

    context "when creating InventoryDiscrepancy records" do
      it "creates InventoryDiscrepancy records for differences" do
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        expect { result }.to change(InventoryDiscrepancy, :count).by(2)
      end

      it "associates discrepancies with the correct node" do
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        result.discrepancies.each do |discrepancy|
          expect(discrepancy.node).to eq(node)
        end
      end

      it "assigns correct severity levels" do
        create(:node_state, node: node, dmi_info: {
          "memory" => [ { "serial_number" => "MEM001" } ]
        })
        create(:bmc_inventory, node: node, memory: [ { "serial" => "MEM002" } ])

        serial_discrepancy = result.discrepancies.find { |d| d.field_path == "memory.*.serial" && d.bmc_value == "MEM002" }
        expect(serial_discrepancy.severity).to eq("critical")
      end
    end

    context "when resolving old discrepancies" do
      it "resolves old discrepancies when values now match" do
        # Create an old unresolved discrepancy
        old_discrepancy = create(:inventory_discrepancy,
          node: node,
          field_path: "processors.*.cores",
          inband_value: "20",
          bmc_value: nil,
          resolved_at: nil
        )

        # Now both sources have matching data (no discrepancy)
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 20 } ])

        result

        old_discrepancy.reload
        expect(old_discrepancy.resolved?).to be true
        expect(old_discrepancy.resolution_note).to eq("Auto-resolved: values now match")
      end

      it "does not resolve discrepancies that still exist" do
        # Create a discrepancy that will still be detected
        old_discrepancy = create(:inventory_discrepancy,
          node: node,
          field_path: "processors.*.cores",
          inband_value: "20",
          bmc_value: nil,
          resolved_at: nil
        )

        # Data still has the same discrepancy
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        result

        old_discrepancy.reload
        expect(old_discrepancy.resolved?).to be false
      end
    end

    context "when avoiding duplicates" do
      it "does not duplicate existing unresolved discrepancies" do
        # Create an existing unresolved discrepancy
        existing = create(:inventory_discrepancy,
          node: node,
          field_path: "processors.*.cores",
          inband_value: "20",
          bmc_value: nil,
          resolved_at: nil
        )

        # Set up data that would create the same discrepancy
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        # Should not create a duplicate for the existing discrepancy
        expect { result }.to change(InventoryDiscrepancy, :count).by(1) # Only the BMC-side discrepancy

        # The existing discrepancy should be returned
        expect(result.discrepancies).to include(existing)
      end

      it "creates new discrepancy if existing one is resolved" do
        # Create a resolved discrepancy
        create(:inventory_discrepancy, :resolved, node: node,
          field_path: "processors.*.cores",
          inband_value: "20",
          bmc_value: nil)

        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        # Should create new discrepancies since the old one is resolved
        expect { result }.to change(InventoryDiscrepancy, :count).by(2)
      end
    end

    context "when handling missing fields gracefully" do
      it "handles missing processor data in inband" do
        create(:node_state, node: node, cpu_info: {})
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        expect(result.success?).to be true
        # Should create discrepancy for BMC-only data
        expect(result.discrepancies.any? { |d| d.bmc_value == "16" }).to be true
      end

      it "handles missing processor data in BMC" do
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [])

        expect(result.success?).to be true
        # Should create discrepancy for inband-only data
        expect(result.discrepancies.any? { |d| d.inband_value == "20" }).to be true
      end

      it "handles nil fields in inband data" do
        create(:node_state, node: node, cpu_info: nil)
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        expect(result.success?).to be true
      end

      it "handles nil fields in BMC data" do
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: nil)

        expect(result.success?).to be true
      end

      it "handles missing BIOS data gracefully" do
        create(:node_state, node: node, dmi_info: {})
        create(:bmc_inventory, node: node, bios: { "version" => "2.0.0" })

        expect(result.success?).to be true
        version_discrepancies = result.discrepancies.select { |d| d.field_path == "bios.version" }
        expect(version_discrepancies.any? { |d| d.bmc_value == "2.0.0" }).to be true
      end

      it "handles blank string values" do
        create(:node_state, node: node, cpu_info: { "model" => "" })
        create(:bmc_inventory, node: node, processors: [ { "model" => "Intel Xeon" } ])

        expect(result.success?).to be true
        # Blank values should be filtered out
        model_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.model" }
        expect(model_discrepancies.none? { |d| d.inband_value == "" }).to be true
      end
    end

    context "when an error occurs" do
      it "returns failure result with error message" do
        # Force an error by making the node's inventory_discrepancies raise
        allow(node).to receive(:inventory_discrepancies).and_raise(StandardError.new("Database connection lost"))

        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        create(:bmc_inventory, node: node, processors: [ { "cores" => 16 } ])

        expect(result.success?).to be false
        expect(result.error).to eq("Database connection lost")
      end
    end

    context "with multiple inventory records" do
      it "uses the most recent node_state" do
        old_state = create(:node_state, node: node, cpu_info: { "cores" => 8 }, captured_at: 2.days.ago)
        new_state = create(:node_state, node: node, cpu_info: { "cores" => 20 }, captured_at: 1.hour.ago)
        create(:bmc_inventory, node: node, processors: [ { "cores" => 20 } ])

        expect(result.success?).to be true
        # Should have no discrepancy for cores since new_state matches BMC
        core_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.cores" }
        expect(core_discrepancies).to be_empty
      end

      it "uses the most recent bmc_inventory" do
        create(:node_state, node: node, cpu_info: { "cores" => 20 })
        old_inventory = create(:bmc_inventory, node: node, processors: [ { "cores" => 8 } ], captured_at: 2.days.ago)
        new_inventory = create(:bmc_inventory, node: node, processors: [ { "cores" => 20 } ], captured_at: 1.hour.ago)

        expect(result.success?).to be true
        # Should have no discrepancy for cores since new_inventory matches inband
        core_discrepancies = result.discrepancies.select { |d| d.field_path == "processors.*.cores" }
        expect(core_discrepancies).to be_empty
      end
    end
  end
end
