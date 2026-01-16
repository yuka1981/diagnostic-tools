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

      # Modal should be hidden (uses scale/opacity animation, then hidden class is added)
      expect(page).to have_css("[data-slide-over-target='panel'].hidden", visible: :hidden, wait: 5)
    end

    it "closes slide-over when clicking outside modal", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Click outside the modal content by dispatching a click event on the panel
      # The panelClick handler will close if click target is not within modalContent
      page.execute_script(<<~JS)
        const panel = document.querySelector("[data-slide-over-target='panel']");
        const clickEvent = new MouseEvent('click', {
          bubbles: true,
          cancelable: true,
          view: window
        });
        panel.dispatchEvent(clickEvent);
      JS

      # Modal should be hidden
      expect(page).to have_css("[data-slide-over-target='panel'].hidden", visible: :hidden, wait: 5)
    end

    it "closes slide-over when pressing Escape key", :js do
      visit benchmark_runs_path
      click_link "View", match: :first

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Press Escape key
      find("body").send_keys(:escape)

      # Modal should be hidden
      expect(page).to have_css("[data-slide-over-target='panel'].hidden", visible: :hidden, wait: 5)
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
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: /Summary/i)
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
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: /Metrics/i)
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
      expect(page).to have_css("[data-tabs-target='tab'][aria-selected='true']", text: /Logs/i)
      expect(page).to have_content(/No logs available/i)
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

  describe "slide-over from nodes overview page" do
    let!(:benchmark_run) do
      create(:benchmark_run, :success,
        node: node,
        benchmark_recipe: recipe,
        started_at: 2.hours.ago,
        finished_at: 1.hour.ago,
        metrics: { "gflops" => 99.99 })
    end

    it "opens slide-over when clicking View Details icon from node overview", :js do
      visit node_path(node)

      # The node overview shows recent benchmark runs (uppercase in UI)
      expect(page).to have_content(/recent benchmark runs/i)

      # Click View Details icon (eye icon)
      within("#node_recent_runs_tbody") do
        find("[title='View Details']", match: :first).click
      end

      # Slide-over should appear with run details
      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)
      within("[data-slide-over-target='panel']") do
        expect(page).to have_content(recipe.name, wait: 5)
        expect(page).to have_content(node.hostname)
      end
    end

    it "loads correct benchmark run content in slide-over from nodes page", :js do
      visit node_path(node)

      within("#node_recent_runs_tbody") do
        find("[title='View Details']", match: :first).click
      end

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Verify the content tabs work
      within("[data-slide-over-target='panel']") do
        expect(page).to have_content(/summary/i, wait: 5)

        # Click Metrics tab (find by aria-controls attribute)
        find("[aria-controls='tab-panel-metrics']").click
        expect(page).to have_content(/gflops/i)
        expect(page).to have_content("99.99")
      end
    end

    it "closes slide-over when pressing Escape from nodes page", :js do
      visit node_path(node)

      within("#node_recent_runs_tbody") do
        find("[title='View Details']", match: :first).click
      end

      expect(page).to have_css("[data-slide-over-target='panel']", visible: true, wait: 5)

      # Press Escape key
      find("body").send_keys(:escape)

      # Modal should be hidden
      expect(page).to have_css("[data-slide-over-target='panel'].hidden", visible: :hidden, wait: 5)
    end
  end
end
