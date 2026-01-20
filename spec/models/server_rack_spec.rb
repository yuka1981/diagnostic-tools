# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServerRack, type: :model do
  describe "validations" do
    subject { build(:server_rack) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:site_id) }
    it { is_expected.to validate_uniqueness_of(:facility_id).scoped_to(:site_id).allow_nil }

    it { is_expected.to validate_numericality_of(:u_height).only_integer.is_greater_than(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:width_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:depth_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_weight_kg).only_integer.is_greater_than(0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:site) }
    it { is_expected.to have_many(:nodes) }
  end

  describe "enums" do
    it "defines status enum" do
      expect(ServerRack.statuses).to eq({ "active" => 0, "planned" => 1, "decommissioned" => 2 })
    end

    it "defaults to active status" do
      server_rack = ServerRack.new
      expect(server_rack.status).to eq("active")
    end
  end

  describe "defaults" do
    it "defaults u_height to 42" do
      server_rack = ServerRack.new
      expect(server_rack.u_height).to eq(42)
    end

    it "defaults desc_units to false" do
      server_rack = ServerRack.new
      expect(server_rack.desc_units).to be false
    end
  end

  describe "factory" do
    it "creates a valid server_rack" do
      server_rack = build(:server_rack)
      expect(server_rack).to be_valid
    end

    it "creates a valid server_rack with planned trait" do
      server_rack = build(:server_rack, :planned)
      expect(server_rack).to be_valid
      expect(server_rack).to be_planned
    end

    it "creates a valid server_rack with decommissioned trait" do
      server_rack = build(:server_rack, :decommissioned)
      expect(server_rack).to be_valid
      expect(server_rack).to be_decommissioned
    end
  end

  describe "#utilization" do
    let(:site) { create(:site) }
    let(:server_rack) { create(:server_rack, site: site, u_height: 42) }

    context "with no nodes" do
      it "returns 0" do
        expect(server_rack.utilization).to eq(0)
      end
    end

    context "with nodes" do
      # Note: This test depends on Node having rack fields (Task 3)
      # Skip for now, will be enabled after Task 3
    end
  end

  describe "#utilization_percentage" do
    let(:site) { create(:site) }
    let(:server_rack) { create(:server_rack, site: site, u_height: 10) }

    context "with no nodes" do
      it "returns 0.0" do
        expect(server_rack.utilization_percentage).to eq(0.0)
      end
    end
  end
end
