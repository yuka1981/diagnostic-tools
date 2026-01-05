# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#format_bytes" do
    it "formats zero or nil" do
      expect(helper.format_bytes(0)).to eq("—")
      expect(helper.format_bytes(nil)).to eq("—")
    end

    it "formats bytes" do
      expect(helper.format_bytes(512)).to eq("512.00 B")
    end

    it "formats kilobytes" do
      expect(helper.format_bytes(1024)).to eq("1.00 KB")
    end

    it "formats megabytes" do
      expect(helper.format_bytes(1024 * 1024)).to eq("1.00 MB")
    end

    it "formats gigabytes" do
      expect(helper.format_bytes(1024 * 1024 * 1024)).to eq("1.00 GB")
    end

    it "formats terabytes" do
      expect(helper.format_bytes(1024 * 1024 * 1024 * 1024 * 1.5)).to eq("1.50 TB")
    end
  end

  describe "#format_megabits" do
    it "formats zero, negative or nil" do
      expect(helper.format_megabits(0)).to eq("—")
      expect(helper.format_megabits(-1)).to eq("—")
      expect(helper.format_megabits(nil)).to eq("—")
    end

    it "formats Mbps for speeds below 1000" do
      expect(helper.format_megabits(100)).to eq("100 Mbps")
      expect(helper.format_megabits(999)).to eq("999 Mbps")
    end

    it "formats Gbps for speeds 1000 and above" do
      expect(helper.format_megabits(1000)).to eq("1.0 Gbps")
      expect(helper.format_megabits(10000)).to eq("10.0 Gbps")
      expect(helper.format_megabits(100000)).to eq("100.0 Gbps")
      expect(helper.format_megabits(200000)).to eq("200.0 Gbps")
    end
  end
end
