# frozen_string_literal: true

require "rails_helper"

RSpec.describe Task do
  let(:node) { create(:node) }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  describe ".wrap" do
    it "wraps a BenchmarkRun" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      task = Task.wrap(run)

      expect(task.type).to eq(:benchmark)
      expect(task.id).to eq(run.id)
      expect(task.uuid).to eq(run.uuid)
    end

    it "wraps a ProfilingRun" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      task = Task.wrap(run)

      expect(task.type).to eq(:profiling)
      expect(task.id).to eq(run.id)
      expect(task.uuid).to eq(run.uuid)
    end
  end

  describe "#type" do
    it "returns :benchmark for BenchmarkRun" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).type).to eq(:benchmark)
    end

    it "returns :profiling for ProfilingRun" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).type).to eq(:profiling)
    end
  end

  describe "#recipe_name" do
    it "returns benchmark recipe name" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).recipe_name).to eq(benchmark_recipe.name)
    end

    it "returns profiling recipe name" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).recipe_name).to eq(profiling_recipe.name)
    end

    it "returns subcommand when profiling recipe is nil" do
      run = create(:profiling_run, node: node, profiling_recipe: nil, subcommand: "report")
      expect(Task.wrap(run).recipe_name).to eq("report")
    end
  end

  describe "#artifacts" do
    it "returns artifact_indices for benchmark" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      artifact = create(:artifact_index, benchmark_run: run)

      expect(Task.wrap(run).artifacts).to include(artifact)
    end

    it "returns profiling_artifacts for profiling" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      artifact = create(:profiling_artifact, profiling_run: run)

      expect(Task.wrap(run).artifacts).to include(artifact)
    end
  end

  describe "#dom_id" do
    it "returns unique dom id for benchmark" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).dom_id).to eq("task_benchmark_#{run.id}")
    end

    it "returns unique dom id for profiling" do
      run = create(:profiling_run, node: node, profiling_recipe: profiling_recipe)
      expect(Task.wrap(run).dom_id).to eq("task_profiling_#{run.id}")
    end
  end

  describe "delegated methods" do
    it "delegates status to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :running)
      expect(Task.wrap(run).status).to eq("running")
    end

    it "delegates node to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe)
      expect(Task.wrap(run).node).to eq(node)
    end

    it "delegates duration to source" do
      run = create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe,
                   started_at: 1.hour.ago, finished_at: 30.minutes.ago)
      expect(Task.wrap(run).duration).to be_within(1).of(1800)
    end
  end
end
