# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::MetricsService do
  subject(:service) { described_class.new }

  describe "#call" do
    it "returns a result with all metrics" do
      result = service.call

      expect(result).to respond_to(:total_nodes)
      expect(result).to respond_to(:online_nodes)
      expect(result).to respond_to(:availability_percentage)
      expect(result).to respond_to(:success_rate_24h)
      expect(result).to respond_to(:total_runs_24h)
      expect(result).to respond_to(:successful_runs_24h)
      expect(result).to respond_to(:failed_runs_24h)
    end
  end

  describe "node availability metrics" do
    context "when there are no nodes" do
      it "returns zero for all node metrics" do
        result = service.call

        expect(result.total_nodes).to eq(0)
        expect(result.online_nodes).to eq(0)
        expect(result.availability_percentage).to eq(0.0)
      end
    end

    context "when there are nodes" do
      before do
        # Create 5 nodes: 3 online, 2 offline
        create_list(:node, 3, last_seen_at: 1.minute.ago)
        create_list(:node, 2, last_seen_at: 10.minutes.ago)
      end

      it "returns correct total nodes count" do
        result = service.call
        expect(result.total_nodes).to eq(5)
      end

      it "returns correct online nodes count" do
        result = service.call
        expect(result.online_nodes).to eq(3)
      end

      it "calculates availability percentage correctly" do
        result = service.call
        # 3/5 = 60%
        expect(result.availability_percentage).to eq(60.0)
      end
    end

    context "when all nodes are online" do
      before do
        create_list(:node, 4, last_seen_at: 1.minute.ago)
      end

      it "returns 100% availability" do
        result = service.call
        expect(result.availability_percentage).to eq(100.0)
      end
    end

    context "when all nodes are offline" do
      before do
        create_list(:node, 3, last_seen_at: 10.minutes.ago)
      end

      it "returns 0% availability" do
        result = service.call
        expect(result.availability_percentage).to eq(0.0)
      end
    end
  end

  describe "benchmark run metrics (24 hours)" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }

    context "when there are no runs" do
      it "returns zero for all run metrics" do
        result = service.call

        expect(result.total_runs_24h).to eq(0)
        expect(result.successful_runs_24h).to eq(0)
        expect(result.failed_runs_24h).to eq(0)
        expect(result.success_rate_24h).to eq(0.0)
      end
    end

    context "when there are completed runs in the last 24 hours" do
      before do
        # Create runs in last 24 hours
        create_list(:benchmark_run, 3, :success, node: node, benchmark_recipe: recipe, started_at: 2.hours.ago)
        create_list(:benchmark_run, 2, :failed, node: node, benchmark_recipe: recipe, started_at: 4.hours.ago)
        create(:benchmark_run, :cancelled, node: node, benchmark_recipe: recipe, started_at: 6.hours.ago)

        # Create runs outside 24 hours (should not be counted)
        create(:benchmark_run, :success, node: node, benchmark_recipe: recipe, started_at: 25.hours.ago)
      end

      it "returns correct total completed runs count" do
        result = service.call
        # 3 success + 2 failed + 1 cancelled = 6
        expect(result.total_runs_24h).to eq(6)
      end

      it "returns correct successful runs count" do
        result = service.call
        expect(result.successful_runs_24h).to eq(3)
      end

      it "returns correct failed runs count" do
        result = service.call
        expect(result.failed_runs_24h).to eq(2)
      end

      it "calculates success rate correctly" do
        result = service.call
        # 3/6 = 50%
        expect(result.success_rate_24h).to eq(50.0)
      end
    end

    context "when all runs are successful" do
      before do
        create_list(:benchmark_run, 5, :success, node: node, benchmark_recipe: recipe, started_at: 2.hours.ago)
      end

      it "returns 100% success rate" do
        result = service.call
        expect(result.success_rate_24h).to eq(100.0)
      end
    end

    context "when all runs failed" do
      before do
        create_list(:benchmark_run, 4, :failed, node: node, benchmark_recipe: recipe, started_at: 2.hours.ago)
      end

      it "returns 0% success rate" do
        result = service.call
        expect(result.success_rate_24h).to eq(0.0)
      end
    end

    context "when there are pending and running jobs" do
      before do
        # Pending and running jobs should not be included in success rate calculation
        create_list(:benchmark_run, 2, node: node, benchmark_recipe: recipe, started_at: 1.hour.ago) # pending
        create_list(:benchmark_run, 2, :running, node: node, benchmark_recipe: recipe, started_at: 30.minutes.ago)
        create_list(:benchmark_run, 3, :success, node: node, benchmark_recipe: recipe, started_at: 2.hours.ago)
      end

      it "only counts completed runs in success rate" do
        result = service.call

        expect(result.total_runs_24h).to eq(3) # Only completed runs
        expect(result.success_rate_24h).to eq(100.0) # 3/3 = 100%
      end
    end
  end

  describe "runs by status" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }

    before do
      create_list(:benchmark_run, 5, :success, node: node, benchmark_recipe: recipe, started_at: 2.hours.ago)
      create_list(:benchmark_run, 3, :failed, node: node, benchmark_recipe: recipe, started_at: 4.hours.ago)
      create_list(:benchmark_run, 2, :cancelled, node: node, benchmark_recipe: recipe, started_at: 6.hours.ago)
    end

    it "returns runs grouped by status" do
      result = service.call

      expect(result.runs_by_status).to be_a(Hash)
      expect(result.runs_by_status[:success]).to eq(5)
      expect(result.runs_by_status[:failed]).to eq(3)
      expect(result.runs_by_status[:cancelled]).to eq(2)
    end
  end

  describe "nodes by role" do
    before do
      create_list(:node, 10) # compute (default)
      create_list(:node, 2, :login)
      create_list(:node, 1, :admin)
    end

    it "returns nodes grouped by role" do
      result = service.call

      expect(result.nodes_by_role).to be_a(Hash)
      expect(result.nodes_by_role[:compute]).to eq(10)
      expect(result.nodes_by_role[:login]).to eq(2)
      expect(result.nodes_by_role[:admin]).to eq(1)
    end
  end

  describe "caching" do
    it "uses memoization for expensive calculations" do
      # First call
      result1 = service.call
      # Second call should return the same object (memoized)
      result2 = service.call

      expect(result1).to equal(result2)
    end

    it "allows refresh to bypass cache" do
      result1 = service.call
      result2 = service.call(refresh: true)

      expect(result1).not_to equal(result2)
    end
  end

  describe "time range customization" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }

    before do
      create_list(:benchmark_run, 2, :success, node: node, benchmark_recipe: recipe, started_at: 6.hours.ago)
      create_list(:benchmark_run, 3, :success, node: node, benchmark_recipe: recipe, started_at: 18.hours.ago)
      create_list(:benchmark_run, 4, :success, node: node, benchmark_recipe: recipe, started_at: 30.hours.ago)
    end

    it "allows custom time range for run metrics" do
      # Last 12 hours should only include first 2 runs
      service_12h = described_class.new(time_range: 12.hours)
      result = service_12h.call

      expect(result.total_runs_24h).to eq(2)
    end

    it "defaults to 24 hours" do
      result = service.call
      # 2 + 3 = 5 runs in last 24 hours
      expect(result.total_runs_24h).to eq(5)
    end
  end
end
