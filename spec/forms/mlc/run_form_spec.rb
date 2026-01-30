# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::RunForm do
  let(:node) { create(:node) }

  describe "validations" do
    it "is valid with required attributes" do
      form = described_class.new(node_id: node.id, profile: "quick")
      expect(form).to be_valid
    end

    it "is invalid without node_id" do
      form = described_class.new(node_id: nil, profile: "quick")
      expect(form).not_to be_valid
      expect(form.errors[:node_id]).to include("can't be blank")
    end

    it "is invalid without profile" do
      form = described_class.new(node_id: node.id, profile: nil)
      expect(form).not_to be_valid
      expect(form.errors[:profile]).to include("can't be blank")
    end

    it "is invalid with unknown profile" do
      form = described_class.new(node_id: node.id, profile: "unknown")
      expect(form).not_to be_valid
      expect(form.errors[:profile]).to include("is not a valid profile")
    end

    it "is invalid with non-existent node" do
      form = described_class.new(node_id: 999_999, profile: "quick")
      expect(form).not_to be_valid
      expect(form.errors[:node_id]).to include("node not found")
    end
  end

  describe "#node" do
    it "returns the associated node" do
      form = described_class.new(node_id: node.id, profile: "quick")
      expect(form.node).to eq(node)
    end
  end

  describe "#argument_overrides_hash" do
    it "returns hash with profile" do
      form = described_class.new(node_id: node.id, profile: "standard")
      expect(form.argument_overrides_hash).to include("profile" => "standard")
    end

    it "includes binary_path when provided" do
      form = described_class.new(node_id: node.id, profile: "quick", binary_path: "/opt/mlc")
      expect(form.argument_overrides_hash).to include("binary_path" => "/opt/mlc")
    end

    it "includes modules when provided" do
      form = described_class.new(node_id: node.id, profile: "quick", modules: "intel-mlc/3.12, gcc")
      expect(form.argument_overrides_hash["modules"]).to eq([ "intel-mlc/3.12", "gcc" ])
    end
  end
end
