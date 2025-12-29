# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Benchmark Runs Filtering", type: :system do
  let(:user) { create(:user) }
  let(:node1) { create(:node, hostname: "compute-001") }
  let(:node2) { create(:node, hostname: "login-001", role: :login) }
  let(:recipe1) { create(:benchmark_recipe, name: "HPL", version: "2.3") }
  let(:recipe2) { create(:benchmark_recipe, name: "STREAM", version: "5.10") }

  before do
    sign_in user
  end

  describe "filter controls" do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }

    it "displays filter controls" do
      visit benchmark_runs_path

      expect(page).to have_field("Search")
      expect(page).to have_select("Status")
      expect(page).to have_select("Node")
      expect(page).to have_select("Recipe")
    end
  end

  describe "filtering by status", :js do
    let!(:success_run) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:failed_run) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "filters runs by status" do
      visit benchmark_runs_path

      # Initially shows all runs
      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).to have_content("login-001")
      end

      # Select status filter
      select "Success", from: "Status"

      # Wait for Turbo Frame to update
      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end
  end

  describe "filtering by node", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "filters runs by node" do
      visit benchmark_runs_path

      select "compute-001", from: "Node"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end
  end

  describe "filtering by recipe", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "filters runs by recipe" do
      visit benchmark_runs_path

      select "HPL", from: "Recipe"

      within("tbody") do
        expect(page).to have_content("HPL", wait: 5)
        expect(page).not_to have_content("STREAM")
      end
    end
  end

  describe "search functionality", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "searches runs by node hostname" do
      visit benchmark_runs_path

      fill_in "Search", with: "compute"
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
      end
    end

    it "searches runs by recipe name" do
      visit benchmark_runs_path

      fill_in "Search", with: "HPL"
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("HPL", wait: 5)
        expect(page).not_to have_content("STREAM")
      end
    end
  end

  describe "clearing filters", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "clears all filters when clicking clear button" do
      visit benchmark_runs_path(status: "success")

      # Should show filtered results
      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).not_to have_content("login-001")
      end

      # Click clear filters
      click_link "Clear filters"

      # Should show all runs
      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).to have_content("login-001")
      end
    end
  end

  describe "combined filters", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :success, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }
    let!(:run3) { create(:benchmark_run, :failed, node: node1, benchmark_recipe: recipe1, started_at: 3.hours.ago) }

    it "applies multiple filters" do
      visit benchmark_runs_path

      select "Success", from: "Status"
      select "compute-001", from: "Node"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
        expect(page).to have_selector("tr", count: 1)
      end
    end
  end

  describe "empty state" do
    it "shows empty state when no runs match filters" do
      visit benchmark_runs_path(status: "success")

      expect(page).to have_content("No benchmark runs")
    end
  end

  describe "filter persistence in URL", :js do
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe1, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe2, started_at: 2.hours.ago) }

    it "updates URL with filter parameters" do
      visit benchmark_runs_path

      select "Success", from: "Status"

      # Wait for filter to apply
      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
      end

      # URL should include filter parameter
      expect(page).to have_current_path(/status=success/)
    end
  end

  describe "pagination", :js do
    before do
      # Create 25 runs (more than default page size of 20)
      25.times do |i|
        create(:benchmark_run, :success,
          node: node1,
          benchmark_recipe: recipe1,
          started_at: i.hours.ago)
      end
    end

    it "shows pagination controls when there are many runs" do
      visit benchmark_runs_path

      expect(page).to have_css("[data-turbo-frame='runs_list']")
      # First page should have limited runs
      within("tbody") do
        expect(page).to have_selector("tr", maximum: 20)
      end
    end

    it "navigates to the next page when clicking Next" do
      visit benchmark_runs_path

      # Verify we're on page 1
      expect(page).to have_content("Showing 1 to 20 of 25 results")

      # Click Next link
      click_link "Next"

      # Verify page 2 content
      expect(page).to have_content("Showing 21 to 25 of 25 results", wait: 5)

      # First page has 20 rows, second page has 5 rows
      within("tbody") do
        expect(page).to have_selector("tr", count: 5)
      end

      # Previous link should now be visible
      expect(page).to have_link("Previous")
    end

    it "navigates back to the previous page when clicking Previous" do
      visit benchmark_runs_path(page: 2)

      # Verify we're on page 2
      expect(page).to have_content("Showing 21 to 25 of 25 results")

      # Click Previous link
      click_link "Previous"

      # Verify page 1 content
      expect(page).to have_content("Showing 1 to 20 of 25 results", wait: 5)

      within("tbody") do
        expect(page).to have_selector("tr", count: 20)
      end
    end
  end
end
