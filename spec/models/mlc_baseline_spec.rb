# frozen_string_literal: true

require "rails_helper"

RSpec.describe MlcBaseline, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:benchmark_run) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:metric_type) }
    it { is_expected.to validate_presence_of(:value) }

    describe "uniqueness of metric_type per node" do
      subject { create(:mlc_baseline) }

      it { is_expected.to validate_uniqueness_of(:metric_type).scoped_to(:node_id) }
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let(:other_node) { create(:node) }
    let!(:baseline1) { create(:mlc_baseline, node: node, metric_type: "idle_latency") }
    let!(:baseline2) { create(:mlc_baseline, node: node, metric_type: "peak_bandwidth") }
    let!(:baseline3) { create(:mlc_baseline, node: other_node, metric_type: "idle_latency") }

    describe ".for_node" do
      it "returns baselines for the specified node" do
        expect(described_class.for_node(node)).to contain_exactly(baseline1, baseline2)
      end
    end

    describe ".by_metric_type" do
      it "returns baselines with the specified metric type" do
        expect(described_class.by_metric_type("idle_latency")).to contain_exactly(baseline1, baseline3)
      end
    end

    describe ".latest" do
      it "orders by created_at descending" do
        expect(described_class.latest.to_a).to eq([ baseline3, baseline2, baseline1 ])
      end
    end
  end
end
