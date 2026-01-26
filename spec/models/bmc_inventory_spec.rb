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

  describe "factory" do
    it "creates a valid bmc_inventory" do
      bmc_inventory = build(:bmc_inventory)
      expect(bmc_inventory).to be_valid
    end

    it "creates a bmc_inventory with processors" do
      bmc_inventory = build(:bmc_inventory, :with_processors)
      expect(bmc_inventory.processors).to be_an(Array)
      expect(bmc_inventory.processors).not_to be_empty
      expect(bmc_inventory.processors.first).to include("model", "cores", "threads")
    end

    it "creates a bmc_inventory with memory" do
      bmc_inventory = build(:bmc_inventory, :with_memory)
      expect(bmc_inventory.memory).to be_an(Array)
      expect(bmc_inventory.memory).not_to be_empty
      expect(bmc_inventory.memory.first).to include("size_gb", "type", "speed_mhz")
    end

    it "creates a bmc_inventory via_redfish" do
      bmc_inventory = build(:bmc_inventory, :via_redfish)
      expect(bmc_inventory.collection_method).to eq("redfish")
    end

    it "creates a bmc_inventory via_ipmi" do
      bmc_inventory = build(:bmc_inventory, :via_ipmi)
      expect(bmc_inventory.collection_method).to eq("ipmi")
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let!(:old_inventory) { create(:bmc_inventory, node: node, captured_at: 2.days.ago) }
    let!(:recent_inventory) { create(:bmc_inventory, node: node, captured_at: 1.day.ago) }
    let!(:latest_inventory) { create(:bmc_inventory, node: node, captured_at: 1.hour.ago) }

    describe ".latest" do
      it "returns the most recent inventory per node" do
        result = described_class.latest
        expect(result).to include(latest_inventory)
        expect(result).not_to include(old_inventory, recent_inventory)
      end

      it "returns one record per node" do
        other_node = create(:node)
        other_latest = create(:bmc_inventory, node: other_node, captured_at: 30.minutes.ago)
        create(:bmc_inventory, node: other_node, captured_at: 2.hours.ago)

        result = described_class.latest
        expect(result.count).to eq(2)
        expect(result).to include(latest_inventory, other_latest)
      end
    end

    describe ".for_node" do
      let(:other_node) { create(:node) }
      let!(:other_inventory) { create(:bmc_inventory, node: other_node) }

      it "returns inventories for specified node only" do
        expect(described_class.for_node(node)).to match_array([ old_inventory, recent_inventory, latest_inventory ])
        expect(described_class.for_node(node)).not_to include(other_inventory)
      end

      it "accepts node id as parameter" do
        expect(described_class.for_node(node.id)).to match_array([ old_inventory, recent_inventory, latest_inventory ])
      end
    end
  end

  describe "JSONB columns" do
    let(:bmc_inventory) { create(:bmc_inventory) }

    it "accepts valid processors data" do
      processors = [
        { "model" => "Intel Xeon Gold 6248", "cores" => 20, "threads" => 40 },
        { "model" => "Intel Xeon Gold 6248", "cores" => 20, "threads" => 40 }
      ]
      bmc_inventory.update!(processors: processors)
      expect(bmc_inventory.reload.processors).to eq(processors)
    end

    it "accepts valid memory data" do
      memory = [
        { "size_gb" => 32, "type" => "DDR4", "speed_mhz" => 3200, "slot" => "DIMM_A1" },
        { "size_gb" => 32, "type" => "DDR4", "speed_mhz" => 3200, "slot" => "DIMM_A2" }
      ]
      bmc_inventory.update!(memory: memory)
      expect(bmc_inventory.reload.memory).to eq(memory)
    end

    it "accepts valid storage data" do
      storage = [
        { "name" => "Disk 0", "capacity_gb" => 480, "type" => "SSD", "manufacturer" => "Samsung" }
      ]
      bmc_inventory.update!(storage: storage)
      expect(bmc_inventory.reload.storage).to eq(storage)
    end

    it "accepts valid network data" do
      network = [
        { "id" => "NIC.Slot.1-1", "mac" => "00:11:22:33:44:55", "speed_gbps" => 25 }
      ]
      bmc_inventory.update!(network: network)
      expect(bmc_inventory.reload.network).to eq(network)
    end

    it "accepts valid infiniband data" do
      infiniband = [
        { "guid" => "0x0011223344556677", "port_state" => "Active", "link_speed" => "HDR" }
      ]
      bmc_inventory.update!(infiniband: infiniband)
      expect(bmc_inventory.reload.infiniband).to eq(infiniband)
    end

    it "accepts valid bios data" do
      bios = { "vendor" => "AMI", "version" => "2.5.1", "release_date" => "2024-01-15" }
      bmc_inventory.update!(bios: bios)
      expect(bmc_inventory.reload.bios).to eq(bios)
    end

    it "accepts valid bmc_info data" do
      bmc_info = {
        "firmware_version" => "2.10.0",
        "ip_address" => "10.0.1.100",
        "mac_address" => "AA:BB:CC:DD:EE:FF"
      }
      bmc_inventory.update!(bmc_info: bmc_info)
      expect(bmc_inventory.reload.bmc_info).to eq(bmc_info)
    end
  end

  describe "Node#bmc_inventories association" do
    let(:node) { create(:node) }

    it "allows node to have multiple bmc_inventories" do
      create_list(:bmc_inventory, 3, node: node)
      expect(node.bmc_inventories.count).to eq(3)
    end

    it "destroys inventories when node is destroyed" do
      create(:bmc_inventory, node: node)
      expect { node.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
