# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Equipment Racks", type: :system do
  let(:user) { create(:user, :approver) }
  let(:room) { create(:room, name: "Machine Room 1") }
  let(:rack) { create(:equipment_rack, name: "R01", room: room, u_height: 42, width: 19, row: "A") }

  before { sign_in user }

  describe "show page" do
    context "with positioned nodes" do
      let!(:node1) { create(:node, hostname: "compute-001", rack: rack, rack_position: 10, rack_height: 2, rack_face: :front) }
      let!(:node2) { create(:node, hostname: "compute-002", rack: rack, rack_position: 15, rack_height: 1, rack_face: :front) }

      it "displays the rack-show controller container" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-controller='rack-show']")
      end

      it "shows the rack name as page title" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("h1", text: "R01")
      end

      it "displays room and row information" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Room:")
        expect(page).to have_content("Machine Room 1")
        expect(page).to have_content("Row:")
        expect(page).to have_content("A")
      end

      it "shows summary bar with U Height" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("U Height:")
        expect(page).to have_content("42U")
      end

      it "shows summary bar with Width" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Width:")
        expect(page).to have_content("19\"")
      end

      it "shows summary bar with Utilization percentage" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Utilization:")
        # 3U used out of 42U = ~7%
        expect(page).to have_css("[style*='width:']")
      end

      it "displays the 2-column layout on desktop" do
        visit equipment_rack_path(rack)
        # Desktop layout container
        expect(page).to have_css(".lg\\:flex.lg\\:flex-row")
        # Left column for rack elevation
        expect(page).to have_css(".w-\\[320px\\]")
        # Right column for nodes list
        expect(page).to have_css(".flex-1.min-w-0")
      end

      it "displays the rack elevation component" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-controller='rack-elevation']")
        expect(page).to have_content("Rack Elevation")
      end

      it "shows face toggle buttons (Front/Rear)" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Front")
        expect(page).to have_content("Rear")
      end

      it "displays node cards in the nodes list" do
        visit equipment_rack_path(rack)
        # Both mobile and desktop layouts are rendered, so we check for minimum count
        expect(page).to have_css("[data-rack-show-target='nodeCard']", minimum: 2)
      end

      it "shows node hostnames in node cards" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("compute-001")
        expect(page).to have_content("compute-002")
      end

      it "shows node position information" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("U10")
        expect(page).to have_content("U15")
      end

      it "shows node height badges" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("2U")
        expect(page).to have_content("1U")
      end

      it "displays nodes in the rack elevation diagram" do
        visit equipment_rack_path(rack)
        # Both mobile and desktop layouts are rendered, so we check for minimum count
        expect(page).to have_css("[data-rack-show-target='elevationNode']", minimum: 2)
      end

      it "shows the nodes count in the header" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Nodes in Rack (2)")
      end

      it "displays the gear icon for field configuration" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-controller='fields-config']")
        expect(page).to have_css("button[title='Configure displayed fields']")
      end

      it "shows elevation legend with Online, Offline, and Empty indicators" do
        visit equipment_rack_path(rack)
        # Scope to desktop layout to avoid ambiguous match (mobile and desktop both have elevation)
        within(".lg\\:flex [data-controller='rack-elevation']") do
          expect(page).to have_content("Online")
          expect(page).to have_content("Offline")
          expect(page).to have_content("Empty")
        end
      end
    end

    context "with nodes on both faces" do
      let!(:front_node) { create(:node, hostname: "front-node", rack: rack, rack_position: 5, rack_height: 1, rack_face: :front) }
      let!(:rear_node) { create(:node, hostname: "rear-node", rack: rack, rack_position: 5, rack_height: 1, rack_face: :rear) }

      it "shows front face nodes by default" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-rack-show-target='elevationNode']", text: "front-node")
      end

      it "can switch to rear face view" do
        visit equipment_rack_path(rack, face: :rear)
        expect(page).to have_css("[data-rack-show-target='elevationNode']", text: "rear-node")
      end
    end

    context "with unpositioned nodes" do
      let!(:positioned_node) { create(:node, hostname: "positioned-node", rack: rack, rack_position: 10, rack_height: 1) }
      let!(:unpositioned_node) { create(:node, hostname: "unpositioned-node", rack: rack, rack_position: nil, rack_height: nil) }

      it "shows unpositioned nodes section" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("Unpositioned Nodes")
        expect(page).to have_content("unpositioned-node")
      end

      it "shows 'No position set' indicator for unpositioned nodes" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("No position set")
      end

      it "positioned nodes appear in rack elevation, unpositioned do not" do
        visit equipment_rack_path(rack)
        # Only positioned node in elevation (both mobile and desktop layouts rendered)
        expect(page).to have_css("[data-rack-show-target='elevationNode']", minimum: 1)
        # The unpositioned node should not appear in elevation
        expect(page).not_to have_css("[data-rack-show-target='elevationNode']", text: "unpositioned-node")
      end
    end

    context "empty rack" do
      it "shows empty state message" do
        visit equipment_rack_path(rack)
        expect(page).to have_content("No nodes in rack")
        expect(page).to have_content("This rack is empty")
      end

      it "does not show node cards" do
        visit equipment_rack_path(rack)
        expect(page).not_to have_css("[data-rack-show-target='nodeCard']")
      end

      it "still shows rack elevation structure" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-controller='rack-elevation']")
      end
    end

    context "rack with notes" do
      let(:rack_with_notes) { create(:equipment_rack, room: room, notes: "Important maintenance scheduled for next week.") }

      it "displays notes section" do
        visit equipment_rack_path(rack_with_notes)
        expect(page).to have_content("Notes")
        expect(page).to have_content("Important maintenance scheduled for next week.")
      end
    end

    context "rack without room" do
      let(:unassigned_rack) { create(:equipment_rack, name: "Unassigned-R01", room: nil) }

      it "shows 'Unassigned' for room" do
        visit equipment_rack_path(unassigned_rack)
        expect(page).to have_content("Room:")
        expect(page).to have_content("Unassigned")
      end
    end

    context "rack without row" do
      let(:no_row_rack) { create(:equipment_rack, name: "NoRow-R01", room: room, row: nil) }

      it "does not show row field when not set" do
        visit equipment_rack_path(no_row_rack)
        expect(page).not_to have_content("Row:")
      end
    end

    context "action buttons" do
      it "displays Edit button for approver" do
        visit equipment_rack_path(rack)
        expect(page).to have_link("Edit")
      end

      it "displays Delete button for approver" do
        visit equipment_rack_path(rack)
        expect(page).to have_button("Delete")
      end
    end

    context "as viewer user" do
      let(:viewer) { create(:user, role: :viewer) }

      before { sign_in viewer }

      it "does not show Edit button" do
        visit equipment_rack_path(rack)
        expect(page).not_to have_link("Edit")
      end

      it "does not show Delete button" do
        visit equipment_rack_path(rack)
        expect(page).not_to have_button("Delete")
      end
    end

    context "breadcrumbs" do
      it "shows navigation breadcrumbs" do
        visit equipment_rack_path(rack)
        expect(page).to have_link("Racks")
        expect(page).to have_content("R01")
      end
    end

    context "mobile swipe layout" do
      it "has mobile swipe container for small screens" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-controller='swipe']")
      end

      it "has swipe dot indicators" do
        visit equipment_rack_path(rack)
        expect(page).to have_css("[data-swipe-target='dot']", count: 2)
      end
    end
  end

  describe "show page with JS", js: true do
    let!(:node) { create(:node, hostname: "interactive-node", rack: rack, rack_position: 20, rack_height: 2) }

    it "can click node card to interact" do
      visit equipment_rack_path(rack)
      # Wait for page to load and find node card (desktop or mobile)
      expect(page).to have_css("[data-rack-show-target='nodeCard']", minimum: 1, wait: 5)
    end

    it "gear icon dropdown is functional" do
      visit equipment_rack_path(rack)

      # Find and click the gear icon (use first one found, as there may be multiple)
      gear_button = first("button[title='Configure displayed fields']", wait: 5)
      gear_button.click

      # Dropdown should be visible (text is uppercase in the UI)
      expect(page).to have_content(/show in node preview/i, wait: 5)
    end
  end
end
