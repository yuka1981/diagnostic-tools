# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mlc::ThresholdEvaluator do
  let(:node) { create(:node) }
  let(:recipe) { create(:benchmark_recipe, slug: "mlc", default_profile: config) }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, metrics: metrics) }

  let(:metrics) do
    {
      "idle_latency_ns" => 78.2,
      "peak_bandwidth" => { "all_reads" => 298_450.0 },
      "numa_node_count" => 4
    }
  end

  describe "#evaluate" do
    context "with manual threshold mode" do
      let(:config) do
        {
          "threshold_mode" => "manual",
          "manual_thresholds" => {
            "idle_latency_ns" => { "max" => 90 },
            "peak_bandwidth.all_reads" => { "min" => 200_000 }
          }
        }
      end

      it "returns pass when all thresholds are met" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("pass")
        expect(result[:results]["idle_latency_ns"][:status]).to eq("pass")
      end

      it "returns fail when threshold is exceeded" do
        run.update!(metrics: { "idle_latency_ns" => 95.0 })
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("fail")
        expect(result[:results]["idle_latency_ns"][:status]).to eq("fail")
      end
    end

    context "with auto_baseline threshold mode" do
      let(:config) do
        {
          "threshold_mode" => "auto_baseline",
          "baseline_tolerance" => { "warning_percent" => 10, "fail_percent" => 20 }
        }
      end

      let!(:baseline) do
        create(:mlc_baseline, node: node, benchmark_run: run, metric_type: "idle_latency_ns", value: 78.0)
      end

      it "returns pass when within tolerance" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("pass")
      end

      it "returns warn when deviation exceeds warning threshold" do
        run.update!(metrics: { "idle_latency_ns" => 88.0 }) # +12.8%
        result = described_class.new(run, recipe).evaluate
        expect(result[:results]["idle_latency_ns"][:status]).to eq("warn")
      end

      it "returns fail when deviation exceeds fail threshold" do
        run.update!(metrics: { "idle_latency_ns" => 100.0 }) # +28.2%
        result = described_class.new(run, recipe).evaluate
        expect(result[:results]["idle_latency_ns"][:status]).to eq("fail")
      end
    end

    context "with no threshold mode configured" do
      let(:config) { {} }

      it "returns skipped status" do
        result = described_class.new(run, recipe).evaluate
        expect(result[:status]).to eq("skipped")
      end
    end
  end
end
