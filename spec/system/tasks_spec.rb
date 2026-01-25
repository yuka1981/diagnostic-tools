# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tasks", type: :system do
  let(:user) { create(:user) }
  let(:node1) { create(:node, hostname: "compute-001") }
  let(:node2) { create(:node, hostname: "login-001", role: :login) }
  let(:benchmark_recipe) { create(:benchmark_recipe, :hpcg) }
  let(:benchmark_recipe2) { create(:benchmark_recipe, name: "HPL", version: "2.3") }
  let(:profiling_recipe) { create(:profiling_recipe, :report) }
  let(:profiling_recipe2) { create(:profiling_recipe, :telemetry) }

  before { sign_in user }

  describe "page display" do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }
    let!(:profiling_run) { create(:profiling_run, :running, node: node2, profiling_recipe: profiling_recipe) }

    it "displays the tasks page with heading" do
      visit tasks_path

      expect(page).to have_content("Tasks")
      expect(page).to have_css("h1", text: "Tasks")
    end

    it "shows tasks link in sidebar" do
      visit tasks_path

      within("aside") do
        expect(page).to have_link("Tasks", href: tasks_path)
      end
    end

    it "displays both benchmark and profiling runs" do
      visit tasks_path

      expect(page).to have_content("compute-001")
      expect(page).to have_content("login-001")
      expect(page).to have_content(benchmark_recipe.name)
      expect(page).to have_content(profiling_recipe.name)
    end

    it "shows type badges for benchmark and profiling" do
      visit tasks_path

      expect(page).to have_css(".bg-blue-100", text: "Benchmark")
      expect(page).to have_css(".bg-purple-100", text: "Profiling")
    end

    it "shows status badges with correct colors" do
      visit tasks_path

      # Success status should have green styling
      expect(page).to have_content("Success")
      # Running status should have blue styling
      expect(page).to have_content("Running")
    end

    it "shows auto-refresh dropdown" do
      visit tasks_path

      expect(page).to have_select(nil, options: [ "Auto-refresh: Off", "10s", "30s", "1m", "5m" ])
    end
  end

  describe "filter controls" do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

    it "displays all filter controls" do
      visit tasks_path

      expect(page).to have_field("Search")
      expect(page).to have_select("Type")
      expect(page).to have_select("Status")
      expect(page).to have_select("Node")
      expect(page).to have_select("Recipe")
      expect(page).to have_select("Date")
    end
  end

  describe "filtering by type", :js do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:profiling_run) { create(:profiling_run, :success, node: node2, profiling_recipe: profiling_recipe, started_at: 2.hours.ago) }

    it "filters benchmark only" do
      visit tasks_path

      # Initially shows all tasks
      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).to have_content("login-001")
      end

      select "Benchmark", from: "Type"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
        expect(page).to have_css(".bg-blue-100", text: "Benchmark")
        expect(page).not_to have_css(".bg-purple-100", text: "Profiling")
      end
    end

    it "filters profiling only" do
      visit tasks_path

      select "Profiling", from: "Type"

      within("tbody") do
        expect(page).to have_content("login-001", wait: 5)
        expect(page).not_to have_content("compute-001")
        expect(page).to have_css(".bg-purple-100", text: "Profiling")
        expect(page).not_to have_css(".bg-blue-100", text: "Benchmark")
      end
    end
  end

  describe "filtering by status", :js do
    let!(:success_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:pending_run) { create(:benchmark_run, node: node2, benchmark_recipe: benchmark_recipe) }
    let!(:failed_run) { create(:profiling_run, :failed, node: node1, profiling_recipe: profiling_recipe, started_at: 30.minutes.ago) }

    it "filters by success status" do
      visit tasks_path

      select "Success", from: "Status"

      within("tbody") do
        expect(page).to have_content("Success", wait: 5)
        expect(page).not_to have_content("Pending")
        expect(page).not_to have_content("Failed")
      end
    end

    it "filters by pending status" do
      visit tasks_path

      select "Pending", from: "Status"

      within("tbody") do
        expect(page).to have_content("Pending", wait: 5)
        expect(page).not_to have_content("Success")
      end
    end

    it "filters by failed status" do
      visit tasks_path

      select "Failed", from: "Status"

      within("tbody") do
        expect(page).to have_content("Failed", wait: 5)
        expect(page).not_to have_content("Success")
      end
    end

    it "filters by running status" do
      create(:profiling_run, :running, node: node2, profiling_recipe: profiling_recipe)
      visit tasks_path

      select "Running", from: "Status"

      within("tbody") do
        expect(page).to have_content("Running", wait: 5)
      end
    end

    it "filters by cancelled status" do
      create(:benchmark_run, :cancelled, node: node1, benchmark_recipe: benchmark_recipe)
      visit tasks_path

      select "Cancelled", from: "Status"

      within("tbody") do
        expect(page).to have_content("Cancelled", wait: 5)
      end
    end
  end

  describe "filtering by node", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:profiling_run, :success, node: node2, profiling_recipe: profiling_recipe, started_at: 2.hours.ago) }

    it "filters runs by node" do
      visit tasks_path

      select "compute-001", from: "Node"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end
  end

  describe "filtering by recipe", :js do
    let!(:hpcg_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:hpl_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe2, started_at: 2.hours.ago) }
    let!(:profile_run) { create(:profiling_run, :success, node: node2, profiling_recipe: profiling_recipe, started_at: 3.hours.ago) }

    it "filters by benchmark recipe" do
      visit tasks_path

      select "Benchmark: #{benchmark_recipe.name}", from: "Recipe"

      within("tbody") do
        expect(page).to have_content(benchmark_recipe.name, wait: 5)
        expect(page).not_to have_content("HPL")
        expect(page).not_to have_content(profiling_recipe.name)
      end
    end

    it "filters by profiling recipe" do
      visit tasks_path

      select "Profiling: #{profiling_recipe.name}", from: "Recipe"

      within("tbody") do
        expect(page).to have_content(profiling_recipe.name, wait: 5)
        expect(page).not_to have_content(benchmark_recipe.name)
      end
    end
  end

  describe "filtering by date range", :js do
    let!(:recent_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, created_at: 30.minutes.ago, started_at: 30.minutes.ago) }
    let!(:old_run) { create(:benchmark_run, :success, node: node2, benchmark_recipe: benchmark_recipe, created_at: 2.days.ago, started_at: 2.days.ago) }

    it "filters by last hour" do
      visit tasks_path

      select "Last Hour", from: "Date"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end

    it "filters by last 24 hours" do
      visit tasks_path

      select "Last 24 Hours", from: "Date"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end

    it "filters by last 7 days" do
      visit tasks_path

      select "Last 7 Days", from: "Date"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).to have_content("login-001")
      end
    end
  end

  describe "search functionality", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:profiling_run, :success, node: node2, profiling_recipe: profiling_recipe, started_at: 2.hours.ago) }

    it "searches by node hostname" do
      visit tasks_path

      fill_in "Search", with: "compute"
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end

    it "searches by recipe name" do
      visit tasks_path

      fill_in "Search", with: benchmark_recipe.name
      click_button "Search"

      within("tbody") do
        expect(page).to have_content(benchmark_recipe.name, wait: 5)
        expect(page).not_to have_content(profiling_recipe.name)
      end
    end

    it "searches by uuid" do
      visit tasks_path

      fill_in "Search", with: run1.uuid[0..8]
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
      end
    end
  end

  describe "clearing filters", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:profiling_run, :failed, node: node2, profiling_recipe: profiling_recipe, started_at: 2.hours.ago) }

    it "clears all filters when clicking clear button" do
      visit tasks_path(status: "success")

      # Should show filtered results
      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).not_to have_content("login-001")
      end

      # Click clear button
      click_link "Clear"

      # Should show all runs
      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).to have_content("login-001")
      end
    end

    it "shows clear button only when filters are active" do
      # Without filters, no clear button
      visit tasks_path
      expect(page).not_to have_link("Clear")

      # With filters applied via URL, clear button should appear
      visit tasks_path(status: "success")
      expect(page).to have_link("Clear")
    end
  end

  describe "combined filters", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :success, node: node2, benchmark_recipe: benchmark_recipe, started_at: 2.hours.ago) }
    let!(:run3) { create(:benchmark_run, :failed, node: node1, benchmark_recipe: benchmark_recipe, started_at: 3.hours.ago) }
    let!(:run4) { create(:profiling_run, :success, node: node1, profiling_recipe: profiling_recipe, started_at: 4.hours.ago) }

    it "applies multiple filters together" do
      visit tasks_path

      select "Success", from: "Status"
      select "compute-001", from: "Node"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
        # Only 2 matches: run1 (benchmark success on compute-001) and run4 (profiling success on compute-001)
        expect(page).to have_selector("tr[data-accordion-target='row']", count: 2)
      end
    end

    it "applies type and status filters together" do
      visit tasks_path

      select "Benchmark", from: "Type"
      select "Success", from: "Status"

      within("tbody") do
        # Only run1 and run2 are benchmark + success
        expect(page).to have_selector("tr[data-accordion-target='row'][id^='task_benchmark']", count: 2, wait: 5)
        expect(page).not_to have_css(".bg-purple-100")
      end
    end
  end

  describe "accordion row expansion", :js do
    let!(:benchmark_run) do
      create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe,
             started_at: 2.hours.ago, finished_at: 1.hour.ago, metrics: { "gflops" => 123.45, "efficiency" => 0.85 })
    end

    it "expands row details when clicking" do
      visit tasks_path

      # Details row should be collapsed initially (has hidden class)
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details.hidden", visible: :all)

      # Click the row to expand
      find("#task_benchmark_#{benchmark_run.id}").click

      # Details should be visible (hidden class removed)
      expect(page).not_to have_css("#task_benchmark_#{benchmark_run.id}_details.hidden", wait: 5)
    end

    it "collapses row details when clicking again" do
      visit tasks_path

      # Expand
      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).not_to have_css("#task_benchmark_#{benchmark_run.id}_details.hidden", wait: 5)

      # Collapse - click the main row again
      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details.hidden", visible: :all, wait: 5)
    end

    it "shows details section with started and finished times" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_content("Started:")
        expect(page).to have_content("Finished:")
      end
    end

    it "shows uuid in details section" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_content("UUID:")
        expect(page).to have_content(benchmark_run.uuid[0..7])
      end
    end

    it "shows recipe in details section" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_content("Recipe:")
        expect(page).to have_content(benchmark_recipe.name)
      end
    end

    it "shows metrics when present" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        # Headers are uppercase in the UI
        expect(page).to have_content(/metrics/i)
        # The metric key "gflops" is displayed as "GFLOP/s" after formatting
        expect(page).to have_content(/gflop/i)
        expect(page).to have_content("123.45")
        expect(page).to have_content(/efficiency/i)
        expect(page).to have_content("0.85")
      end
    end

    it "shows no metrics message when metrics are empty" do
      run_without_metrics = create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, metrics: {})
      visit tasks_path

      find("#task_benchmark_#{run_without_metrics.id}").click
      expect(page).to have_css("#task_benchmark_#{run_without_metrics.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{run_without_metrics.id}_details") do
        expect(page).to have_content("No metrics available")
      end
    end
  end

  describe "error message display", :js do
    let!(:failed_run) do
      create(:benchmark_run, :failed, node: node1, benchmark_recipe: benchmark_recipe,
             error_message: "Build failed: missing module gcc/12.2.0")
    end

    it "shows error message for failed tasks" do
      visit tasks_path

      find("#task_benchmark_#{failed_run.id}").click
      expect(page).to have_css("#task_benchmark_#{failed_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{failed_run.id}_details") do
        # Headers are uppercase in the UI
        expect(page).to have_content(/error/i)
        expect(page).to have_content("Build failed: missing module gcc/12.2.0")
      end
    end
  end

  describe "artifacts display", :js do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }
    let!(:artifact) { create(:artifact_index, :log, benchmark_run: benchmark_run) }

    it "shows artifacts section when artifacts exist" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        # Headers are uppercase in the UI
        expect(page).to have_content(/artifacts/i)
        expect(page).to have_content("hpcg.log")
      end
    end
  end

  describe "cancel action", :js do
    context "with pending task" do
      let!(:pending_run) { create(:benchmark_run, node: node1, benchmark_recipe: benchmark_recipe, status: :pending) }

      it "shows cancel button for pending tasks" do
        visit tasks_path

        within("#task_benchmark_#{pending_run.id}") do
          expect(page).to have_css("[title='Cancel']")
        end
      end

      it "cancels the task when clicking cancel" do
        visit tasks_path

        within("#task_benchmark_#{pending_run.id}") do
          accept_confirm do
            find("[title='Cancel']").click
          end
        end

        # Wait for the page to update - the task should show as cancelled
        expect(page).to have_content("Cancelled", wait: 5)
        expect(pending_run.reload.status).to eq("cancelled")
      end

      it "shows cancel button in expanded details for pending tasks" do
        visit tasks_path

        find("#task_benchmark_#{pending_run.id}").click

        within("#task_benchmark_#{pending_run.id}_details") do
          expect(page).to have_button("Cancel")
        end
      end
    end

    context "with running task" do
      let!(:running_run) { create(:benchmark_run, :running, node: node1, benchmark_recipe: benchmark_recipe) }

      it "shows cancel button for running tasks" do
        visit tasks_path

        within("#task_benchmark_#{running_run.id}") do
          expect(page).to have_css("[title='Cancel']")
        end
      end
    end

    context "with completed task" do
      let!(:completed_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

      it "does not show cancel button for completed tasks" do
        visit tasks_path

        within("#task_benchmark_#{completed_run.id}") do
          expect(page).not_to have_css("[title='Cancel']")
        end
      end

      it "does not show cancel button in expanded details for completed tasks" do
        visit tasks_path

        find("#task_benchmark_#{completed_run.id}").click

        within("#task_benchmark_#{completed_run.id}_details") do
          expect(page).not_to have_button("Cancel")
        end
      end
    end
  end

  describe "delete action", :js do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

    it "shows delete button for all tasks" do
      visit tasks_path

      within("#task_benchmark_#{benchmark_run.id}") do
        expect(page).to have_css("[title='Delete']")
      end
    end

    it "deletes the task when clicking delete" do
      visit tasks_path

      within("#task_benchmark_#{benchmark_run.id}") do
        accept_confirm do
          find("[title='Delete']").click
        end
      end

      # Wait for the row to be removed from the page
      expect(page).not_to have_css("#task_benchmark_#{benchmark_run.id}", wait: 5)
      expect(BenchmarkRun.exists?(benchmark_run.id)).to be false
    end

    it "shows delete button in expanded details" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_button("Delete")
      end
    end
  end

  describe "re-run action", :js do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

    it "shows re-run button in expanded details" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_button("Re-run")
      end
    end

    it "creates a new task when clicking re-run" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      within("#task_benchmark_#{benchmark_run.id}_details") do
        accept_confirm do
          click_button "Re-run"
        end
      end

      # Wait for the page to update - a new task should appear
      # There should now be 2 benchmark tasks
      expect(page).to have_selector("tr[data-accordion-target='row'][id^='task_benchmark']", count: 2, wait: 5)
      expect(BenchmarkRun.count).to eq(2)
    end
  end

  describe "view node action", :js do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

    it "shows view node link in expanded details" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click

      within("#task_benchmark_#{benchmark_run.id}_details") do
        expect(page).to have_link("View Node", href: node_path(node1))
      end
    end

    it "navigates to node page when clicking view node" do
      visit tasks_path

      find("#task_benchmark_#{benchmark_run.id}").click
      expect(page).to have_css("#task_benchmark_#{benchmark_run.id}_details", visible: true, wait: 5)

      # Find the View Node link and use visit instead to ensure navigation
      link_href = find("#task_benchmark_#{benchmark_run.id}_details a", text: "View Node")[:href]
      visit link_href

      # Wait for navigation to complete - check for node page content
      expect(page).to have_current_path(node_path(node1))
      expect(page).to have_content(node1.hostname)
    end
  end

  describe "node link in table row" do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe) }

    it "has clickable node hostname link" do
      visit tasks_path

      within("#task_benchmark_#{benchmark_run.id}") do
        expect(page).to have_link("compute-001", href: node_path(node1))
      end
    end
  end

  describe "pagination", :js do
    before do
      # Create 30 tasks (more than the default 20 per page)
      30.times do |i|
        create(:benchmark_run, :success,
               node: node1,
               benchmark_recipe: benchmark_recipe,
               started_at: i.hours.ago,
               created_at: i.hours.ago)
      end
    end

    it "shows pagination controls when there are many tasks" do
      visit tasks_path

      expect(page).to have_content(/Showing 1 to 20 of 30 tasks/i)
      expect(page).to have_css('a[rel="next"]')
    end

    it "navigates to the next page" do
      visit tasks_path

      find('a[rel="next"]').click

      expect(page).to have_content(/Showing 21 to 30 of 30 tasks/i, wait: 5)
      expect(page).to have_css('a[rel="prev"]')
    end

    it "navigates back to the previous page" do
      visit tasks_path(page: 2)

      find('a[rel="prev"]').click

      expect(page).to have_content(/Showing 1 to 20 of 30 tasks/i, wait: 5)
    end

    it "shows correct number of rows per page" do
      visit tasks_path

      within("tbody") do
        expect(page).to have_selector("tr[data-accordion-target='row']", count: 20)
      end
    end
  end

  describe "empty state" do
    it "shows empty state when no tasks exist" do
      visit tasks_path

      expect(page).to have_content("No tasks yet")
    end

    it "shows empty state when no tasks match filters" do
      create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe)
      visit tasks_path(status: "failed")

      expect(page).to have_content("No tasks match your filters")
      expect(page).to have_link("Clear all filters")
    end

    it "clear filters button works from empty state" do
      create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe)
      visit tasks_path(status: "failed")

      click_link "Clear all filters"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
      end
    end
  end

  describe "filter persistence in URL", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }

    it "updates URL with filter parameters" do
      visit tasks_path

      select "Success", from: "Status"

      # Wait for filter to apply
      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
      end

      expect(page).to have_current_path(/status=success/)
    end

    it "maintains filters when reloading page" do
      visit tasks_path(status: "success", type: "benchmark")

      expect(page).to have_select("Status", selected: "Success")
      expect(page).to have_select("Type", selected: "Benchmark")
    end
  end

  describe "filter summary display" do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }

    it "shows filter summary when filters are active" do
      visit tasks_path(status: "success")

      expect(page).to have_content(/Showing \d+ task/)
    end

    it "shows search query in filter summary when searching" do
      visit tasks_path(q: "compute")

      expect(page).to have_content('matching "compute"')
    end
  end

  describe "profiling run with error", :js do
    let!(:failed_profiling) do
      create(:profiling_run, :failed, node: node1, profiling_recipe: profiling_recipe,
             error_message: "Module perfspect/3.13.0 not found")
    end

    it "shows error message for failed profiling tasks" do
      visit tasks_path

      find("#task_profiling_#{failed_profiling.id}").click
      expect(page).to have_css("#task_profiling_#{failed_profiling.id}_details", visible: true, wait: 5)

      within("#task_profiling_#{failed_profiling.id}_details") do
        # Headers are uppercase in the UI
        expect(page).to have_content(/error/i)
        expect(page).to have_content("Module perfspect/3.13.0 not found")
      end
    end
  end

  describe "profiling run with artifacts", :js do
    let!(:profiling_run) { create(:profiling_run, :success, node: node1, profiling_recipe: profiling_recipe) }
    let!(:artifact) { create(:profiling_artifact, :html_report, profiling_run: profiling_run) }

    it "shows artifacts for profiling tasks" do
      visit tasks_path

      find("#task_profiling_#{profiling_run.id}").click
      expect(page).to have_css("#task_profiling_#{profiling_run.id}_details", visible: true, wait: 5)

      within("#task_profiling_#{profiling_run.id}_details") do
        # Headers are uppercase in the UI
        expect(page).to have_content(/artifacts/i)
        expect(page).to have_content("system_report.html")
      end
    end
  end

  describe "running task indicator" do
    let!(:running_run) { create(:benchmark_run, :running, node: node1, benchmark_recipe: benchmark_recipe) }

    it "shows spinner icon for running tasks" do
      visit tasks_path

      within("#task_benchmark_#{running_run.id}") do
        expect(page).to have_css(".animate-spin")
      end
    end
  end

  describe "duration display" do
    let!(:run_with_duration) do
      create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe,
             started_at: 2.hours.ago, finished_at: 1.hour.ago)
    end
    let!(:pending_run) { create(:benchmark_run, node: node1, benchmark_recipe: benchmark_recipe, status: :pending) }

    it "shows duration for completed tasks" do
      visit tasks_path

      within("#task_benchmark_#{run_with_duration.id}") do
        expect(page).to have_content(/about 1 hour|1 hour/)
      end
    end

    it "shows dash for pending tasks" do
      visit tasks_path

      within("#task_benchmark_#{pending_run.id}") do
        expect(page).to have_content("-")
      end
    end
  end

  describe "started time display" do
    let!(:benchmark_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe, started_at: 1.hour.ago) }
    let!(:pending_run) { create(:benchmark_run, node: node1, benchmark_recipe: benchmark_recipe, status: :pending) }

    it "shows time ago for started tasks" do
      visit tasks_path

      within("#task_benchmark_#{benchmark_run.id}") do
        expect(page).to have_content(/ago/)
      end
    end

    it "shows pending for tasks not yet started" do
      visit tasks_path

      within("#task_benchmark_#{pending_run.id}") do
        expect(page).to have_content("Pending")
      end
    end
  end

  describe "accordion expansion after Turbo Frame refresh", :js do
    let!(:benchmark_run1) do
      create(:benchmark_run, :success, node: node1, benchmark_recipe: benchmark_recipe,
             started_at: 1.hour.ago, finished_at: 30.minutes.ago)
    end
    let!(:benchmark_run2) do
      create(:benchmark_run, :success, node: node2, benchmark_recipe: benchmark_recipe2,
             started_at: 2.hours.ago, finished_at: 1.hour.ago)
    end

    describe "basic accordion functionality" do
      it "expands row when clicking and shows chevron rotation" do
        visit tasks_path

        # Details row should be collapsed initially (has hidden class)
        expect(page).to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", visible: :all)

        # Chevron should not be rotated
        within("#task_benchmark_#{benchmark_run1.id}") do
          expect(page).not_to have_css("[data-accordion-target='chevron'].rotate-90")
        end

        # Click the row to expand
        find("#task_benchmark_#{benchmark_run1.id}").click

        # Details row should expand (hidden class removed)
        expect(page).not_to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", wait: 5)

        # Chevron should be rotated
        within("#task_benchmark_#{benchmark_run1.id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90", wait: 5)
        end
      end

      it "collapses row when clicking the same row again" do
        visit tasks_path

        # Expand
        find("#task_benchmark_#{benchmark_run1.id}").click
        expect(page).not_to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", wait: 5)

        # Collapse by clicking again
        find("#task_benchmark_#{benchmark_run1.id}").click

        # Details row should be collapsed again (hidden class added back)
        expect(page).to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", visible: :all, wait: 5)

        # Chevron should not be rotated
        within("#task_benchmark_#{benchmark_run1.id}") do
          expect(page).not_to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end

      it "closes previously opened row when clicking a different row (exclusive mode)" do
        visit tasks_path

        # Expand first row
        find("#task_benchmark_#{benchmark_run1.id}").click
        expect(page).not_to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", wait: 5)

        # Click second row - should close first row and open second
        find("#task_benchmark_#{benchmark_run2.id}").click

        # First row should be collapsed
        expect(page).to have_css("#task_benchmark_#{benchmark_run1.id}_details.hidden", visible: :all, wait: 5)
        within("#task_benchmark_#{benchmark_run1.id}") do
          expect(page).not_to have_css("[data-accordion-target='chevron'].rotate-90")
        end

        # Second row should be expanded
        expect(page).not_to have_css("#task_benchmark_#{benchmark_run2.id}_details.hidden")
        within("#task_benchmark_#{benchmark_run2.id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end
    end

    describe "accordion after pagination (Turbo Frame refresh)" do
      before do
        # Create enough tasks to have multiple pages (more than 20)
        25.times do |i|
          create(:benchmark_run, :success,
                 node: node1,
                 benchmark_recipe: benchmark_recipe,
                 started_at: (i + 3).hours.ago,
                 created_at: (i + 3).hours.ago)
        end
      end

      it "accordion expansion works after navigating to next page" do
        visit tasks_path

        # Navigate to page 2
        find('a[rel="next"]').click
        expect(page).to have_content(/showing 21 to/i, wait: 5)

        # Get the first task row on page 2
        first_row = find("tbody tr[data-accordion-target='row']", match: :first)
        row_id = first_row[:id]
        details_id = "#{row_id}_details"

        # Details should be collapsed initially (has hidden class)
        expect(page).to have_css("##{details_id}.hidden", visible: :all)

        # Click to expand - accordion should still work after Turbo Frame refresh
        first_row.click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)

        # Chevron should be rotated
        within("##{row_id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end

      it "accordion expansion works after navigating back to previous page" do
        visit tasks_path(page: 2)

        # Navigate back to page 1
        find('a[rel="prev"]').click
        expect(page).to have_content(/showing 1 to 20/i, wait: 5)

        # Get the first task row on page 1
        first_row = find("tbody tr[data-accordion-target='row']", match: :first)
        row_id = first_row[:id]
        details_id = "#{row_id}_details"

        # Click to expand - accordion should work after Turbo Frame refresh
        first_row.click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)

        # Verify chevron rotation
        within("##{row_id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end

      it "exclusive mode works after pagination" do
        visit tasks_path

        # Navigate to page 2 to trigger Turbo Frame refresh
        find('a[rel="next"]').click
        expect(page).to have_content(/showing 21 to/i, wait: 5)

        # Get the first two task rows on page 2
        rows = all("tbody tr[data-accordion-target='row']")
        first_row = rows[0]
        second_row = rows[1]
        first_row_id = first_row[:id]
        second_row_id = second_row[:id]

        # Expand first row
        first_row.click
        expect(page).not_to have_css("##{first_row_id}_details.hidden", wait: 5)

        # Click second row - exclusive mode should close the first
        second_row.click

        # First row should be collapsed
        expect(page).to have_css("##{first_row_id}_details.hidden", visible: :all, wait: 5)

        # Second row should be expanded
        expect(page).not_to have_css("##{second_row_id}_details.hidden")
      end
    end

    describe "accordion after filtering (Turbo Frame refresh)" do
      let!(:failed_run) do
        create(:benchmark_run, :failed, node: node1, benchmark_recipe: benchmark_recipe,
               started_at: 30.minutes.ago)
      end
      let!(:profiling_run) do
        create(:profiling_run, :success, node: node2, profiling_recipe: profiling_recipe,
               started_at: 45.minutes.ago)
      end

      it "accordion expansion works after applying status filter" do
        visit tasks_path

        # Apply status filter - triggers Turbo Frame refresh
        select "Success", from: "Status"

        # Wait for filter to be applied
        within("tbody") do
          expect(page).to have_content("Success", wait: 5)
          expect(page).not_to have_content("Failed")
        end

        # Get first task row after filtering
        first_row = find("tbody tr[data-accordion-target='row']", match: :first)
        row_id = first_row[:id]
        details_id = "#{row_id}_details"

        # Click to expand - accordion should work after filter refresh
        first_row.click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)

        # Chevron should be rotated
        within("##{row_id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end

      it "accordion expansion works after applying type filter" do
        visit tasks_path

        # Apply type filter - triggers Turbo Frame refresh
        select "Profiling", from: "Type"

        # Wait for filter to be applied
        within("tbody") do
          expect(page).to have_css(".bg-purple-100", text: "Profiling", wait: 5)
          expect(page).not_to have_css(".bg-blue-100", text: "Benchmark")
        end

        # Get the profiling task row
        profiling_row = find("#task_profiling_#{profiling_run.id}")
        details_id = "task_profiling_#{profiling_run.id}_details"

        # Click to expand
        profiling_row.click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)
      end

      it "accordion expansion works after applying node filter" do
        visit tasks_path

        # Apply node filter - triggers Turbo Frame refresh
        select "compute-001", from: "Node"

        # Wait for filter to be applied
        within("tbody") do
          expect(page).to have_content("compute-001", wait: 5)
          expect(page).not_to have_content("login-001")
        end

        # Get first task row after filtering
        first_row = find("tbody tr[data-accordion-target='row']", match: :first)
        row_id = first_row[:id]
        details_id = "#{row_id}_details"

        # Click to expand
        first_row.click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)
      end

      it "accordion expansion works after clearing filters" do
        visit tasks_path(status: "success")

        # Verify filter is applied
        expect(page).to have_link("Clear")

        # Clear filters - triggers Turbo Frame refresh
        click_link "Clear"

        # Wait for all tasks to be visible and Turbo Frame to settle
        within("tbody") do
          expect(page).to have_content("compute-001", wait: 5)
          expect(page).to have_content("login-001")
        end

        # Wait for Turbo Frame to fully settle
        sleep 0.5

        # Get row ID directly from DOM to avoid stale reference
        row_id = page.evaluate_script(<<~JS)
          document.querySelector("tbody tr[data-accordion-target='row']")?.id
        JS

        details_id = "#{row_id}_details"

        # Click to expand using fresh element reference
        find("##{row_id}").click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)
      end

      it "exclusive mode works after filtering" do
        visit tasks_path

        # Apply filter to show only success status
        select "Success", from: "Status"

        # Wait for filter to be fully applied and DOM to settle
        within("tbody") do
          expect(page).to have_content("Success", wait: 5)
        end

        # Wait a moment for Turbo Frame to fully settle
        sleep 0.5

        # Get row IDs directly from DOM to avoid stale references
        row_ids = page.evaluate_script(<<~JS)
          Array.from(document.querySelectorAll("tbody tr[data-accordion-target='row']"))
            .slice(0, 2)
            .map(r => r.id)
        JS

        return if row_ids.length < 2 # Skip if not enough rows

        first_row_id = row_ids[0]
        second_row_id = row_ids[1]

        # Expand first row by finding it fresh
        find("##{first_row_id}").click
        expect(page).not_to have_css("##{first_row_id}_details.hidden", wait: 5)

        # Click second row - exclusive mode should close first
        find("##{second_row_id}").click

        # First row should be collapsed
        expect(page).to have_css("##{first_row_id}_details.hidden", visible: :all, wait: 5)

        # Second row should be expanded
        expect(page).not_to have_css("##{second_row_id}_details.hidden")
      end
    end

    describe "accordion after search (Turbo Frame refresh)" do
      it "accordion expansion works after performing search" do
        visit tasks_path

        # Perform search - triggers Turbo Frame refresh
        fill_in "Search", with: "compute"
        click_button "Search"

        # Wait for search results
        within("tbody") do
          expect(page).to have_content("compute-001", wait: 5)
        end

        # Wait for Turbo Frame to fully settle
        sleep 0.5

        # Get row ID directly from DOM to avoid stale reference
        row_id = page.evaluate_script(<<~JS)
          document.querySelector("tbody tr[data-accordion-target='row']")?.id
        JS

        details_id = "#{row_id}_details"

        # Click to expand using fresh element reference
        find("##{row_id}").click

        # Details should be expanded (hidden class removed)
        expect(page).not_to have_css("##{details_id}.hidden", wait: 5)

        # Verify chevron rotation
        within("##{row_id}") do
          expect(page).to have_css("[data-accordion-target='chevron'].rotate-90")
        end
      end
    end
  end
end
