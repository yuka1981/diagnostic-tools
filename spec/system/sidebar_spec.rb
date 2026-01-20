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
        expect(page).to have_button("Rooms")
        expect(page).to have_link("Racks")
      end
    end
  end

  describe "rooms expansion", :js do
    let!(:room1) { create(:room, name: "Server Room A") }
    let!(:room2) { create(:room, name: "Data Center B") }

    before do
      # Clear localStorage to ensure consistent test state (rooms expanded by default)
      visit dashboard_path
      page.execute_script("localStorage.removeItem('sidebarRoomsExpanded')")
      page.execute_script("localStorage.removeItem('sidebarCollapsed')")
      visit dashboard_path
    end

    it "shows rooms list when expanded" do
      within("aside") do
        expect(page).to have_text("Server Room A")
        expect(page).to have_text("Data Center B")
      end
    end

    it "hides rooms list when collapsed" do
      within("aside") do
        click_button "Rooms"

        expect(page).not_to have_text("Server Room A")
        expect(page).not_to have_text("Data Center B")
      end
    end

    it "navigates to room when clicking room name" do
      within("aside") do
        click_link "Server Room A"
      end

      expect(page).to have_current_path(room_path(room1))
    end
  end

  describe "sidebar collapse", :js do
    before do
      # Clear localStorage to ensure consistent test state
      visit dashboard_path
      page.execute_script("localStorage.removeItem('sidebarCollapsed')")
      page.execute_script("localStorage.removeItem('sidebarRoomsExpanded')")
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
  end
end
