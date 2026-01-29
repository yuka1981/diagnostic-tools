require "rails_helper"

RSpec.describe Benchmark::SaltTriggerRunService do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, name: "mlc", slug: "mlc", command: "mlc") }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }
  let(:salt_client) { instance_double(SaltApiClient) }
  let(:service) do
    described_class.new(
      node,
      benchmark_run: run,
      salt_client: salt_client
    )
  end

  describe "#call" do
    it "triggers an async Salt state.apply job" do
      expect(salt_client).to receive(:run_async)
        .with(
          "node-01",
          "state.apply",
          mods: "benchmark.mlc",
          pillar: hash_including(run_id: run.uuid)
        )
        .and_return("20260129120000123456")

      result = service.call
      expect(result.success?).to be true
      expect(result.jid).to eq("20260129120000123456")
    end

    it "updates the benchmark run to running status" do
      allow(salt_client).to receive(:run_async).and_return("20260129120000123456")

      service.call
      run.reload
      expect(run.status).to eq("running")
      expect(run.started_at).to be_present
    end

    it "handles TargetUnreachable errors" do
      allow(salt_client).to receive(:run_async)
        .and_raise(SaltApiClient::TargetUnreachable, "Minion not responding")

      result = service.call
      expect(result.success?).to be false
      run.reload
      expect(run.status).to eq("failed")
      expect(run.error_message).to include("not responding")
    end

    it "handles TimeoutError" do
      allow(salt_client).to receive(:run_async)
        .and_raise(SaltApiClient::TimeoutError, "Request timed out")

      result = service.call
      expect(result.success?).to be false
    end
  end
end
