# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::InventoryComponent, type: :component do
  let(:node) { create(:node) }

  subject(:component) { described_class.new(node: node) }

  describe "#render" do
    subject(:rendered) { render_inline(component) }

    context "when node has no BMC inventory" do
      it "shows 'No BMC inventory' message" do
        expect(rendered.text).to include("No BMC inventory collected")
      end

      it "shows hint to collect inventory" do
        expect(rendered.text).to include("Collect Now")
      end

      it "renders the card-netbox container" do
        expect(rendered.css(".card-netbox")).to be_present
      end

      it "does not render tabs" do
        expect(rendered.css("[data-controller='tabs']")).not_to be_present
      end
    end

    context "when node has BMC inventory" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :complete, node: node, captured_at: 5.minutes.ago)
      end

      it "renders tabs for all inventory categories" do
        expect(rendered.css("[data-tabs-target='tab']").length).to eq(6)
      end

      it "displays processor tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Processors")
      end

      it "displays memory tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Memory")
      end

      it "displays storage tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Storage")
      end

      it "displays network tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Network")
      end

      it "displays infiniband tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Infiniband")
      end

      it "displays bios tab" do
        tab_texts = rendered.css("[data-tabs-target='tab']").map(&:text)
        expect(tab_texts.join).to include("Bios")
      end

      it "shows collection method in header" do
        expect(rendered.text).to include("Redfish")
      end

      it "shows time ago in header" do
        expect(rendered.text).to include("5 minutes ago")
      end

      it "displays processor count badge" do
        # The :complete trait has 2 processors
        processor_tab = rendered.css("[data-tabs-target='tab']").first
        expect(processor_tab.text).to include("2")
      end

      it "displays memory count badge" do
        # The :complete trait has 2 memory modules
        memory_tab = rendered.css("[data-tabs-target='tab']")[1]
        expect(memory_tab.text).to include("2")
      end

      it "renders tab panels" do
        expect(rendered.css("[data-tabs-target='panel']").length).to eq(6)
      end
    end

    context "with processor data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_processors, node: node, captured_at: 1.hour.ago)
      end

      it "renders processor table with data" do
        expect(rendered.css("table")).to be_present
        expect(rendered.text).to include("Intel(R) Xeon(R) Gold 6248")
      end

      it "displays processor socket" do
        expect(rendered.text).to include("CPU1")
      end

      it "displays processor cores" do
        expect(rendered.text).to include("20")
      end
    end

    context "with memory data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_memory, node: node, captured_at: 1.hour.ago)
      end

      it "renders memory table with data" do
        expect(rendered.text).to include("DIMM_A1")
      end

      it "displays memory size" do
        expect(rendered.text).to include("32 GB")
      end

      it "displays memory type" do
        expect(rendered.text).to include("DDR4")
      end

      it "displays memory speed" do
        expect(rendered.text).to include("3200 MHz")
      end

      it "displays manufacturer" do
        expect(rendered.text).to include("Samsung")
      end
    end

    context "with storage data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_storage, node: node, captured_at: 1.hour.ago)
      end

      it "renders storage table with data" do
        expect(rendered.text).to include("Disk 0")
      end

      it "displays storage model" do
        expect(rendered.text).to include("MZ7LH480HAHQ")
      end
    end

    context "with network data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_network, node: node, captured_at: 1.hour.ago)
      end

      it "renders network table with MAC address" do
        expect(rendered.text).to include("00:11:22:33:44:55")
      end

      it "displays network model" do
        expect(rendered.text).to include("ConnectX-6")
      end
    end

    context "with infiniband data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_infiniband, node: node, captured_at: 1.hour.ago)
      end

      it "renders infiniband table with GUID" do
        expect(rendered.text).to include("0x0011223344556677")
      end

      it "displays port state with status badge" do
        expect(rendered.text).to include("Active")
      end
    end

    context "with bios data" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :with_bios, node: node, captured_at: 1.hour.ago)
      end

      it "renders bios info" do
        expect(rendered.text).to include("AMI")
      end

      it "displays bios version" do
        expect(rendered.text).to include("2.5.1")
      end

      it "displays bios release date" do
        expect(rendered.text).to include("2024-01-15")
      end
    end

    context "with empty arrays" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, node: node, captured_at: 1.hour.ago)
      end

      it "shows no processor data message" do
        expect(rendered.text).to include("No processor data available")
      end

      it "shows count badge of 0 for processors" do
        processor_tab = rendered.css("[data-tabs-target='tab']").first
        # Count badge should not be shown when count is 0
        expect(processor_tab.css(".rounded-full")).not_to be_present
      end
    end

    context "via IPMI collection method" do
      let!(:bmc_inventory) do
        create(:bmc_inventory, :via_ipmi, node: node, captured_at: 1.hour.ago)
      end

      it "shows IPMI as collection method" do
        expect(rendered.text).to include("Ipmi")
      end
    end
  end

  describe "#tabs" do
    context "with default active_tab" do
      it "returns 6 tabs" do
        expect(component.tabs.length).to eq(6)
      end

      it "marks processors as active by default" do
        processors_tab = component.tabs.find { |t| t[:id] == "processors" }
        expect(processors_tab[:active]).to be true
      end
    end

    context "with custom active_tab" do
      subject(:component) { described_class.new(node: node, active_tab: "memory") }

      it "marks specified tab as active" do
        memory_tab = component.tabs.find { |t| t[:id] == "memory" }
        expect(memory_tab[:active]).to be true
      end

      it "marks other tabs as inactive" do
        processors_tab = component.tabs.find { |t| t[:id] == "processors" }
        expect(processors_tab[:active]).to be false
      end
    end
  end

  describe "#has_inventory?" do
    context "when node has no inventory" do
      it "returns false" do
        expect(component.has_inventory?).to be false
      end
    end

    context "when node has inventory" do
      before { create(:bmc_inventory, node: node) }

      it "returns true" do
        expect(component.has_inventory?).to be true
      end
    end
  end

  describe "#collection_method" do
    context "when no inventory" do
      it "returns Unknown" do
        expect(component.collection_method).to eq("Unknown")
      end
    end

    context "with redfish inventory" do
      before { create(:bmc_inventory, :via_redfish, node: node) }

      it "returns humanized method" do
        expect(component.collection_method).to eq("Redfish")
      end
    end
  end
end
