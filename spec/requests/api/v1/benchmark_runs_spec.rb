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

    describe "artifact_uploads" do
      let(:storage_dir) { Rails.root.join("tmp", "test_artifacts", run.uuid) }
      let(:file_content) { "Test file content\nLine 2\nLine 3" }
      let(:encoded_content) { Base64.strict_encode64(file_content) }

      before do
        allow(Rails.configuration.x).to receive(:artifacts_storage_path).and_return(Rails.root.join("tmp", "test_artifacts").to_s)
      end

      after do
        FileUtils.rm_rf(Rails.root.join("tmp", "test_artifacts"))
      end

      it "stores uploaded artifacts and creates artifact_index records with stored_path" do
        payload = valid_payload.merge(
          artifact_uploads: [
            {
              filename: "hpcg.log",
              content: encoded_content,
              file_type: "log",
              size: file_content.bytesize
            }
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)

        artifact = run.artifact_indices.find_by(file_type: "log")
        expect(artifact).to be_present
        expect(artifact.stored_path).to be_present
        expect(File.exist?(artifact.stored_path)).to be true
        expect(File.read(artifact.stored_path)).to eq(file_content)
      end

      it "handles multiple artifact uploads" do
        payload = valid_payload.merge(
          artifact_uploads: [
            {
              filename: "output.log",
              content: Base64.strict_encode64("Log content"),
              file_type: "log",
              size: 11
            },
            {
              filename: "results.json",
              content: Base64.strict_encode64('{"gflops": 123.45}'),
              file_type: "json",
              size: 18
            }
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)
        expect(run.artifact_indices.count).to eq(2)
        expect(run.artifact_indices.pluck(:file_type)).to contain_exactly("log", "json")
      end

      it "sanitizes filenames to prevent directory traversal" do
        payload = valid_payload.merge(
          artifact_uploads: [
            {
              filename: "../../../etc/passwd",
              content: encoded_content,
              file_type: "txt",
              size: file_content.bytesize
            }
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)

        artifact = run.artifact_indices.first
        expect(artifact.stored_path).not_to include("..")
        expect(File.basename(artifact.stored_path)).to eq("passwd")
      end

      it "skips uploads with blank filename or content" do
        payload = valid_payload.merge(
          artifact_uploads: [
            { filename: "", content: encoded_content, file_type: "log", size: 10 },
            { filename: "test.log", content: "", file_type: "log", size: 10 }
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)
        expect(run.artifact_indices.count).to eq(0)
      end

      it "skips legacy artifact processing for files already uploaded via artifact_uploads" do
        # Simulate agent sending both artifact_uploads and artifacts for the same file
        payload = valid_payload.merge(
          artifact_uploads: [
            {
              filename: "HPCG-Benchmark_test.txt",
              content: encoded_content,
              file_type: "txt",
              size: file_content.bytesize
            }
          ],
          artifacts: [
            "/tmp/hpc-diagnostics-log/HPCG-Benchmark_test.txt"
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)
        # Should only have 1 artifact record, not 2
        expect(run.artifact_indices.count).to eq(1)
        # The record should have stored_path set (from artifact_uploads)
        artifact = run.artifact_indices.first
        expect(artifact.stored_path).to be_present
        expect(File.exist?(artifact.stored_path)).to be true
      end

      it "still processes legacy artifacts for files not in artifact_uploads" do
        payload = valid_payload.merge(
          artifact_uploads: [
            {
              filename: "uploaded.txt",
              content: encoded_content,
              file_type: "txt",
              size: file_content.bytesize
            }
          ],
          artifacts: [
            "/tmp/different_file.log"
          ]
        )

        post "/api/v1/benchmark_runs",
             params: payload.to_json,
             headers: { "Authorization" => "Bearer #{valid_token}", "Content-Type" => "application/json" }

        expect(response).to have_http_status(:success)
        # Should have 2 artifact records - one uploaded, one legacy
        expect(run.artifact_indices.count).to eq(2)
        expect(run.artifact_indices.pluck(:file_type)).to contain_exactly("txt", "log")
      end
    end
  end
end
