# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nodes Filtering", type: :system do
  let(:user) { create(:user, :approver) }
  let!(:compute_node) { create(:node, hostname: "compute-001", role: :compute, ip: "10.0.0.1", last_seen_at: 1.minute.ago) }
  let!(:login_node) { create(:node, hostname: "login-001", role: :login, ip: "10.0.0.2", last_seen_at: 1.hour.ago) }
  let!(:admin_node) { create(:node, hostname: "admin-001", role: :admin, ip: "192.168.1.1", last_seen_at: 1.minute.ago) }

  before do
    sign_in user
  end

  describe "filter controls" do
    it "displays filter controls" do
      visit nodes_path

      expect(page).to have_field("Search")
      expect(page).to have_select("Role")
      expect(page).to have_select("Status")
    end
  end

  describe "filtering by role", :js do
    it "filters nodes by role" do
      visit nodes_path

      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).to have_content("login-001")
        expect(page).to have_content("admin-001")
      end

      select "Compute", from: "Role"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
        expect(page).not_to have_content("admin-001")
      end
    end
  end

  describe "filtering by status", :js do
    it "filters nodes by status" do
      visit nodes_path

      # compute-001 and admin-001 are online (seen 1 min ago)
      # login-001 is offline (seen 1 hour ago)

      select "Online", from: "Status"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).to have_content("admin-001")
        expect(page).not_to have_content("login-001")
      end

      select "Offline", from: "Status"

      within("tbody") do
        expect(page).to have_content("login-001", wait: 5)
        expect(page).not_to have_content("compute-001")
        expect(page).not_to have_content("admin-001")
      end
    end
  end

  describe "search functionality", :js do
    it "searches nodes by hostname" do
      visit nodes_path

      fill_in "Search", with: "admin"
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("admin-001", wait: 5)
        expect(page).not_to have_content("compute-001")
        expect(page).not_to have_content("login-001")
      end
    end

    it "searches nodes by IP" do
      visit nodes_path

      fill_in "Search", with: "192.168"
      click_button "Search"

      within("tbody") do
        expect(page).to have_content("admin-001", wait: 5)
        expect(page).not_to have_content("compute-001") # 10.0.0.1
        expect(page).not_to have_content("login-001")   # 10.0.0.2
      end
    end
  end

  describe "clearing filters", :js do
    it "clears all filters when clicking clear button" do
      visit nodes_path(role: "compute")

      within("tbody") do
        expect(page).to have_content("compute-001")
        expect(page).not_to have_content("login-001")
      end

      click_link "Clear filters"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).to have_content("login-001")
        expect(page).to have_content("admin-001")
      end
    end
  end

  describe "combined filters", :js do
    it "applies multiple filters" do
      visit nodes_path

      select "Compute", from: "Role"
      select "Online", from: "Status"

      within("tbody") do
        expect(page).to have_content("compute-001", wait: 5)
        expect(page).not_to have_content("login-001")
        expect(page).not_to have_content("admin-001")
      end
    end
  end

  describe "empty state" do
    it "shows empty state when no nodes match filters" do
      visit nodes_path(q: "nonexistent")

      expect(page).to have_content("No nodes match your filters")
      expect(page).not_to have_content("Build your cluster")
    end
  end
end
