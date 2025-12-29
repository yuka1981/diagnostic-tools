# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Heatmap", type: :system do
  let(:user) { create(:user) }

  before do
    driven_by(:rack_test)
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
      let!(:compute_node) { create(:node, hostname: "compute-001", role: :compute, last_seen_at: 1.minute.ago) }
      let!(:login_node) { create(:node, hostname: "login-001", role: :login, last_seen_at: 1.minute.ago) }
      let!(:admin_node) { create(:node, hostname: "admin-001", role: :admin, last_seen_at: 1.minute.ago) }
      let!(:offline_node) { create(:node, hostname: "compute-002", role: :compute, last_seen_at: 10.minutes.ago) }

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
    let!(:node1) { create(:node, hostname: "compute-001", last_seen_at: 1.minute.ago) }
    let!(:node2) { create(:node, hostname: "compute-002", last_seen_at: 1.minute.ago) }
    let!(:recipe) { create(:benchmark_recipe) }

    let!(:run1) { create(:benchmark_run, :success, node: node1, benchmark_recipe: recipe, started_at: 1.hour.ago) }
    let!(:run2) { create(:benchmark_run, :failed, node: node2, benchmark_recipe: recipe, started_at: 2.hours.ago) }

    context "without filter" do
      it "shows all recent benchmark runs" do
        visit dashboard_path

        within("#filtered_runs") do
          expect(page).to have_content("Recent Benchmark Runs")
          expect(page).to have_content(node1.hostname)
          expect(page).to have_content(node2.hostname)
        end
      end
    end

    context "with node filter via URL parameter" do
      it "shows only filtered node runs" do
        visit dashboard_path(node_id: node1.id)

        within("#filtered_runs") do
          expect(page).to have_content("Benchmark Runs for #{node1.hostname}")
          expect(page).to have_content(node1.hostname)
          expect(page).not_to have_content(node2.hostname)
        end
      end

      it "displays node info when filtered" do
        visit dashboard_path(node_id: node1.id)

        within("#filtered_runs") do
          expect(page).to have_content("Benchmark Runs for compute-001")
          expect(page).to have_content("Compute node")
        end
      end
    end

    context "when filtered node has no runs" do
      let!(:node3) { create(:node, hostname: "compute-003", last_seen_at: 1.minute.ago) }

      it "shows empty state for that node" do
        visit dashboard_path(node_id: node3.id)

        within("#filtered_runs") do
          expect(page).to have_content("No benchmark runs for compute-003")
          expect(page).to have_content("Run a benchmark on this node")
        end
      end
    end
  end

  describe "helper methods" do
    describe "node_heatmap_class" do
      let(:helper) { ApplicationController.helpers }

      it "returns emerald classes for online compute nodes" do
        node = build(:node, role: :compute, last_seen_at: 1.minute.ago)
        expect(helper.node_heatmap_class(node)).to include("bg-emerald-500")
      end

      it "returns blue classes for online login nodes" do
        node = build(:node, role: :login, last_seen_at: 1.minute.ago)
        expect(helper.node_heatmap_class(node)).to include("bg-blue-500")
      end

      it "returns amber classes for online admin nodes" do
        node = build(:node, role: :admin, last_seen_at: 1.minute.ago)
        expect(helper.node_heatmap_class(node)).to include("bg-amber-500")
      end

      it "returns gray classes for offline nodes" do
        node = build(:node, role: :compute, last_seen_at: 10.minutes.ago)
        expect(helper.node_heatmap_class(node)).to include("bg-gray-300")
      end
    end
  end
end
