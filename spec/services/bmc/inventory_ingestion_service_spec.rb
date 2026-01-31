# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bmc::InventoryIngestionService do
  include ActiveSupport::Testing::TimeHelpers

  let(:node) { create(:node) }

  let(:event_data) do
    {
      "results" => [
        {
          "node_id" => node.id,
          "node_hostname" => node.hostname,
          "protocol" => "redfish",
          "collected_at" => "2026-01-30T10:00:00Z",
          "inventory" => {
            "processors" => [ { "socket" => "CPU1", "model" => "Xeon", "cores_physical" => 32 } ],
            "memory" => [ { "slot" => "DIMM_A1", "size_gb" => 64, "speed_mhz" => 3200 } ],
            "storage" => [],
            "network" => [],
            "infiniband" => [],
            "bios" => { "vendor" => "AMI", "version" => "1.2.3" },
            "bmc_info" => { "model" => "iDRAC9", "firmware" => "6.10.00.00" }
          }
        }
      ],
      "errors" => []
    }
  end

  describe "#call" do
    before do
      # Stub ReconciliationService since it's tested separately
      allow(Bmc::ReconciliationService).to receive(:new).and_return(
        instance_double(Bmc::ReconciliationService, call: { compared: true })
      )
    end

    it "creates a BmcInventory record" do
      expect { described_class.new(event_data).call }
        .to change(BmcInventory, :count).by(1)
    end

    it "stores processor data" do
      described_class.new(event_data).call
      inv = BmcInventory.last
      expect(inv.processors.first["model"]).to eq("Xeon")
      expect(inv.collection_method).to eq("redfish")
    end

    it "triggers reconciliation" do
      expect(Bmc::ReconciliationService).to receive(:new).with(node)
      described_class.new(event_data).call
    end

    context "when collected_at is nil" do
      before { event_data["results"][0]["collected_at"] = nil }

      it "falls back to Time.current and still creates inventory" do
        travel_to(Time.zone.local(2026, 1, 30, 12, 0, 0)) do
          expect { described_class.new(event_data).call }
            .to change(BmcInventory, :count).by(1)
          expect(BmcInventory.last.captured_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "when collected_at is malformed" do
      before { event_data["results"][0]["collected_at"] = "garbage-timestamp" }

      it "falls back to Time.current and still creates inventory" do
        travel_to(Time.zone.local(2026, 1, 30, 12, 0, 0)) do
          expect { described_class.new(event_data).call }
            .to change(BmcInventory, :count).by(1)
          expect(BmcInventory.last.captured_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end
end
