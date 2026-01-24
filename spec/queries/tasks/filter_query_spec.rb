# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::FilterQuery do
  let(:node1) { create(:node, hostname: "node-01") }
  let(:node2) { create(:node, hostname: "node-02") }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  let!(:benchmark_run1) { create(:benchmark_run, node: node1, benchmark_recipe: benchmark_recipe, status: :success, created_at: 1.hour.ago) }
  let!(:benchmark_run2) { create(:benchmark_run, node: node2, benchmark_recipe: benchmark_recipe, status: :failed, created_at: 2.hours.ago) }
  let!(:profiling_run1) { create(:profiling_run, node: node1, profiling_recipe: profiling_recipe, status: :running, created_at: 30.minutes.ago) }
  let!(:profiling_run2) { create(:profiling_run, node: node2, profiling_recipe: profiling_recipe, status: :pending, created_at: 3.hours.ago) }

  describe "#call" do
    it "returns all tasks sorted by created_at desc" do
      tasks = described_class.new.call
      expect(tasks.map(&:uuid)).to eq([ profiling_run1, benchmark_run1, benchmark_run2, profiling_run2 ].map(&:uuid))
    end

    it "wraps results in Task objects" do
      tasks = described_class.new.call
      expect(tasks).to all(be_a(Task))
    end
  end

  describe "filtering by type" do
    it "filters benchmark only" do
      tasks = described_class.new(type: "benchmark").call
      expect(tasks.map(&:type)).to all(eq(:benchmark))
      expect(tasks.size).to eq(2)
    end

    it "filters profiling only" do
      tasks = described_class.new(type: "profiling").call
      expect(tasks.map(&:type)).to all(eq(:profiling))
      expect(tasks.size).to eq(2)
    end
  end

  describe "filtering by status" do
    it "filters by success status" do
      tasks = described_class.new(status: "success").call
      expect(tasks.map(&:status)).to all(eq("success"))
    end

    it "filters by running status" do
      tasks = described_class.new(status: "running").call
      expect(tasks.map(&:status)).to all(eq("running"))
    end
  end

  describe "filtering by node" do
    it "filters by node_id" do
      tasks = described_class.new(node_id: node1.id).call
      expect(tasks.map { |t| t.node.id }).to all(eq(node1.id))
      expect(tasks.size).to eq(2)
    end
  end

  describe "filtering by recipe" do
    it "filters by benchmark recipe" do
      tasks = described_class.new(recipe_id: "benchmark_#{benchmark_recipe.id}").call
      expect(tasks).to all(be_benchmark)
    end

    it "filters by profiling recipe" do
      tasks = described_class.new(recipe_id: "profiling_#{profiling_recipe.id}").call
      expect(tasks).to all(be_profiling)
    end
  end

  describe "search" do
    it "searches by node hostname" do
      tasks = described_class.new(q: "node-01").call
      expect(tasks.map { |t| t.node.hostname }).to all(eq("node-01"))
    end

    it "searches by recipe name" do
      tasks = described_class.new(q: benchmark_recipe.name).call
      expect(tasks).to all(be_benchmark)
    end

    it "searches by uuid" do
      tasks = described_class.new(q: benchmark_run1.uuid[0..8]).call
      expect(tasks.map(&:uuid)).to include(benchmark_run1.uuid)
    end
  end

  describe "date range filtering" do
    it "filters by last hour" do
      tasks = described_class.new(date_range: "last_hour").call
      expect(tasks.map(&:uuid)).to contain_exactly(profiling_run1.uuid)
    end

    it "filters by last 24 hours" do
      tasks = described_class.new(date_range: "last_24h").call
      expect(tasks.size).to eq(4)
    end
  end

  describe "combined filters" do
    it "applies multiple filters" do
      tasks = described_class.new(type: "benchmark", status: "success").call
      expect(tasks.size).to eq(1)
      expect(tasks.first.uuid).to eq(benchmark_run1.uuid)
    end
  end

  describe "#filtered?" do
    it "returns false when no filters" do
      expect(described_class.new.filtered?).to be false
    end

    it "returns true when type filter" do
      expect(described_class.new(type: "benchmark").filtered?).to be true
    end

    it "returns true when search query" do
      expect(described_class.new(q: "test").filtered?).to be true
    end
  end

  describe "#total_count" do
    it "returns count before pagination" do
      query = described_class.new
      expect(query.total_count).to eq(4)
    end
  end
end
