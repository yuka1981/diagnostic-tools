# frozen_string_literal: true

require "rails_helper"

RSpec.describe Benchmark::TriggerJob, type: :job do
  let(:node) { create(:node, hostname: "node-01") }
  let(:recipe) { create(:benchmark_recipe, benchmark_type: :hpcg) }
  let(:run) { create(:benchmark_run, node: node, benchmark_recipe: recipe) }

  it "delegates to Benchmark::SaltTriggerRunService" do
    service = instance_double(Benchmark::SaltTriggerRunService)
    allow(Benchmark::SaltTriggerRunService).to receive(:new)
      .with(node, benchmark_run: run, argument_overrides: {})
      .and_return(service)
    allow(service).to receive(:call).and_return(
      Benchmark::SaltTriggerRunService::Result.new(success: true, jid: "123")
    )

    described_class.perform_now(node, run)

    expect(service).to have_received(:call)
  end

  it "handles service failures" do
    service = instance_double(Benchmark::SaltTriggerRunService)
    allow(Benchmark::SaltTriggerRunService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(
      Benchmark::SaltTriggerRunService::Result.new(success: false, error: "Minion offline")
    )

    described_class.perform_now(node, run)
    # Service already updates run status, so we just verify no exception
  end
end
