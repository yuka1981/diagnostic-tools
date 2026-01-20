# Sidebar Navigation Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement collapsible sidebar with expandable Rooms section and localStorage persistence.

**Architecture:** Enhance existing Stimulus sidebar_controller to handle desktop collapse/expand and section toggling. All state persisted via localStorage. Sidebar width changes from w-64 (expanded) to w-16 (collapsed) with smooth transitions.

**Tech Stack:** Rails 7.2, Stimulus.js, Tailwind CSS, localStorage

---

## Task 1: Create SidebarHelper for Rooms Data

**Files:**
- Create: `app/helpers/sidebar_helper.rb`
- Modify: `app/helpers/application_helper.rb:1-3`
- Test: `spec/helpers/sidebar_helper_spec.rb`

**Step 1: Write the failing test**

Create `spec/helpers/sidebar_helper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SidebarHelper, type: :helper do
  describe "#sidebar_rooms" do
    it "returns all rooms ordered by name" do
      room_b = create(:room, name: "Server Room B")
      room_a = create(:room, name: "Data Center A")

      result = helper.sidebar_rooms

      expect(result.map(&:name)).to eq([ "Data Center A", "Server Room B" ])
    end

    it "returns empty array when no rooms exist" do
      expect(helper.sidebar_rooms).to eq([])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/helpers/sidebar_helper_spec.rb -v`
Expected: FAIL with "uninitialized constant SidebarHelper"

**Step 3: Write minimal implementation**

Create `app/helpers/sidebar_helper.rb`:

```ruby
# frozen_string_literal: true

module SidebarHelper
  def sidebar_rooms
    Room.order(:name)
  end
end
```

**Step 4: Include helper in ApplicationHelper**

Modify `app/helpers/application_helper.rb` - add after line 2:

```ruby
module ApplicationHelper
  include DashboardHelper
  include SidebarHelper
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/helpers/sidebar_helper_spec.rb -v`
Expected: PASS

**Step 6: Run RuboCop**

Run: `bin/rubocop app/helpers/sidebar_helper.rb spec/helpers/sidebar_helper_spec.rb`
Expected: No offenses

**Step 7: Commit**

```bash
git add app/helpers/sidebar_helper.rb spec/helpers/sidebar_helper_spec.rb app/helpers/application_helper.rb
git commit -m "feat(sidebar): add SidebarHelper with sidebar_rooms method"
```

---

## Task 2: Enhance Stimulus Sidebar Controller

**Files:**
- Modify: `app/javascript/controllers/sidebar_controller.js`
- Test: Manual testing (system specs in later task)

**Step 1: Review current controller**

Current controller only handles mobile toggle. We need to add:
- Desktop collapse/expand with localStorage persistence
- Section expand/collapse (for Rooms)
- Target management for UI elements

**Step 2: Rewrite sidebar controller**

Replace `app/javascript/controllers/sidebar_controller.js` with:

```javascript
import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
// Handles:
// - Mobile sidebar toggle (existing)
// - Desktop sidebar collapse/expand (new)
// - Expandable sections like Rooms (new)
// - State persistence via localStorage (new)
export default class extends Controller {
  static targets = [
    "menu",
    "overlay",
    "content",
    "collapseIcon",
    "label",
    "sectionHeader",
    "roomsList",
    "roomsChevron",
    "brandText",
    "userInfo"
  ]

  static values = {
    collapsed: { type: Boolean, default: false },
    roomsExpanded: { type: Boolean, default: true }
  }

  connect() {
    this.loadState()
    this.applyState()
  }

  // Mobile toggle (existing functionality)
  toggle() {
    this.menuTarget.classList.toggle("translate-x-0")
    this.menuTarget.classList.toggle("-translate-x-full")
    this.overlayTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.remove("translate-x-0")
    this.menuTarget.classList.add("-translate-x-full")
    this.overlayTarget.classList.add("hidden")
  }

  // Desktop collapse/expand
  toggleCollapse() {
    this.collapsedValue = !this.collapsedValue
    this.saveState()
    this.applyState()
  }

  // Rooms section expand/collapse
  toggleRooms() {
    if (this.collapsedValue) return // Don't toggle when sidebar collapsed
    this.roomsExpandedValue = !this.roomsExpandedValue
    this.saveState()
    this.applyRoomsState()
  }

  // Load state from localStorage
  loadState() {
    const collapsed = localStorage.getItem("sidebarCollapsed")
    const roomsExpanded = localStorage.getItem("sidebarRoomsExpanded")

    if (collapsed !== null) {
      this.collapsedValue = collapsed === "true"
    }
    if (roomsExpanded !== null) {
      this.roomsExpandedValue = roomsExpanded === "true"
    }
  }

  // Save state to localStorage
  saveState() {
    localStorage.setItem("sidebarCollapsed", this.collapsedValue)
    localStorage.setItem("sidebarRoomsExpanded", this.roomsExpandedValue)
  }

  // Apply collapsed/expanded state to UI
  applyState() {
    const menu = this.menuTarget

    if (this.collapsedValue) {
      // Collapse: w-16, hide labels
      menu.classList.remove("w-64")
      menu.classList.add("w-16")

      if (this.hasContentTarget) {
        this.contentTarget.classList.remove("lg:pl-64")
        this.contentTarget.classList.add("lg:pl-16")
      }

      // Hide text elements
      this.labelTargets.forEach(el => el.classList.add("hidden"))
      this.sectionHeaderTargets.forEach(el => el.classList.add("hidden"))
      if (this.hasBrandTextTarget) this.brandTextTarget.classList.add("hidden")
      if (this.hasUserInfoTarget) this.userInfoTarget.classList.add("hidden")

      // Update collapse icon to show expand arrow
      if (this.hasCollapseIconTarget) {
        this.collapseIconTarget.classList.remove("rotate-180")
      }

      // Hide rooms list when collapsed
      if (this.hasRoomsListTarget) {
        this.roomsListTarget.classList.add("hidden")
      }
    } else {
      // Expand: w-64, show labels
      menu.classList.remove("w-16")
      menu.classList.add("w-64")

      if (this.hasContentTarget) {
        this.contentTarget.classList.remove("lg:pl-16")
        this.contentTarget.classList.add("lg:pl-64")
      }

      // Show text elements
      this.labelTargets.forEach(el => el.classList.remove("hidden"))
      this.sectionHeaderTargets.forEach(el => el.classList.remove("hidden"))
      if (this.hasBrandTextTarget) this.brandTextTarget.classList.remove("hidden")
      if (this.hasUserInfoTarget) this.userInfoTarget.classList.remove("hidden")

      // Update collapse icon to show collapse arrow
      if (this.hasCollapseIconTarget) {
        this.collapseIconTarget.classList.add("rotate-180")
      }

      // Apply rooms state
      this.applyRoomsState()
    }
  }

  // Apply rooms section expanded/collapsed state
  applyRoomsState() {
    if (!this.hasRoomsListTarget || !this.hasRoomsChevronTarget) return

    if (this.roomsExpandedValue && !this.collapsedValue) {
      this.roomsListTarget.classList.remove("hidden")
      this.roomsChevronTarget.classList.add("rotate-90")
    } else {
      this.roomsListTarget.classList.add("hidden")
      this.roomsChevronTarget.classList.remove("rotate-90")
    }
  }
}
```

**Step 3: Verify no syntax errors**

Run: `npx eslint app/javascript/controllers/sidebar_controller.js` (if eslint configured) or just check browser console after deploy.

**Step 4: Commit**

```bash
git add app/javascript/controllers/sidebar_controller.js
git commit -m "feat(sidebar): enhance controller with collapse and section toggle"
```

---

## Task 3: Update Sidebar Template

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Rewrite sidebar template**

Replace entire content of `app/views/shared/_sidebar.html.erb`:

```erb
<aside class="fixed inset-y-0 left-0 z-50 w-64 bg-slate-900 text-slate-300 flex flex-col transition-all duration-300 ease-in-out lg:translate-x-0"
       data-sidebar-target="menu">

  <%# Brand %>
  <div class="flex h-14 items-center px-4 border-b border-slate-800 bg-slate-900">
    <div class="flex items-center gap-3">
      <div class="flex h-8 w-8 items-center justify-center rounded bg-teal-600 text-white shadow-sm flex-shrink-0">
        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
        </svg>
      </div>
      <span class="text-base font-bold text-white tracking-tight" data-sidebar-target="brandText">HPC Diagnostics</span>
    </div>
  </div>

  <%# Navigation %>
  <nav class="flex-1 overflow-y-auto px-2 py-4 space-y-6 text-slate-400">

    <%# Organization %>
    <div>
      <h3 class="px-3 text-xs font-bold text-slate-500 uppercase tracking-wider mb-1" data-sidebar-target="sectionHeader">Organization</h3>
      <div class="space-y-0.5">
        <%= render "shared/sidebar_link", path: dashboard_path, label: "Dashboard", icon: "dashboard" %>
      </div>
    </div>

    <%# Inventory %>
    <div>
      <h3 class="px-3 text-xs font-bold text-slate-500 uppercase tracking-wider mb-1" data-sidebar-target="sectionHeader">Inventory</h3>
      <div class="space-y-0.5">
        <%= render "shared/sidebar_link", path: nodes_path, label: "Nodes", icon: "nodes" %>

        <%# Rooms - Expandable %>
        <div class="relative">
          <%# Rooms header (clickable to expand) %>
          <button type="button"
                  data-action="click->sidebar#toggleRooms"
                  class="w-full flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors <%= request.path.start_with?('/rooms') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400' %> group">
            <svg class="h-5 w-5 opacity-75 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
            </svg>
            <span data-sidebar-target="label" class="flex-1 text-left">Rooms</span>
            <svg class="h-4 w-4 transition-transform duration-200" data-sidebar-target="roomsChevron" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
            </svg>
          </button>

          <%# Tooltip for collapsed state %>
          <div class="hidden absolute left-full top-1/2 -translate-y-1/2 ml-2 px-2 py-1 bg-slate-800 text-white text-xs rounded whitespace-nowrap opacity-0 group-hover:opacity-100 pointer-events-none z-50">
            Rooms
          </div>

          <%# Rooms sub-list %>
          <div data-sidebar-target="roomsList" class="mt-1 ml-8 space-y-0.5">
            <% sidebar_rooms.each do |room| %>
              <%= link_to room_path(room),
                  class: "block px-3 py-1.5 text-sm rounded transition-colors #{current_page?(room_path(room)) ? 'text-teal-400 bg-slate-800/50' : 'text-slate-400 hover:text-teal-400 hover:bg-slate-800/50'}" do %>
                <%= room.name %>
              <% end %>
            <% end %>
            <% if sidebar_rooms.empty? %>
              <span class="block px-3 py-1.5 text-xs text-slate-500 italic">No rooms</span>
            <% end %>
          </div>
        </div>

        <%= render "shared/sidebar_link", path: equipment_racks_path, label: "Racks", icon: "racks" %>
      </div>
    </div>

    <%# Benchmarks %>
    <div>
      <h3 class="px-3 text-xs font-bold text-slate-500 uppercase tracking-wider mb-1" data-sidebar-target="sectionHeader">Benchmarks</h3>
      <div class="space-y-0.5">
        <%= render "shared/sidebar_link", path: benchmark_runs_path, label: "Benchmark Runs", icon: "benchmark_runs" %>
        <%= render "shared/sidebar_link", path: benchmark_recipes_path, label: "Recipes", icon: "recipes" %>
      </div>
    </div>

    <%# Admin %>
    <% if current_user&.approver? %>
      <div>
        <h3 class="px-3 text-xs font-bold text-slate-500 uppercase tracking-wider mb-1" data-sidebar-target="sectionHeader">Admin</h3>
        <div class="space-y-0.5">
          <%= render "shared/sidebar_link", path: api_keys_path, label: "API Keys", icon: "api_keys" %>
          <%= render "shared/sidebar_link", path: settings_ssh_path, label: "SSH Settings", icon: "ssh" %>
          <%= render "shared/sidebar_link", path: settings_agent_path, label: "Agent Config", icon: "settings" %>
        </div>
      </div>
    <% end %>
  </nav>

  <%# Footer %>
  <div class="border-t border-slate-800">
    <% if current_user %>
      <div class="p-4">
        <div class="flex items-center gap-3">
          <div class="h-8 w-8 rounded-full bg-slate-700 flex items-center justify-center text-sm font-medium text-white flex-shrink-0">
            <%= current_user.name&.first&.upcase || current_user.email.first.upcase %>
          </div>
          <div class="flex-1 min-w-0" data-sidebar-target="userInfo">
            <p class="text-sm font-medium text-white truncate"><%= current_user.name || current_user.email %></p>
            <p class="text-xs text-slate-500 truncate"><%= current_user.role.humanize %></p>
          </div>
        </div>
        <div data-sidebar-target="label">
          <%= link_to destroy_user_session_path,
              data: { turbo_method: :delete },
              class: "mt-3 flex items-center gap-2 text-xs text-slate-500 hover:text-slate-300 transition-colors" do %>
            <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
            </svg>
            Sign out
          <% end %>
        </div>
      </div>
    <% else %>
      <div class="p-4">
        <%= link_to new_user_session_path, class: "flex items-center gap-2 text-sm text-slate-500 hover:text-white transition-colors" do %>
          <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 16l-4-4m0 0l4-4m-4 4h14m-5 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          <span data-sidebar-target="label">Sign in</span>
        <% end %>
      </div>
    <% end %>

    <%# Collapse toggle button %>
    <div class="border-t border-slate-800 p-2">
      <button type="button"
              data-action="click->sidebar#toggleCollapse"
              class="w-full flex items-center justify-center gap-2 px-3 py-2 text-xs text-slate-500 hover:text-slate-300 hover:bg-slate-800 rounded transition-colors">
        <svg class="h-4 w-4 rotate-180 transition-transform duration-200" data-sidebar-target="collapseIcon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 19l-7-7 7-7m8 14l-7-7 7-7" />
        </svg>
        <span data-sidebar-target="label">Collapse</span>
      </button>
    </div>
  </div>
</aside>
```

**Step 2: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat(sidebar): update template with collapse and rooms expansion"
```

---

## Task 4: Create Sidebar Link Partial

**Files:**
- Create: `app/views/shared/_sidebar_link.html.erb`

**Step 1: Create the partial**

Create `app/views/shared/_sidebar_link.html.erb`:

```erb
<%# Sidebar navigation link
    locals: path, label, icon %>
<%
  icons = {
    "dashboard" => "M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z",
    "nodes" => "M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01",
    "rooms" => "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
    "racks" => "M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4",
    "benchmark_runs" => "M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z",
    "recipes" => "M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z",
    "api_keys" => "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 012.93-.707l5.964-5.964A6 6 0 1121 9z",
    "ssh" => "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
    "settings" => "M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
  }
  icon_path = icons[icon] || icons["dashboard"]

  # Determine if link is active
  is_active = case icon
              when "dashboard" then current_page?(path)
              when "nodes" then request.path.start_with?('/nodes')
              when "racks" then request.path.start_with?('/racks')
              when "rooms" then request.path.start_with?('/rooms')
              when "benchmark_runs" then request.path.start_with?('/benchmark_runs')
              when "recipes" then request.path.start_with?('/benchmark_recipes')
              when "api_keys" then request.path.start_with?('/api_keys')
              when "ssh" then request.path.start_with?('/settings/ssh')
              when "settings" then request.path.start_with?('/settings/agent')
              else current_page?(path)
              end
%>

<%= link_to path,
    class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors group relative #{is_active ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
  <svg class="h-5 w-5 opacity-75 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="<%= icon_path %>" />
  </svg>
  <span data-sidebar-target="label"><%= label %></span>

  <%# Tooltip for collapsed state %>
  <span class="absolute left-full top-1/2 -translate-y-1/2 ml-2 px-2 py-1 bg-slate-800 text-white text-xs rounded whitespace-nowrap opacity-0 group-hover:opacity-100 pointer-events-none z-50 hidden"
        data-sidebar-target="tooltip">
    <%= label %>
  </span>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/shared/_sidebar_link.html.erb
git commit -m "feat(sidebar): add sidebar_link partial for DRY navigation links"
```

---

## Task 5: Update Dashboard Layout

**Files:**
- Modify: `app/views/layouts/dashboard.html.erb`

**Step 1: Update layout with content target**

Modify `app/views/layouts/dashboard.html.erb` to add the content target and transition classes.

Change line 32 from:
```erb
<div class="lg:pl-64 flex flex-col min-h-screen">
```

To:
```erb
<div class="lg:pl-64 flex flex-col min-h-screen transition-all duration-300 ease-in-out" data-sidebar-target="content">
```

**Step 2: Commit**

```bash
git add app/views/layouts/dashboard.html.erb
git commit -m "feat(sidebar): add content target for sidebar collapse"
```

---

## Task 6: Add System Spec for Sidebar Behavior

**Files:**
- Create: `spec/system/sidebar_spec.rb`

**Step 1: Write system spec**

Create `spec/system/sidebar_spec.rb`:

```ruby
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

  describe "rooms expansion", js: true do
    let!(:room1) { create(:room, name: "Server Room A") }
    let!(:room2) { create(:room, name: "Data Center B") }

    it "shows rooms list when expanded" do
      visit dashboard_path

      within("aside") do
        expect(page).to have_text("Server Room A")
        expect(page).to have_text("Data Center B")
      end
    end

    it "hides rooms list when collapsed" do
      visit dashboard_path

      within("aside") do
        click_button "Rooms"

        expect(page).not_to have_text("Server Room A")
        expect(page).not_to have_text("Data Center B")
      end
    end

    it "navigates to room when clicking room name" do
      visit dashboard_path

      within("aside") do
        click_link "Server Room A"
      end

      expect(page).to have_current_path(room_path(room1))
    end
  end

  describe "sidebar collapse", js: true do
    it "collapses sidebar when clicking collapse button" do
      visit dashboard_path

      within("aside") do
        click_button "Collapse"
      end

      # Sidebar should be narrow
      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-16")
      expect(sidebar[:class]).not_to include("w-64")
    end

    it "expands sidebar when clicking expand button" do
      visit dashboard_path

      # First collapse
      within("aside") do
        click_button "Collapse"
      end

      # Then expand
      within("aside") do
        find("button[data-action='click->sidebar#toggleCollapse']").click
      end

      sidebar = find("aside")
      expect(sidebar[:class]).to include("w-64")
      expect(sidebar[:class]).not_to include("w-16")
    end
  end
end
```

**Step 2: Run test to verify it passes**

Run: `bin/rspec spec/system/sidebar_spec.rb -v`
Expected: All tests pass

**Step 3: Commit**

```bash
git add spec/system/sidebar_spec.rb
git commit -m "test(sidebar): add system specs for collapse and rooms expansion"
```

---

## Task 7: Final Verification and Cleanup

**Step 1: Run full test suite**

Run: `bin/rspec`
Expected: All tests pass

**Step 2: Run RuboCop**

Run: `bin/rubocop`
Expected: No offenses

**Step 3: Manual testing**

1. Start dev server: `bin/dev`
2. Navigate to dashboard
3. Test collapse button - sidebar should collapse to icons only
4. Test expand button - sidebar should expand back
5. Refresh page - state should persist
6. Test Rooms expand/collapse - room list should show/hide
7. Click room name - should navigate to room detail
8. Test on mobile viewport - hamburger menu should still work

**Step 4: Final commit**

If any fixes needed, commit them:

```bash
git add -A
git commit -m "fix(sidebar): address any issues from manual testing"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | SidebarHelper for rooms data | helper + spec |
| 2 | Enhance Stimulus controller | sidebar_controller.js |
| 3 | Update sidebar template | _sidebar.html.erb |
| 4 | Create sidebar link partial | _sidebar_link.html.erb |
| 5 | Update dashboard layout | dashboard.html.erb |
| 6 | System specs | sidebar_spec.rb |
| 7 | Final verification | manual testing |

**Dependencies:** Task 1 must complete before Task 3. Tasks 2-5 can be done in any order but all must complete before Task 6.
