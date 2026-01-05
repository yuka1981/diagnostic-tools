# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BenchmarkRuns", type: :request do
  let(:user) { create(:user) }
  let(:node) { create(:node) }
  let(:recipe) { create(:benchmark_recipe) }
  let!(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe, status: :pending) }
  let(:valid_token) { "test-token" } # BaseController uses Bearer token

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:api, :agent_token).and_return(valid_token)
  end

  describe "POST /api/v1/benchmark_runs" do
    let(:valid_payload) do
      {
        run_id: run.uuid,
        status: "PASS",
        metrics: { gflops: 123.45 },
        start_time: Time.current.iso8601,
        end_time: (Time.current + 1.hour).iso8601
      }
    end

    it "updates the benchmark run status and metrics" do
      post "/api/v1/benchmark_runs",
           params: valid_payload.to_json,
           headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      run.reload
      expect(run.status).to eq("success")
      expect(run.metrics["gflops"]).to eq(123.45)
    end

    it "handles RUNNING status updates" do
      post "/api/v1/benchmark_runs",
           params: valid_payload.merge(status: "RUNNING").to_json,
           headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      expect(run.reload.status).to eq("running")
    end

    it "returns 404 for unknown run_id" do
      post "/api/v1/benchmark_runs",
           params: valid_payload.merge(run_id: SecureRandom.uuid).to_json,
           headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
