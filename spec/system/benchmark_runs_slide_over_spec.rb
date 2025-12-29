# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Runs Slide-over Inspector", type: :system do
  let(:user) { create(:user) }
  let(:node) { create(:node, hostname: "compute-001") }
  let(:recipe) { create(:benchmark_recipe, name: "HPL", version: "2.3.0") }

  before do
    sign_in user
  end

  describe "slide-over panel display" do
    let!(:benchmark_run) do
      create(:benchmark_run, :success,
        node: node,
        benchmark_recipe: recipe,
        started_at: 2.hours.ago,
        finished_at: 1.hour.ago,
        metrics: { "gflops" => 123.45, "efficiency" => 0.85 })
    end

    it "displays slide-over panel when clicking View button", :js do
      visit benchmark_runs_path

      # Click View button to open slide-over
      click_link "View", match: :first

      # Slide-over should appear
      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)
      expect(page).to have_content(recipe.name)
      expect(page).to have_content(node.hostname)
    end

    it "closes slide-over when clicking close button", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      # Wait for slide-over to open
      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Click close button
      find("[data-action='click->slide-over#close']").click

      # Slide-over should be hidden
      expect(page).to have_css("[data-slide-over-target='panel'].translate-x-full", visible: :hidden, wait: 5)
    end

    it "closes slide-over when clicking backdrop", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Click backdrop
      find("[data-slide-over-target='backdrop']").click

      expect(page).to have_css("[data-slide-over-target='panel'].translate-x-full", visible: :hidden, wait: 5)
    end

    it "closes slide-over when pressing Escape key", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Press Escape key
      find("body").send_keys(:escape)

      expect(page).to have_css("[data-slide-over-target='panel'].translate-x-full", visible: :hidden, wait: 5)
    end
  end

  describe "slide-over content tabs" do
    let!(:benchmark_run) do
      create(:benchmark_run, :success,
        node: node,
        benchmark_recipe: recipe,
        started_at: 2.hours.ago,
        finished_at: 1.hour.ago,
        metrics: { "gflops" => 123.45 },
        error_message: nil)
    end

    it "displays Summary tab by default", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Summary tab should be active
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: "Summary")
      expect(page).to have_content("Node")
      expect(page).to have_content(node.hostname)
    end

    it "switches to Metrics tab", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Click Metrics tab
      click_button "Metrics"

      # Metrics tab should be active
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: "Metrics")
      # Metrics keys are humanized (gflops -> Gflops)
      expect(page).to have_content("Gflops")
      expect(page).to have_content("123.45")
    end

    it "switches to Logs tab", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Click Logs tab
      click_button "Logs"

      # Logs tab should be active and show placeholder
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: "Logs")
      expect(page).to have_content("No logs available")
    end
  end

  describe "slide-over with error message" do
    let!(:failed_run) do
      create(:benchmark_run, :failed,
        node: node,
        benchmark_recipe: recipe,
        started_at: 2.hours.ago,
        finished_at: 1.hour.ago,
        error_message: "Segmentation fault (core dumped)")
    end

    it "displays error message in the slide-over", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Wait for Turbo Frame to load the content and show error
      within("[data-slide-over-target='panel']") do
        expect(page).to have_content("Run #", wait: 5)
        expect(page).to have_content("Segmentation fault (core dumped)")
      end
    end
  end

  describe "slide-over accessibility" do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node, benchmark_recipe: recipe) }

    it "has proper ARIA attributes", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      panel = find("[data-slide-over-target='panel']")
      expect(panel["role"]).to eq("dialog")
      expect(panel["aria-modal"]).to eq("true")
      expect(panel["aria-labelledby"]).to be_present
    end

    it "traps focus within slide-over when open", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Close button should be focusable
      close_button = find("[data-action='click->slide-over#close']")
      expect(close_button).to be_visible
    end
  end
end
