# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerJob, type: :job do
  let(:node) { create(:node) }
  let(:recipe) { create(:benchmark_recipe) }
  let(:run) { create(:benchmark_run, :pending, node: node, benchmark_recipe: recipe) }
  let(:server_url) { "https://api.example.com" }
  let(:agent_token) { "secret_token_123" }

  describe "#perform" do
    let(:mock_result) { double(success?: true, output: "Command output", error: nil) }

    before do
      allow_any_instance_of(Benchmark::TriggerRunService).to receive(:call).and_return(mock_result)
    end

    context "when trigger service succeeds" do
      it "updates run status to running" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.status).to eq("running")
      end

      it "sets started_at timestamp" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.started_at).to be_present
        expect(run.started_at).to be_within(5.seconds).of(Time.current)
      end

      it "stores command output in log_content" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.log_content).to eq("Command output")
      end

      it "passes argument overrides to service" do
        overrides = { "nx" => 128, "ny" => 128 }

        expect(Benchmark::TriggerRunService).to receive(:new).with(
          node,
          hash_including(argument_overrides: overrides)
        ).and_return(double(call: mock_result))

        described_class.new.perform(node, run, server_url, agent_token, overrides)
      end
    end

    context "when trigger service fails" do
      let(:mock_result) { double(success?: false, output: "SSH output", error: "Connection refused") }

      it "updates run status to failed" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.status).to eq("failed")
      end

      it "stores error message" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.error_message).to eq("Connection refused")
      end

      it "stores output in log_content" do
        described_class.new.perform(node, run, server_url, agent_token)
        run.reload
        expect(run.log_content).to eq("SSH output")
      end
    end

    context "when run status has changed during SSH call" do
      let(:cancelled_run) { create(:benchmark_run, :cancelled, node: node, benchmark_recipe: recipe) }

      it "does not update status if run is no longer pending" do
        # The run is cancelled, so pending? returns false
        described_class.new.perform(node, cancelled_run, server_url, agent_token)
        cancelled_run.reload
        # Status should remain cancelled since job skips update for non-pending runs
        expect(cancelled_run.status).to eq("cancelled")
      end
    end

    context "when run was cancelled before job runs" do
      let(:cancelled_run) { create(:benchmark_run, :cancelled, node: node, benchmark_recipe: recipe) }

      it "does not change the cancelled run status" do
        described_class.new.perform(node, cancelled_run, server_url, agent_token)
        cancelled_run.reload
        expect(cancelled_run.status).to eq("cancelled")
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
