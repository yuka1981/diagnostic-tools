require "rails_helper"

RSpec.describe MlcInstallationNode, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:mlc_installation) }
    it { is_expected.to belong_to(:node) }
  end

  describe "enums" do
    it do
      is_expected.to define_enum_for(:status)
        .with_values(pending: 0, running: 1, success: 2, failed: 3, skipped: 4, cancelled: 5)
        .with_default(:pending)
    end
  end

  describe "#completed?" do
    it "returns true for success status" do
      node = build(:mlc_installation_node, status: :success)
      expect(node.completed?).to be true
    end

    it "returns true for failed status" do
      node = build(:mlc_installation_node, status: :failed)
      expect(node.completed?).to be true
    end

    it "returns true for skipped status" do
      node = build(:mlc_installation_node, status: :skipped)
      expect(node.completed?).to be true
    end

    it "returns false for running status" do
      node = build(:mlc_installation_node, status: :running)
      expect(node.completed?).to be false
    end

    it "returns false for pending status" do
      node = build(:mlc_installation_node, status: :pending)
      expect(node.completed?).to be false
    end
  end

  describe "#duration" do
    it "returns nil when not started" do
      node = build(:mlc_installation_node, started_at: nil, completed_at: nil)
      expect(node.duration).to be_nil
    end

    it "returns nil when not completed" do
      node = build(:mlc_installation_node, started_at: Time.current, completed_at: nil)
      expect(node.duration).to be_nil
    end

    it "returns duration in seconds when completed" do
      node = build(:mlc_installation_node, started_at: 10.seconds.ago, completed_at: Time.current)
      expect(node.duration).to be_within(1).of(10)
    end
  end
end
