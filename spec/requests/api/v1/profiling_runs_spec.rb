# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ProfilingRuns", type: :request do
  let(:api_key) { create(:api_key) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}" } }
  let(:node) { create(:node) }
  let!(:run) { create(:profiling_run, node: node, status: :running) }

  describe "POST /api/v1/profiling_runs/:uuid/status" do
    it "updates run status" do
      post "/api/v1/profiling_runs/#{run.uuid}/status",
           params: { status: "running", message: "Executing perfspect" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.log_content).to include("Executing perfspect")
    end
  end

  describe "POST /api/v1/profiling_runs/:uuid/complete" do
    it "marks run as success with artifacts" do
      post "/api/v1/profiling_runs/#{run.uuid}/complete",
           params: {
             status: "success",
             metrics: { "cpu_model" => "Intel Xeon" },
             artifacts: [
               { filename: "report.html", file_path: "/shared/abc/report.html", file_type: "html" }
             ]
           },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.status).to eq("success")
      expect(run.metrics["cpu_model"]).to eq("Intel Xeon")
      expect(run.profiling_artifacts.count).to eq(1)
    end

    it "marks run as failed with error message" do
      post "/api/v1/profiling_runs/#{run.uuid}/complete",
           params: { status: "failed", error_message: "Module not found" },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:ok)
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to eq("Module not found")
    end
  end
end
