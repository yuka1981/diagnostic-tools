# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenchmarkWatchdogJob, type: :job do
  let!(:stale_run) do
    create(:benchmark_run, :running, last_heartbeat_at: 10.minutes.ago, error_message: "Previous note")
  end
  let!(:fresh_run) { create(:benchmark_run, :running, last_heartbeat_at: 2.minutes.ago) }
  let!(:completed_run) { create(:benchmark_run, :success, last_heartbeat_at: 1.minute.ago) }

  it "marks stale active runs as lost and appends heartbeat note" do
    BenchmarkWatchdogJob.new.perform

    stale_run.reload
    expect(stale_run).to be_lost
    expect(stale_run.error_message).to include("Previous note")
    expect(stale_run.error_message).to include(BenchmarkWatchdogJob::LOST_MESSAGE)
    expect(stale_run.last_heartbeat_at).to be_within(1.second).of(Time.current)
  end

  it "ignores fresh or completed runs" do
    BenchmarkWatchdogJob.new.perform

    expect(fresh_run.reload).to be_running
    expect(completed_run.reload).to be_success
  end
end
