# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes::BenchmarkRuns", type: :request do
  let(:user) { create(:user, :approver) }
  let(:node) { create(:node) }

  before do
    sign_in user
  end

  describe "GET /nodes/:node_id/benchmark_runs/new" do
    it "returns http success" do
      get new_node_benchmark_run_path(node)
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /nodes/:node_id/benchmark_runs" do
    let(:trigger_service) { instance_double(Benchmark::TriggerRunService) }

    before do
      allow(Benchmark::TriggerRunService).to receive(:new).with(an_instance_of(Node), log_path: anything).and_return(trigger_service)
    end

    context "with valid params" do
      it "triggers benchmark and redirects" do
        allow(trigger_service).to receive(:call).and_return(double(success?: true))

        post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "/tmp/test.log" } }

        expect(response).to redirect_to(benchmark_runs_path(node_id: node.id))
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params" do
      it "renders new on form validation error" do
        post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "invalid path" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when trigger fails" do
      it "renders new with alert" do
        allow(trigger_service).to receive(:call).and_return(double(success?: false, error: "SSH error"))

        post node_benchmark_runs_path(node), params: { benchmark_run_form: { log_path: "/tmp/test.log" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include("SSH error")
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
