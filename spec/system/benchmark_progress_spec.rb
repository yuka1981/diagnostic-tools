# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Progress", type: :system, js: true do
  include ActionView::RecordIdentifier
  let(:approver) { create(:user, :approver) }
  let(:node) { create(:node, hostname: "target-node", source: :agent_push) }
  let!(:recipe) { create(:benchmark_recipe, name: "HPCG", version: "3.1") }

  before do
    sign_in approver
    # Mock SSH Execution to avoid actual network calls
    allow(Net::SSH).to receive(:start).and_yield(instance_double(Net::SSH::Connection::Session, exec!: "Benchmark started"))
  end

  it "shows progress updates when a benchmark is run" do
    visit node_path(node)

    # Initial state
    expect(page).to have_text("LATEST BENCHMARK")
    expect(page).to have_text("—")

    click_link "Run Benchmarking"

    # In the modal
    within "#modal" do
      fill_in "Log File Path (Optional)", with: "/tmp/hpcg.log"
      click_button "Start Benchmark"
    end

    # Should redirect to node show page
    expect(page).to have_current_path(node_path(node))
    expect(page).to have_content("Benchmark triggered successfully")

    # Should see the pending run in the Latest Benchmark section
    within "##{dom_id(node, :latest_benchmark)}" do
      expect(page).to have_content("Pending")
    end

    # Simulate agent reporting back "RUNNING" via DB update
    run = BenchmarkRun.last
    run.update!(status: :running, started_at: Time.current)

    # Wait for Turbo Stream update on node show page
    within "##{dom_id(node, :latest_benchmark)}" do
      expect(page).to have_content("Running")
    end

    # Simulate agent reporting back "PASS" (Success)
    run.update!(status: :success, finished_at: Time.current)

    within "##{dom_id(node, :latest_benchmark)}" do
      expect(page).to have_content("Success")
    end
  end
end
