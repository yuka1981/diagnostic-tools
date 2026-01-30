# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MlcBenchmarks", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }
  let!(:mlc_recipe) { create(:benchmark_recipe, slug: "mlc", name: "Intel MLC", command: "mlc") }

  before { sign_in user }

  describe "GET /mlc_benchmarks/new" do
    it "returns http success" do
      get new_mlc_benchmark_path
      expect(response).to have_http_status(:success)
    end

    it "renders profile selector" do
      get new_mlc_benchmark_path
      expect(response.body).to include("Select Profile")
      expect(response.body).to include("Quick")
    end

    it "renders node selector" do
      get new_mlc_benchmark_path
      expect(response.body).to include("Target Node")
    end

    context "when user is not approver" do
      let(:user) { create(:user, :viewer) }

      it "redirects with unauthorized message" do
        get new_mlc_benchmark_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /mlc_benchmarks" do
    include ActiveJob::TestHelper

    let(:valid_params) do
      {
        mlc_run_form: {
          node_id: node.id,
          profile: "quick"
        }
      }
    end

    it "creates benchmark run and redirects" do
      expect {
        post mlc_benchmarks_path, params: valid_params
      }.to change(BenchmarkRun, :count).by(1)

      expect(response).to redirect_to(node_path(node))
    end

    it "enqueues trigger job" do
      expect {
        post mlc_benchmarks_path, params: valid_params
      }.to have_enqueued_job(Benchmark::TriggerJob)
    end

    it "sets profile in arguments" do
      post mlc_benchmarks_path, params: valid_params
      run = BenchmarkRun.last
      expect(run.arguments["profile"]).to eq("quick")
    end

    context "with invalid params" do
      it "re-renders form with errors" do
        post mlc_benchmarks_path, params: { mlc_run_form: { node_id: nil, profile: nil } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("can&#39;t be blank")
      end
    end
  end
end
