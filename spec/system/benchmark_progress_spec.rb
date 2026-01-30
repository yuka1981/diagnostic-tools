# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Progress", type: :system, js: true do
  include ActionView::RecordIdentifier
  let(:approver) { create(:user, :approver) }
  let(:node) { create(:node, hostname: "target-node", source: :agent_push) }
  let!(:recipe) { create(:benchmark_recipe, name: "HPCG", version: "3.1") }

  before do
    sign_in approver
  end

  it "shows progress updates when a benchmark is run" do
    # Visit node page
    visit node_path(node)

    # Should see the empty state initially
    expect(page).to have_text(/Recent Benchmark Runs/i)
    expect(page).to have_text("No benchmarks run yet.")

    click_link "Benchmark"

    # In the modal
    within "#modal" do
      select recipe.display_name, from: "Benchmark Recipe"
      fill_in "Log File Path (Optional)", with: "/tmp/hpcg.log"
      click_button "Start Benchmark"
    end

    # Should redirect to node show page
    expect(page).to have_current_path(node_path(node))
    expect(page).to have_content("Benchmark triggered successfully")

    # Get the created run
    run = BenchmarkRun.last

    # Should see the pending run in the Recent Benchmark Runs section
    within "##{dom_id(run)}" do
      expect(page).to have_content("Pending")
    end

    # Simulate agent reporting back "RUNNING" via DB update
    run.update!(status: :running, started_at: Time.current)

    # Wait for Turbo Stream update on node show page
    within "##{dom_id(run)}" do
      expect(page).to have_content("Running", wait: 10)
    end

    # Simulate agent reporting back "PASS" (Success)
    run.update!(status: :success, finished_at: Time.current)

    within "##{dom_id(run)}" do
      expect(page).to have_content("Success")
    end
  end
end
