# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidebar", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "navigation" do
    it "displays sidebar with navigation links" do
      visit dashboard_path

      within("aside") do
        expect(page).to have_link("Dashboard")
        expect(page).to have_link("Nodes")
        expect(page).to have_link("Rooms")
        expect(page).to have_link("Racks")
      end
    end

    it "clicking Rooms navigates to rooms index" do
      visit dashboard_path

      within("aside") do
        click_link "Rooms"
      end

      expect(page).to have_current_path(rooms_path)
    end
  end

  describe "sidebar collapse", :js do
    before do
      # Clear localStorage to ensure consistent test state
      visit dashboard_path
      page.execute_script("localStorage.removeItem('sidebarCollapsed')")
      visit dashboard_path
    end

    it "collapses sidebar when clicking collapse button" do
      within("aside") do
        click_button "Collapse"
      end

      # Sidebar should be narrow
      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-16")
      expect(sidebar[:class]).not_to include("w-64")
    end

    it "expands sidebar when clicking expand button" do
      # First collapse
      within("aside") do
        click_button "Collapse"
      end

      # Wait for collapse to complete
      expect(find("aside")[:class]).to include("w-16")

      # Then expand by clicking the same button (which is now just an icon)
      within("aside") do
        find("button[data-action='click->sidebar#toggleCollapse']").click
      end

      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-64")
      expect(sidebar[:class]).not_to include("w-16")
    end

    it "shows collapse icon pointing left (<<) when sidebar is expanded" do
      visit dashboard_path

      # Clear localStorage to ensure expanded state
      page.execute_script("localStorage.removeItem('sidebarCollapsed')")
      visit dashboard_path

      # Sidebar should be expanded (w-64)
      expect(find("aside")[:class]).to include("w-64")

      # Collapse icon should NOT have rotate-180 (pointing left <<)
      collapse_icon = find("svg[data-sidebar-target='collapseIcon']")
      expect(collapse_icon[:class]).not_to include("rotate-180")
    end

    it "shows expand icon pointing right (>>) when sidebar is collapsed" do
      visit dashboard_path

      # Collapse the sidebar
      within("aside") do
        click_button "Collapse"
      end

      # Wait for collapse
      expect(find("aside")[:class]).to include("w-16")

      # Collapse icon should have rotate-180 (pointing right >>)
      collapse_icon = find("svg[data-sidebar-target='collapseIcon']")
      expect(collapse_icon[:class]).to include("rotate-180")
    end

    it "renders sidebar collapsed on page load when cookie indicates collapsed state" do
      # Visit first to establish the domain, then set cookie via JS
      visit dashboard_path
      page.execute_script("document.cookie = 'sidebar_collapsed=true; path=/'")

      # Revisit to test server-side rendering with cookie
      visit dashboard_path

      # Sidebar should be rendered with w-16 (collapsed) from server-side
      # without needing JavaScript to fix it
      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-16")
      expect(sidebar[:class]).not_to include("w-64")
    end

    it "renders sidebar expanded on page load when cookie indicates expanded state" do
      # Visit first to establish the domain, then set cookie via JS
      visit dashboard_path
      page.execute_script("document.cookie = 'sidebar_collapsed=false; path=/'")

      # Revisit to test server-side rendering with cookie
      visit dashboard_path

      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-64")
      expect(sidebar[:class]).not_to include("w-16")
    end

    it "does not flash expanded sidebar when navigating while collapsed" do
      # Visit first to establish the domain, then set cookie via JS
      visit dashboard_path
      page.execute_script("document.cookie = 'sidebar_collapsed=true; path=/'")

      # Revisit with cookie set
      visit dashboard_path

      # Verify sidebar is collapsed
      expect(find("aside")[:class]).to include("w-16")

      # Click Rooms link to navigate
      within("aside") do
        click_link "Rooms"
      end

      # Should navigate to rooms index
      expect(page).to have_current_path(rooms_path)

      # Sidebar should still be collapsed (rendered from cookie, no flash)
      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-16")
      expect(sidebar[:class]).not_to include("w-64")
    end
  end
end
