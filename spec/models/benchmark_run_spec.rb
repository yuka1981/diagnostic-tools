# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkRun, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:node) }
    it { is_expected.to belong_to(:benchmark_recipe) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }

    it "can have a log path" do
      run = build(:benchmark_run, log_path: "/tmp/hpcg.log")
      expect(run.log_path).to eq("/tmp/hpcg.log")
    end
  end

  describe "enums" do
    describe "status" do
      it "defines progress-aware statuses" do
        expect(BenchmarkRun.statuses).to eq({
          "pending" => 0,
          "preparing" => 1,
          "building" => 2,
          "running" => 3,
          "uploading" => 4,
          "success" => 5,
          "failed" => 6,
          "lost" => 7
        })
      end

      it "defaults to pending" do
        run = BenchmarkRun.new
        expect(run.status).to eq("pending")
      end
    end
  end

  describe "factory" do
    it "creates a valid benchmark_run" do
      run = build(:benchmark_run)
      expect(run).to be_valid
    end

    it "creates a successful run with metrics" do
      run = build(:benchmark_run, :success)
      expect(run).to be_success
      expect(run.metrics).to include("gflops")
      expect(run.finished_at).to be_present
    end

    it "creates a failed run with error message" do
      run = build(:benchmark_run, :failed)
      expect(run).to be_failed
      expect(run.error_message).to be_present
    end

    it "creates a running run" do
      run = build(:benchmark_run, :running)
      expect(run).to be_running
      expect(run.started_at).to be_present
      expect(run.finished_at).to be_nil
    end
  end

  describe "scopes" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }
    let!(:pending_run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }
    let!(:running_run) { create(:benchmark_run, :running, node: node, benchmark_recipe: recipe) }
    let!(:building_run) { create(:benchmark_run, :building, node: node, benchmark_recipe: recipe) }
    let!(:success_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }
    let!(:failed_run) { create(:benchmark_run, :failed, node: node, benchmark_recipe: recipe) }
    let!(:lost_run) { create(:benchmark_run, :lost, node: node, benchmark_recipe: recipe) }

    describe ".recent" do
      it "orders by created_at descending" do
        runs = BenchmarkRun.recent.to_a
        expect(runs.first).to eq(lost_run)
        expect(runs.last).to eq(pending_run)
      end
    end

    describe ".completed" do
      it "returns success, failed, and lost runs" do
        expect(BenchmarkRun.completed).to contain_exactly(success_run, failed_run, lost_run)
      end
    end

    describe ".active" do
      it "returns runs in progress states" do
        expect(BenchmarkRun.active).to contain_exactly(running_run, building_run)
      end
    end

    describe ".successful" do
      it "returns only success runs" do
        expect(BenchmarkRun.successful).to contain_exactly(success_run)
      end
    end

    describe ".for_node" do
      let(:other_node) { create(:node) }
      let!(:other_run) { create(:benchmark_run, node: other_node, benchmark_recipe: recipe) }

      it "returns runs for the specified node" do
        expect(BenchmarkRun.for_node(node)).to contain_exactly(pending_run, running_run, building_run, success_run, failed_run, lost_run)
        expect(BenchmarkRun.for_node(node)).not_to include(other_run)
      end
    end

    describe ".in_last_24_hours" do
      let!(:old_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe, started_at: 2.days.ago) }

      it "returns runs started within the last 24 hours" do
        recent_runs = BenchmarkRun.in_last_24_hours
        expect(recent_runs).to include(building_run, running_run, success_run, failed_run, lost_run)
        expect(recent_runs).not_to include(old_run)
      end
    end
  end

  describe "#duration" do
    context "when run is completed" do
      it "returns the duration in seconds" do
        run = build(:benchmark_run,
          started_at: Time.current - 1.hour,
          finished_at: Time.current
        )
        expect(run.duration).to be_within(1).of(3600)
      end
    end

    context "when run is not completed" do
      it "returns nil" do
        run = build(:benchmark_run, :running)
        expect(run.duration).to be_nil
      end
    end
  end

  describe "#completed?" do
    it "returns true for success status" do
      run = build(:benchmark_run, status: :success)
      expect(run.completed?).to be true
    end

    it "returns true for failed status" do
      run = build(:benchmark_run, status: :failed)
      expect(run.completed?).to be true
    end

    it "returns true for lost status" do
      run = build(:benchmark_run, status: :lost)
      expect(run.completed?).to be true
    end

    it "returns false for pending status" do
      run = build(:benchmark_run, status: :pending)
      expect(run.completed?).to be false
    end

    it "returns false for running status" do
      run = build(:benchmark_run, status: :running)
      expect(run.completed?).to be false
    end

    it "returns false for building status" do
      run = build(:benchmark_run, status: :building)
      expect(run.completed?).to be false
    end
  end

  describe "Node#benchmark_runs association" do
    let(:node) { create(:node) }
    let(:recipe) { create(:benchmark_recipe) }

    it "allows node to have multiple benchmark runs" do
      create_list(:benchmark_run, 3, node: node, benchmark_recipe: recipe)
      expect(node.benchmark_runs.count).to eq(3)
    end
  end
end
