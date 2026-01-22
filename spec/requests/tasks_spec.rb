# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks", type: :request do
  let(:user) { create(:user) }
  let(:node) { create(:node) }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:profiling_recipe) { create(:profiling_recipe) }

  before { sign_in user }

  describe "GET /tasks" do
    let!(:benchmark_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }
    let!(:profiling_run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe) }

    it "returns http success" do
      get tasks_path
      expect(response).to have_http_status(:success)
    end

    it "displays both benchmark and profiling runs" do
      get tasks_path
      expect(response.body).to include(node.hostname)
      expect(response.body).to include(benchmark_recipe.name)
      expect(response.body).to include(profiling_recipe.name)
    end

    context "with type filter" do
      it "filters benchmark only" do
        get tasks_path(type: "benchmark")
        expect(response.body).to include(benchmark_recipe.name)
        expect(response.body).not_to include(profiling_recipe.name)
      end

      it "filters profiling only" do
        get tasks_path(type: "profiling")
        expect(response.body).to include(profiling_recipe.name)
        expect(response.body).not_to include(benchmark_recipe.name)
      end
    end

    context "with status filter" do
      let!(:success_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :success) }

      it "filters by status" do
        get tasks_path(status: "success")
        expect(response).to have_http_status(:success)
      end
    end

    context "with pagination" do
      before do
        30.times { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }
      end

      it "paginates results" do
        get tasks_path
        expect(response.body).to include("Next")
      end

      it "accepts page parameter" do
        get tasks_path(page: 2)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST /tasks/:id/cancel" do
    context "with benchmark run" do
      let(:pending_run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :pending) }

      it "cancels the benchmark run" do
        post cancel_task_path("benchmark_#{pending_run.id}")
        expect(pending_run.reload.status).to eq("cancelled")
      end

      it "redirects to tasks path" do
        post cancel_task_path("benchmark_#{pending_run.id}")
        expect(response).to redirect_to(tasks_path)
      end
    end

    context "with profiling run" do
      let(:pending_run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe, status: :pending) }

      it "cancels the profiling run" do
        post cancel_task_path("profiling_#{pending_run.id}")
        expect(pending_run.reload.status).to eq("cancelled")
      end
    end
  end

  describe "DELETE /tasks/:id" do
    context "with benchmark run" do
      let!(:run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe) }

      it "deletes the benchmark run" do
        expect {
          delete task_path("benchmark_#{run.id}")
        }.to change(BenchmarkRun, :count).by(-1)
      end
    end

    context "with profiling run" do
      let!(:run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe) }

      it "deletes the profiling run" do
        expect {
          delete task_path("profiling_#{run.id}")
        }.to change(ProfilingRun, :count).by(-1)
      end
    end
  end

  describe "POST /tasks/:id/rerun" do
    context "with benchmark run" do
      let!(:run) { create(:benchmark_run, node: node, benchmark_recipe: benchmark_recipe, status: :success) }

      it "creates a new benchmark run" do
        expect {
          post rerun_task_path("benchmark_#{run.id}")
        }.to change(BenchmarkRun, :count).by(1)
      end

      it "redirects to tasks path" do
        post rerun_task_path("benchmark_#{run.id}")
        expect(response).to redirect_to(tasks_path)
      end
    end

    context "with profiling run" do
      let!(:run) { create(:profiling_run, node: node, profiling_recipe: profiling_recipe, status: :success) }

      it "creates a new profiling run" do
        expect {
          post rerun_task_path("profiling_#{run.id}")
        }.to change(ProfilingRun, :count).by(1)
      end
    end
  end
end
