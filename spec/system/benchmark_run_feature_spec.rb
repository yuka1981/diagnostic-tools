# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Run Feature", type: :system do
  let(:approver) { create(:user, :approver) }
  let(:node) { create(:node, source: :agent_push) }
  let!(:recipe) { create(:benchmark_recipe, :hpcg) }

  before do
    sign_in approver
    driven_by(:rack_test)

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

  it "allows an approver to run a benchmark with a custom log path" do
    visit node_path(node)

    # Expect the "Benchmark" button to be visible
    expect(page).to have_link("Benchmark")
    click_link "Benchmark"

    expect(page).to have_content("Run Benchmark")


    # Since we are using rack_test which doesn't support JS/Turbo frames perfectly for modals
    # we can visit the new page directly or stub the interaction.
    # But rack_test follows links. The link has data-turbo-frame="modal".
    # rack_test handles turbo-frame by following the link (it treats it as a normal link basically but returns the frame content if it was a real turbo request, here it might just load the page).
    # Let's visit the new path directly to simulate the modal opening or fallback.

    visit new_node_benchmark_run_path(node)

    expect(page).to have_content("Run Benchmark")
    expect(page).to have_field("Benchmark Recipe")
    expect(page).to have_field("Log File Path (Optional)")

    select recipe.display_name, from: "Benchmark Recipe"
    fill_in "Log File Path (Optional)", with: "/tmp/custom_hpcg.log"

    # We need to mock the service call to avoid actual SSH
    service = instance_double(Benchmark::TriggerRunService)
    allow(Benchmark::TriggerRunService).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return(double(success?: true))

    click_button "Start Benchmark"

    expect(page).to have_content("Benchmark triggered successfully")
    expect(page).to have_current_path(node_path(node))
  end
end
