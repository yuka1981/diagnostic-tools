# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::BenchmarkRuns", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }

  before do
    sign_in user
  end

  describe "GET /nodes/:node_id/benchmark_runs" do
    it "returns http success" do
      get node_benchmark_runs_path(node)
      expect(response).to have_http_status(:success)
    end

    it "displays benchmark runs for the node" do
      recipe = create(:benchmark_recipe)
      create_list(:benchmark_run, 3, node: node, benchmark_recipe: recipe)

      get node_benchmark_runs_path(node)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(node.hostname)
    end

    it "is accessible to viewers (read-only)" do
      viewer = create(:user, :viewer)
      sign_in viewer

      get node_benchmark_runs_path(node)

      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /nodes/:node_id/benchmark_runs/new" do
    it "returns http success" do
      get new_node_benchmark_run_path(node)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /nodes/:node_id/benchmark_runs" do
    include ActiveJob::TestHelper
    let(:recipe) { create(:benchmark_recipe, :hpcg) }

    context "with valid params" do
      it "triggers benchmark job and redirects to node show" do
        expect {
          post node_benchmark_runs_path(node), params: {
            benchmark_run_form: { benchmark_recipe_id: recipe.id, log_path: "/tmp/test.log" }
          }
        }.to enqueue_job(Benchmark::TriggerJob)

        expect(response).to redirect_to(node_path(node))
        expect(flash[:notice]).to be_present
      end

      it "saves merged arguments snapshot to run record" do
        post node_benchmark_runs_path(node), params: {
          benchmark_run_form: {
            benchmark_recipe_id: recipe.id,
            argument_overrides: '{"nx": 256}'
          }
        }

        run = BenchmarkRun.last
        expect(run.arguments["nx"]).to eq(256) # Override
        expect(run.arguments["ny"]).to eq(104) # Default from recipe
      end
    end

    context "with invalid params" do
      it "renders new on form validation error for invalid log path" do
        post node_benchmark_runs_path(node), params: {
          benchmark_run_form: { benchmark_recipe_id: recipe.id, log_path: "invalid path" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "renders new on form validation error for missing recipe" do
        post node_benchmark_runs_path(node), params: {
          benchmark_run_form: { log_path: "/tmp/test.log" }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "renders new on form validation error for invalid JSON overrides" do
        post node_benchmark_runs_path(node), params: {
          benchmark_run_form: {
            benchmark_recipe_id: recipe.id,
            argument_overrides: "not valid json"
          }
        }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "authorization" do
    let(:viewer) { create(:user, :viewer) }

    before { sign_in viewer }

    it "denies access to new" do
      get new_node_benchmark_run_path(node)
      expect(response).to redirect_to(node_path(node))
      expect(flash[:alert]).to be_present
    end

    it "denies access to create" do
      post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "/tmp/test.log" } }
      expect(response).to redirect_to(node_path(node))
      expect(flash[:alert]).to be_present
    end
  end
end
