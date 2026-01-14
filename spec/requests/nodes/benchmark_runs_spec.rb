# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::BenchmarkRuns", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }

  before do
    sign_in user

    # Mock preflight service to return successful checks
    mock_preflight = instance_double(
      Benchmark::PreflightService::Result,
      success?: true,
      checks: [
        Benchmark::PreflightService::Check.new(name: "SSH Connectivity", passed: true, message: "Connected"),
        Benchmark::PreflightService::Check.new(name: "Working Directory", passed: true, message: "Exists"),
        Benchmark::PreflightService::Check.new(name: "HPCG Source", passed: true, message: "Ready"),
        Benchmark::PreflightService::Check.new(name: "Agent Binary", passed: true, message: "Found")
      ],
      failed_checks: [],
      config: {
        work_dir: "/tmp/hpcg",
        work_dir_source: :default,
        agent_path: "../hpc-agent",
        node_hostname: "test-node",
        server_url: nil,
        api_configured: false,
        token_source: :none
      }
    )
    allow_any_instance_of(Benchmark::PreflightService).to receive(:call).and_return(mock_preflight)
  end

  describe "GET /nodes/:node_id/benchmark_runs/new" do
    it "returns http success" do
      get new_node_benchmark_run_path(node)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /nodes/:node_id/benchmark_runs" do
    include ActiveJob::TestHelper

    context "with valid params" do
      it "triggers benchmark job and redirects to node show" do
        expect {
          post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "/tmp/test.log" } }
        }.to enqueue_job(Benchmark::TriggerJob)

        expect(response).to redirect_to(node_path(node))
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params" do
      it "renders new on form validation error" do
        post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "invalid path" } }
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
