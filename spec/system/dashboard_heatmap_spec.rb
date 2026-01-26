# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Heatmap", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "heatmap display" do
    context "when there are no nodes" do
      it "shows empty state message" do
        visit dashboard_path

        within("[data-controller='heatmap']") do
          expect(page).to have_content("No nodes registered")
          expect(page).to have_content("Import nodes via CSV or API")
        end
      end
    end

    context "when there are nodes" do
      let!(:compute_node) { create(:node, hostname: "compute-001", role: :compute, last_heartbeat_at: 1.minute.ago) }
      let!(:login_node) { create(:node, hostname: "login-001", role: :login, last_heartbeat_at: 1.minute.ago) }
      let!(:admin_node) { create(:node, hostname: "admin-001", role: :admin, last_heartbeat_at: 1.minute.ago) }
      let!(:offline_node) { create(:node, hostname: "compute-002", role: :compute, last_heartbeat_at: 10.minutes.ago) }

      it "displays heatmap grid with all nodes" do
        visit dashboard_path

        within("[data-controller='heatmap']") do
          expect(page).to have_css("[data-heatmap-target='cell']", count: 4)
          expect(page).to have_content("4 nodes total")
          expect(page).to have_content("3 online, 1 offline")
        end
      end

      it "shows legend with node status colors" do
        visit dashboard_path

        within("[data-controller='heatmap']") do
          expect(page).to have_content("Online")
          expect(page).to have_content("Offline")
          expect(page).to have_content("Login")
          expect(page).to have_content("Admin")
        end
      end

      it "displays node information in cell title/tooltip" do
        visit dashboard_path

        cell = find("[data-node-id='#{compute_node.id}']")
        expect(cell["title"]).to include("compute-001")
        expect(cell["title"]).to include("Compute")
        expect(cell["title"]).to include("Online")
      end
    end
  end

  describe "click filtering" do
    let!(:node1) { create(:node, hostname: "compute-001", last_heartbeat_at: 1.minute.ago) }
    let!(:node2) { create(:node, hostname: "compute-002", last_heartbeat_at: 1.minute.ago) }
    let!(:recipe) { create(:benchmark_recipe) }

    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe, started_at: 2.hours.ago) }

    context "without filter" do
      it "shows all recent benchmark runs" do
        visit dashboard_path

        within("#filtered_runs") do
          expect(page).to have_content(/Recent Benchmark Runs/i)
          expect(page).to have_content(node1.hostname)
          expect(page).to have_content(node2.hostname)
        end
      end
    end

    context "with node filter via URL parameter" do
      it "shows only filtered node runs" do
        visit dashboard_path(node_id: node1.id)

        within("#filtered_runs") do
          expect(page).to have_content(/Benchmark Runs: #{node1.hostname}/i)
          expect(page).to have_content(node1.hostname)
          expect(page).not_to have_content(node2.hostname)
        end
      end

      it "displays node info when filtered" do
        visit dashboard_path(node_id: node1.id)

        within("#filtered_runs") do
          expect(page).to have_content(/Benchmark Runs: compute-001/i)
          expect(page).to have_content(/Compute node/i)
        end
      end
    end

    context "when filtered node has no runs" do
      let!(:node3) { create(:node, hostname: "compute-003", last_heartbeat_at: 1.minute.ago) }

      it "shows empty state for that node" do
        visit dashboard_path(node_id: node3.id)

        within("#filtered_runs") do
          expect(page).to have_content(/No runs for compute-003/i)
          expect(page).to have_content(/Run a benchmark on this node/i)
        end
      end
    end
  end

  describe "helper methods" do
    context "node_heatmap_class" do
      it "returns warning classes for online admin nodes" do
        node = create(:node, role: :admin, last_heartbeat_at: 1.minute.ago)
        expect(ApplicationController.helpers.node_heatmap_class(node)).to include("bg-warning-5")
      end

      it "returns success classes for online compute nodes" do
        node = create(:node, role: :compute, last_heartbeat_at: 1.minute.ago)
        expect(ApplicationController.helpers.node_heatmap_class(node)).to include("bg-success-5")
      end

            it "returns login classes for online login nodes" do
              node = create(:node, role: :login, last_heartbeat_at: 1.minute.ago)
              expect(ApplicationController.helpers.node_heatmap_class(node)).to include("bg-login-5")
            end
            it "returns gray classes for offline nodes" do
        node = create(:node, role: :compute, last_heartbeat_at: 10.minutes.ago)
        expect(ApplicationController.helpers.node_heatmap_class(node)).to include("bg-neutral-15")
      end
    end
  end

  describe "Stimulus controller interactions", :js do
    let!(:node1) { create(:node, hostname: "compute-001", last_heartbeat_at: 1.minute.ago) }
    let!(:node2) { create(:node, hostname: "compute-002", last_heartbeat_at: 1.minute.ago) }
    let!(:recipe) { create(:benchmark_recipe) }
    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe, started_at: 2.hours.ago) }

    before do
      visit dashboard_path
      # Hide sidebar to prevent interception in tests
      page.execute_script("document.querySelector('aside').style.display = 'none'")
    end

    it "filters runs when clicking a node cell" do
      # Initially shows all runs
      within("#filtered_runs") do
        expect(page).to have_content(node1.hostname)
        expect(page).to have_content(node2.hostname)
      end

      # Click node1 to filter
      find("[data-node-id='#{node1.id}']").click(force: true)

      # Wait for the selected label to appear (visible, not hidden)
      expect(page).to have_css("[data-heatmap-target='selectedLabel']:not(.hidden)", text: /Filtered by: compute-001/i)

      # Wait for Turbo Frame to update with filtered content
      within("#filtered_runs") do
        expect(page).to have_content(/Benchmark Runs: compute-001/i, wait: 5)
        expect(page).to have_content(/#{Regexp.escape(run1.benchmark_recipe.display_name)}/i)
        expect(page).not_to have_content(run2.node.hostname)
      end
    end

    it "shows clear filter button when node is selected" do
      # Clear button initially not visible
      expect(page).not_to have_button("Clear filter", visible: true)

      # Click a node
      find("[data-node-id='#{node1.id}']").click(force: true)

      # Clear button becomes visible after selection
      expect(page).to have_button("Clear filter", visible: true, wait: 5)
    end

    it "clears filter when clicking clear button" do
      # Click node to filter
      find("[data-node-id='#{node1.id}']").click(force: true)

      # Wait for filter to be applied
      expect(page).to have_css("[data-heatmap-target='selectedLabel']:not(.hidden)", wait: 5)

      # Click clear filter button
      click_button "Clear filter"

      # Selected label becomes hidden
      expect(page).to have_css("[data-heatmap-target='selectedLabel'].hidden", visible: :hidden)

      # Runs list resets to show all
      within("#filtered_runs") do
        expect(page).to have_content(/Recent Benchmark Runs/i, wait: 5)
      end
    end

    it "toggles selection when clicking same node twice" do
      cell = find("[data-node-id='#{node1.id}']")

      # First click - select
      cell.click(force: true)
      expect(page).to have_css("[data-heatmap-target='selectedLabel']:not(.hidden)", wait: 5)

      # Second click - deselect
      cell.click(force: true)
      expect(page).to have_css("[data-heatmap-target='selectedLabel'].hidden", visible: :hidden, wait: 5)
    end

    it "highlights selected node with ring style" do
      cell_selector = "[data-node-id='#{node1.id}']"

      # Initially cells have focus:ring but not selection ring
      # The Stimulus controller should not add ring-2 class until clicked
      cell = find(cell_selector)
      initial_classes = cell[:class].split

      # Click to select - Stimulus adds ring-2 (without focus: prefix)
      cell.click(force: true)

      # Wait for UI update then check classes
      expect(page).to have_css("[data-heatmap-target='selectedLabel']:not(.hidden)", wait: 5)

      updated_cell = find(cell_selector)
      updated_classes = updated_cell[:class].split

      # Stimulus adds these selection classes (not focus: prefixed)
      expect(updated_classes).to include("ring-2")
      expect(updated_classes).to include("ring-primary-5")
      expect(updated_classes).to include("ring-offset-2")
    end
  end
end
