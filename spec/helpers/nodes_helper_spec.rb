# frozen_string_literal: true

require "rails_helper"

RSpec.describe NodesHelper, type: :helper do
  describe "#group_memory_topology" do
    it "returns empty hash for nil input" do
      expect(helper.group_memory_topology(nil)).to eq({})
    end

    it "returns empty hash for empty array" do
      expect(helper.group_memory_topology([])).to eq({})
    end

    it "groups by CPU socket" do
      devices = [
        { "bank_locator" => "CPU 0 Channel 0 DIMM 0", "size" => "8 GB" },
        { "bank_locator" => "CPU 0 Channel 1 DIMM 0", "size" => "8 GB" },
        { "bank_locator" => "CPU 1 Channel 0 DIMM 0", "size" => "8 GB" }
      ]

      result = helper.group_memory_topology(devices)

      expect(result.keys).to include("CPU0", "CPU1")
      expect(result["CPU0"].keys).to include("CHANNEL0", "CHANNEL1")
      expect(result["CPU1"].keys).to include("CHANNEL0")
    end

    it "groups by P socket notation" do
      devices = [
        { "bank_locator" => "P0 Channel A", "size" => "16 GB" },
        { "bank_locator" => "P1 Channel A", "size" => "16 GB" }
      ]

      result = helper.group_memory_topology(devices)

      expect(result.keys).to include("P0", "P1")
    end

    it "uses System as default socket" do
      devices = [
        { "bank_locator" => "DIMM 0", "size" => "8 GB" }
      ]

      result = helper.group_memory_topology(devices)

      expect(result.keys).to include("System")
    end

    it "uses Default as default channel" do
      devices = [
        { "bank_locator" => "CPU 0 DIMM 0", "size" => "8 GB" }
      ]

      result = helper.group_memory_topology(devices)

      expect(result["CPU0"]["Default"]).to be_an(Array)
    end
  end

  describe "#format_socket_name" do
    it "formats P0 to CPU 0" do
      expect(helper.format_socket_name("P0")).to eq("CPU 0")
    end

    it "formats P1 to CPU 1" do
      expect(helper.format_socket_name("P1")).to eq("CPU 1")
    end

    it "formats NODE0 to CPU 0" do
      expect(helper.format_socket_name("NODE0")).to eq("CPU 0")
    end

    it "leaves CPU0 names unchanged (does not match pattern)" do
      # The regex only matches P# or NODE#, not CPU#
      expect(helper.format_socket_name("CPU0")).to eq("CPU0")
    end

    it "leaves System unchanged" do
      expect(helper.format_socket_name("System")).to eq("System")
    end
  end

  describe "#memory_slot_status_classes" do
    it "returns dashed border for empty slots" do
      slot = { "size" => "No Module Installed" }
      result = helper.memory_slot_status_classes(slot)
      expect(result).to include("border-dashed")
      expect(result).to include("slate")
    end

    it "returns teal for installed and running at spec speed" do
      slot = { "size" => "8 GB", "speed" => "2400 MT/s", "configured_speed" => "2400 MT/s" }
      result = helper.memory_slot_status_classes(slot)
      expect(result).to include("teal")
    end

    it "returns amber for downgraded slots" do
      slot = { "size" => "8 GB", "speed" => "3200 MT/s", "configured_speed" => "2400 MT/s" }
      result = helper.memory_slot_status_classes(slot)
      expect(result).to include("amber")
    end

    it "handles nil speeds" do
      slot = { "size" => "8 GB" }
      result = helper.memory_slot_status_classes(slot)
      expect(result).to include("teal")
    end
  end

  describe "#memory_slot_downgraded?" do
    it "returns false for empty slots" do
      slot = { "size" => "No Module Installed" }
      expect(helper.memory_slot_downgraded?(slot)).to be false
    end

    it "returns false when running at spec speed" do
      slot = { "size" => "8 GB", "speed" => "2400 MT/s", "configured_speed" => "2400 MT/s" }
      expect(helper.memory_slot_downgraded?(slot)).to be false
    end

    it "returns true when running below spec speed" do
      slot = { "size" => "8 GB", "speed" => "3200 MT/s", "configured_speed" => "2400 MT/s" }
      expect(helper.memory_slot_downgraded?(slot)).to be true
    end

    it "returns false when speeds are not available" do
      slot = { "size" => "8 GB" }
      expect(helper.memory_slot_downgraded?(slot)).to be false
    end
  end

  describe "#net_interface_status_badge" do
    it "returns green badge for up status" do
      result = helper.net_interface_status_badge("up")
      expect(result).to include("green")
      expect(result).to include("Active")
    end

    it "returns green badge for active status" do
      result = helper.net_interface_status_badge("active")
      expect(result).to include("green")
      expect(result).to include("Active")
    end

    it "returns red badge for down status" do
      result = helper.net_interface_status_badge("down")
      expect(result).to include("red")
      expect(result).to include("Down")
    end

    it "returns slate badge for unknown status" do
      result = helper.net_interface_status_badge("unknown")
      expect(result).to include("slate")
      expect(result).to include("UNKNOWN")
    end

    it "handles symbol status" do
      result = helper.net_interface_status_badge(:up)
      expect(result).to include("green")
    end
  end
end
