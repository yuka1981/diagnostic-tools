# Inventory Sidebar Consolidation Design

## Overview

Consolidate Site, Room, Rack, and Node navigation items into a single collapsible "Inventory" section in the sidebar.

## Current State

The sidebar displays flat navigation under "Organization":
```
Dashboard
Sites
Rooms
Racks
Nodes
Tasks
```

## Proposed Change

Replace individual items with a collapsible "Inventory" parent:
```
Dashboard
▼ Inventory
    Sites
    Rooms
    Racks
    Nodes
Tasks
```

## Benefits

- Cleaner sidebar with logical grouping
- Reflects the physical hierarchy: Site → Room → Rack → Node
- Better scalability as more inventory types are added
- Reduced visual clutter

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Menu style | Collapsible parent | Preserves direct routes, familiar pattern |
| Child items | Sites, Rooms, Racks, Nodes | Complete physical infrastructure |
| Tasks placement | Stays separate | Operational, not inventory |
| Parent click behavior | Toggle only | No `/inventory` page needed |
| State persistence | URL-based auto-expand | Simple, predictable, no localStorage |

## Implementation

### Files to Modify

1. `app/views/shared/_sidebar.html.erb` — Replace individual links with collapsible group
2. `app/javascript/controllers/collapsible_nav_controller.js` — New Stimulus controller

### Sidebar Partial Changes

Replace the four individual navigation links with:

```erb
<%# Inventory collapsible section %>
<% inventory_paths = %w[/sites /rooms /racks /nodes] %>
<% inventory_expanded = inventory_paths.any? { |p| request.path.start_with?(p) } %>

<div data-controller="collapsible-nav"
     data-collapsible-nav-expanded-value="<%= inventory_expanded %>"
     class="space-y-1">

  <button type="button"
          data-action="click->collapsible-nav#toggle"
          class="w-full flex items-center gap-3 px-3 py-2 text-slate-300 hover:bg-slate-700 rounded-lg">
    <%= lucide_icon "chevron-right", class: "w-4 h-4 transition-transform duration-200",
        data: { collapsible_nav_target: "icon" } %>
    <%= lucide_icon "archive", class: "w-5 h-5" %>
    <span>Inventory</span>
  </button>

  <div data-collapsible-nav-target="menu" class="ml-7 space-y-1">
    <%= link_to sites_path, class: "..." do %>
      <%= lucide_icon "building-2", class: "w-5 h-5" %>
      <span>Sites</span>
    <% end %>

    <%= link_to rooms_path, class: "..." do %>
      <%= lucide_icon "warehouse", class: "w-5 h-5" %>
      <span>Rooms</span>
    <% end %>

    <%= link_to server_racks_path, class: "..." do %>
      <%= lucide_icon "server", class: "w-5 h-5" %>
      <span>Racks</span>
    <% end %>

    <%= link_to nodes_path, class: "..." do %>
      <%= lucide_icon "hard-drive", class: "w-5 h-5" %>
      <span>Nodes</span>
    <% end %>
  </div>
</div>
```

### Stimulus Controller

Create `app/javascript/controllers/collapsible_nav_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "icon"]
  static values = { expanded: Boolean }

  connect() {
    this.render()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
  }

  expandedValueChanged() {
    this.render()
  }

  render() {
    // Toggle menu visibility
    this.menuTarget.classList.toggle("hidden", !this.expandedValue)

    // Rotate chevron: right when collapsed, down when expanded
    this.iconTarget.classList.toggle("rotate-90", this.expandedValue)
  }
}
```

### Auto-Expand Logic

The inventory section auto-expands when the current path starts with:
- `/sites`
- `/rooms`
- `/racks`
- `/nodes`

This is determined server-side and passed to the Stimulus controller via the `expanded` value. No localStorage or session state needed.

### Visual Details

- **Parent icon:** `archive` (alternatives: `boxes`, `package`)
- **Chevron:** `chevron-right` rotated 90° when expanded
- **Indentation:** Child items use `ml-7` for visual hierarchy
- **Animation:** `transition-transform duration-200` on chevron rotation

## Routes

No route changes required. Existing routes remain:
- `GET /sites`
- `GET /rooms`
- `GET /racks`
- `GET /nodes`

## Testing

- Verify collapsible toggle works on click
- Verify auto-expand when navigating to child pages
- Verify active state highlighting on child items
- Verify mobile sidebar behavior unchanged
