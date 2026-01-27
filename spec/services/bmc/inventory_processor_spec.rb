# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::InventoryProcessor do
  include ActiveSupport::Testing::TimeHelpers

  describe ".call" do
    let(:node) { create(:node) }
    let(:inventory_data) do
      {
        processors: [ { socket: "CPU1", model: "Intel Xeon", cores: 16 } ],
        memory: [ { slot: "DIMM_A1", size_gb: 32, speed_mhz: 3200 } ],
        storage: [ { name: "Disk 0", capacity: "480GB", model: "Samsung SSD" } ],
        network: [ { name: "NIC1", mac: "00:11:22:33:44:55" } ],
        infiniband: [ { hca: "mlx5_0", port_state: "Active" } ],
        bios: { vendor: "AMI", version: "2.5.1" },
        bmc_info: { model: "iDRAC9", firmware: "2.10.0" }
      }
    end
    let(:collection_method) { "redfish" }

    subject(:result) do
      described_class.call(
        node_id: node.id,
        inventory_data: inventory_data,
        collection_method: collection_method
      )
    end

    context "when successful" do
      it "returns a success result" do
        expect(result.success?).to be true
      end

      it "creates a BmcInventory record" do
        expect { result }.to change(BmcInventory, :count).by(1)
      end

      it "returns the created inventory" do
        expect(result.inventory).to be_a(BmcInventory)
        expect(result.inventory).to be_persisted
      end

      it "stores processor data" do
        expect(result.inventory.processors).to eq(inventory_data[:processors].map(&:stringify_keys))
      end

      it "stores memory data" do
        expect(result.inventory.memory).to eq(inventory_data[:memory].map(&:stringify_keys))
      end

      it "stores storage data" do
        expect(result.inventory.storage).to eq(inventory_data[:storage].map(&:stringify_keys))
      end

      it "stores network data" do
        expect(result.inventory.network).to eq(inventory_data[:network].map(&:stringify_keys))
      end

      it "stores infiniband data" do
        expect(result.inventory.infiniband).to eq(inventory_data[:infiniband].map(&:stringify_keys))
      end

      it "stores bios data" do
        expect(result.inventory.bios).to eq(inventory_data[:bios].stringify_keys)
      end

      it "stores bmc_info data" do
        expect(result.inventory.bmc_info).to eq(inventory_data[:bmc_info].stringify_keys)
      end

      it "sets the collection_method" do
        expect(result.inventory.collection_method).to eq("redfish")
      end

      it "sets captured_at timestamp" do
        travel_to Time.zone.local(2024, 1, 15, 12, 0, 0) do
          inventory = described_class.call(
            node_id: node.id,
            inventory_data: inventory_data,
            collection_method: collection_method
          ).inventory
          expect(inventory.captured_at).to eq(Time.zone.local(2024, 1, 15, 12, 0, 0))
        end
      end

      it "associates inventory with the correct node" do
        expect(result.inventory.node).to eq(node)
      end
    end

    context "when node is not found" do
      subject(:result) do
        described_class.call(
          node_id: 999_999,
          inventory_data: inventory_data,
          collection_method: collection_method
        )
      end

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns an appropriate error message" do
        expect(result.error).to eq("Node not found")
      end

      it "does not create a BmcInventory record" do
        expect { result }.not_to change(BmcInventory, :count)
      end
    end

    context "when finding node by uuid" do
      subject(:result) do
        described_class.call(
          node_id: node.uuid,
          inventory_data: inventory_data,
          collection_method: collection_method
        )
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end

      it "creates a BmcInventory record for the correct node" do
        expect(result.inventory.node).to eq(node)
      end
    end

    context "when finding node by hostname" do
      subject(:result) do
        described_class.call(
          node_id: node.hostname,
          inventory_data: inventory_data,
          collection_method: collection_method
        )
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end

      it "creates a BmcInventory record for the correct node" do
        expect(result.inventory.node).to eq(node)
      end
    end

    context "when inventory_data is missing optional fields" do
      let(:inventory_data) do
        {
          processors: [ { socket: "CPU1", model: "Intel Xeon" } ],
          bios: { vendor: "AMI" }
        }
      end

      it "returns a success result" do
        expect(result.success?).to be true
      end

      it "sets missing arrays to empty arrays" do
        expect(result.inventory.memory).to eq([])
        expect(result.inventory.storage).to eq([])
        expect(result.inventory.network).to eq([])
        expect(result.inventory.infiniband).to eq([])
      end

      it "sets missing hashes to empty hashes" do
        expect(result.inventory.bmc_info).to eq({})
      end
    end

    context "when inventory_data is nil" do
      let(:inventory_data) { nil }

      it "returns a success result with empty inventory" do
        expect(result.success?).to be true
      end

      it "creates inventory with empty defaults" do
        expect(result.inventory.processors).to eq([])
        expect(result.inventory.memory).to eq([])
        expect(result.inventory.storage).to eq([])
        expect(result.inventory.network).to eq([])
        expect(result.inventory.infiniband).to eq([])
        expect(result.inventory.bios).to eq({})
        expect(result.inventory.bmc_info).to eq({})
      end
    end

    context "when collection_method is ipmi" do
      let(:collection_method) { "ipmi" }

      it "sets the collection_method to ipmi" do
        expect(result.inventory.collection_method).to eq("ipmi")
      end
    end

    context "when collection_method is invalid" do
      let(:collection_method) { "invalid_method" }

      it "returns a failure result" do
        expect(result.success?).to be false
      end

      it "returns validation error message" do
        expect(result.error).to include("Collection method")
      end
    end
  end
end
