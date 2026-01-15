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
    let(:api_key) { create(:api_key) }
    let(:valid_payload) do
      {
        run_id: run.uuid,
        status: "PASS",
        metrics: { gflops: 123.45 },
        start_time: Time.current.iso8601,
        end_time: (Time.current + 1.hour).iso8601
      }
    end

    it "authenticates using a database-backed API Key" do
      post "/api/v1/benchmark_runs",
           params: valid_payload.to_json,
           headers: { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      expect(api_key.reload.last_used_at).to be_present
    end

    it "denies access with a revoked API Key" do
      api_key.revoked!
      post "/api/v1/benchmark_runs",
           params: valid_payload.to_json,
           headers: { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
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

    it "associates the run with an existing node when X-Node-ID matches (UUID sync)" do
      # Simulate a node with a synced agent UUID
      synced_node = create(:node, hostname: "synced-node", uuid: "synced-agent-uuid")

      post "/api/v1/benchmark_runs",
           params: valid_payload.to_json,
           headers: {
             "Authorization" => "Bearer #{valid_token}",
             "Content-Type" => "application/json",
             "X-Node-ID" => "synced-agent-uuid"
           }

      expect(response).to have_http_status(:success)
      run.reload
      expect(run.node).to eq(synced_node)
      expect(run.node.hostname).to eq("synced-node")
    end

    it "keeps the original node when X-Node-ID does not match any existing node" do
      original_node = run.node
      unknown_uuid = SecureRandom.uuid

      post "/api/v1/benchmark_runs",
           params: valid_payload.to_json,
           headers: {
             "Authorization" => "Bearer #{valid_token}",
             "Content-Type" => "application/json",
             "X-Node-ID" => unknown_uuid
           }

      expect(response).to have_http_status(:success)
      run.reload
      # Run should keep its original node, not create a new one
      expect(run.node).to eq(original_node)
      expect(Node.find_by(uuid: unknown_uuid)).to be_nil
    end

    it "creates artifact index records if artifacts are provided" do
      payload = valid_payload.merge(artifacts: [ "/path/to/hpcg.log", "/path/to/hpcg.dat" ])
      post "/api/v1/benchmark_runs",
           params: payload.to_json,
           headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      expect(run.artifact_indices.count).to eq(2)
      expect(run.artifact_indices.pluck(:path)).to contain_exactly("/path/to/hpcg.log", "/path/to/hpcg.dat")
      expect(run.artifact_indices.find_by(path: "/path/to/hpcg.log").file_type).to eq("log")
    end

    it "saves log_content when provided" do
      log_content = "=== Command Output ===\nHPCG benchmark started\n\n=== HPCG Log File ===\nFinal GFLOPS: 123.45"
      payload = valid_payload.merge(log_content: log_content)
      post "/api/v1/benchmark_runs",
           params: payload.to_json,
           headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:success)
      expect(run.reload.log_content).to eq(log_content)
    end
  end
end
