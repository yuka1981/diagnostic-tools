# Inventory Sidebar Consolidation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Consolidate Site, Room, Rack, and Node navigation items into a collapsible "Inventory" section in the sidebar.

**Architecture:** Modify the sidebar partial to wrap the four navigation links in a collapsible group. Reuse the existing `collapsible_controller.js` with a minor enhancement for chevron rotation. Auto-expand based on current URL path.

**Tech Stack:** Rails 7.2, Hotwire/Stimulus, Tailwind CSS, Lucide icons

---

## Task 1: Enhance Collapsible Controller for Chevron Rotation

The existing `collapsible_controller.js` rotates icons 180° (for down-arrows). We need 90° rotation for right-to-down chevrons.

**Files:**
- Modify: `app/javascript/controllers/collapsible_controller.js`
- Test: Manual browser testing (Stimulus controller)

**Step 1: Add rotation class value**

Open `app/javascript/controllers/collapsible_controller.js` and update:

```javascript
import { Controller } from "@hotwired/stimulus"

// Simple collapsible controller for toggling content visibility
export default class extends Controller {
  static targets = ["content", "icon"]
  static values = {
    open: { type: Boolean, default: false },
    rotateClass: { type: String, default: "rotate-180" }
  }

  connect() {
    this.updateVisibility()
  }

  toggle() {
    this.openValue = !this.openValue
    this.updateVisibility()
  }

  updateVisibility() {
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.openValue)
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle(this.rotateClassValue, this.openValue)
    }
  }
}
```

**Step 2: Verify existing usages still work**

Run: `bin/rspec`
Expected: All tests pass (existing usages default to `rotate-180`)

**Step 3: Commit**

```bash
git add app/javascript/controllers/collapsible_controller.js
git commit -m "feat: add configurable rotation class to collapsible controller"
```

---

## Task 2: Update Sidebar Partial with Collapsible Inventory Section

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb:26-52`

**Step 1: Replace individual links with collapsible group**

Replace lines 26-52 (Sites, Rooms, Racks, Nodes links) with:

```erb
        <%# Inventory collapsible section %>
        <% inventory_paths = %w[/sites /rooms /racks /nodes] %>
        <% inventory_expanded = inventory_paths.any? { |p| request.path.start_with?(p) } %>
        <% inventory_active = inventory_expanded %>

        <div data-controller="collapsible"
             data-collapsible-open-value="<%= inventory_expanded %>"
             data-collapsible-rotate-class-value="rotate-90">

          <%# Inventory toggle button %>
          <button type="button"
                  data-action="click->collapsible#toggle"
                  class="w-full flex items-center gap-3 px-5 py-2 text-sm font-bold rounded transition-colors <%= inventory_active ? 'text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6' %>">
            <%= lucide_icon("chevron-right",
                class: "h-4 w-4 opacity-75 transition-transform duration-200",
                data: { collapsible_target: "icon" }) %>
            <%= lucide_icon("archive", class: "h-5 w-5 opacity-75") %>
            <span>Inventory</span>
          </button>

          <%# Inventory child items %>
          <div data-collapsible-target="content" class="space-y-0.5">
            <%= link_to sites_path,
                data: { turbo_prefetch: false },
                class: "flex items-center gap-3 pl-12 pr-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/sites') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
              <%= lucide_icon("building-2", class: "h-5 w-5 opacity-75") %>
              Sites
            <% end %>

            <%= link_to rooms_path,
                data: { turbo_prefetch: false },
                class: "flex items-center gap-3 pl-12 pr-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/rooms') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
              <%= lucide_icon("warehouse", class: "h-5 w-5 opacity-75") %>
              Rooms
            <% end %>

            <%= link_to server_racks_path,
                data: { turbo_prefetch: false },
                class: "flex items-center gap-3 pl-12 pr-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/racks') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
              <%= lucide_icon("server", class: "h-5 w-5 opacity-75") %>
              Racks
            <% end %>

            <%= link_to nodes_path,
                data: { turbo_prefetch: false },
                class: "flex items-center gap-3 pl-12 pr-5 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/nodes') ? 'bg-primary-1 text-primary-6' : 'hover:bg-neutral-4 hover:text-primary-6'}" do %>
              <%= lucide_icon("hard-drive", class: "h-5 w-5 opacity-75") %>
              Nodes
            <% end %>
          </div>
        </div>
```

**Step 2: Run tests to verify no regressions**

Run: `bin/rspec`
Expected: All tests pass

**Step 3: Run linter**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 4: Commit**

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "feat: consolidate inventory items into collapsible sidebar section

Replaces flat Site, Room, Rack, Node navigation with a collapsible
'Inventory' parent that auto-expands when viewing child pages."
```

---

## Task 3: Manual Verification

**Step 1: Start development server**

Run: `bin/dev`

**Step 2: Verify behaviors**

Test checklist:
- [ ] Visit Dashboard - Inventory section is collapsed
- [ ] Click "Inventory" - Section expands, chevron rotates
- [ ] Click "Inventory" again - Section collapses
- [ ] Visit /sites - Inventory auto-expands, Sites is highlighted
- [ ] Visit /rooms - Inventory stays expanded, Rooms is highlighted
- [ ] Visit /racks - Inventory stays expanded, Racks is highlighted
- [ ] Visit /nodes - Inventory stays expanded, Nodes is highlighted
- [ ] Visit /tasks - Inventory is collapsed
- [ ] Visit /benchmark_runs - Inventory is collapsed

**Step 3: Test mobile sidebar**

- Verify mobile toggle still works
- Verify collapsible works within mobile sidebar

---

## Task 4: Final Quality Check

**Step 1: Run full test suite**

Run: `bin/rspec`
Expected: All tests pass

**Step 2: Run linter**

Run: `bin/rubocop -f github`
Expected: No offenses

**Step 3: Review changes**

Run: `git diff develop`
Review all changes are intentional.

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Enhance collapsible controller | `collapsible_controller.js` |
| 2 | Update sidebar partial | `_sidebar.html.erb` |
| 3 | Manual verification | N/A |
| 4 | Final quality check | N/A |

**Estimated commits:** 2
