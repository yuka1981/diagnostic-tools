# Rack Show Page Redesign

**Date:** 2026-01-20
**Status:** Approved
**Goal:** Redesign the rack show page to make the elevation diagram more prominent and improve information hierarchy with an integrated, interactive view.

## Background

The current rack show page uses a 3-column grid layout where the elevation diagram, details card, and nodes table compete for attention. The elevation diagram should be the visual focus, and clicking nodes in the diagram should connect to the nodes list.

## Design Summary

- **Layout:** Side panel with elevation on left (~300px), nodes list on right
- **Interaction:** Integrated view - clicking node in elevation highlights/expands it in list (and vice versa)
- **Node cards:** Configurable fields stored in user preferences
- **Mobile:** Swipe between elevation and nodes views

---

## Desktop Layout

### Overall Structure

```
┌──────────────────────────────────────────────────────────────┐
│  ← Back to Racks    Rack: R01    Room: DC-1   [Edit][Delete] │
├────────────────────────┬─────────────────────────────────────┤
│                        │                                     │
│   RACK ELEVATION       │   RACK INFO + NODES                 │
│   (~300px, sticky)     │   (flexible width, scrollable)      │
│                        │                                     │
└────────────────────────┴─────────────────────────────────────┘
```

- Left column: Fixed ~300px width, `position: sticky`
- Right column: Remaining width (~60-70%)

### Elevation Panel (Left)

```
┌────────────────────────┐
│  ELEVATION             │
│  [Front] [Rear]        │
├────────────────────────┤
│                        │
│  42 ░░░░░░░░░░░░░░░░░  │
│  41 ░░░░░░░░░░░░░░░░░  │
│  40 ████████████████▓  │  ← selected node has accent border
│  39 ████ Node-01 ███▓  │
│  38 ████████████████▓  │
│  37 ░░░░░░░░░░░░░░░░░  │
│  ...                   │
│   1 ░░░░░░░░░░░░░░░░░  │
├────────────────────────┤
│  ● Online  ○ Offline   │
└────────────────────────┘
```

**Behavior:**
- Clickable nodes - selecting highlights in elevation and scrolls/expands in list
- Hover state with cursor pointer
- Selected state with teal/accent border
- Sticky positioning while scrolling nodes
- ~20px per U height
- Front/Rear toggle via Turbo Frame (existing)

### Right Column

**Summary Bar:**
```
┌─────────────────────────────────────────────────────────────┐
│  U Height: 42  │  Width: 19"  │  Utilization: ████░░░ 24%   │
└─────────────────────────────────────────────────────────────┘
```
- Utilization bar colored: green (0-50%), amber (50-80%), red (>80%)

**Nodes List:**
```
┌─────────────────────────────────────────────────────────────┐
│  NODES IN RACK (3)                                     [⚙]  │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ▶ Node-01                                   U39     4U  ││
│  │   ● Online                          [ View Node → ]     ││
│  │  ───────────────────────────────────────────────────────││
│  │   CPU      2x Intel Xeon 8380 (80 cores)                ││
│  │   RAM      512 GB DDR4-3200                             ││
│  │   Storage  2x 1.92TB NVMe SSD                           ││
│  │   Network  2x 100GbE HDR InfiniBand                     ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │   Node-02                                   U35     2U  ││
│  │   ○ Offline                                             ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**Interaction:**
- Click node card → expands it, collapses others, highlights in elevation
- Click expanded node → collapses, clears selection
- Smooth scroll to selected node

---

## Configurable Fields

**Gear icon dropdown:**
```
┌─────────────────────────┐
│  Show in node preview:  │
│  ─────────────────────  │
│  ☑ CPU                  │
│  ☑ RAM                  │
│  ☑ Storage              │
│  ☑ Network              │
│  ☐ Load                 │
│  ☐ Uptime               │
│  ☐ Last seen            │
│  ☐ OS                   │
│  ☐ Tags                 │
│  ─────────────────────  │
│  [Reset to defaults]    │
└─────────────────────────┘
```

**Data Model:**
```ruby
# users table migration
add_column :users, :rack_node_preview_fields, :string, array: true,
           default: ['cpu', 'ram', 'storage', 'network']
```

**Available Fields:**

| Field | Source |
|-------|--------|
| CPU | `node.cpu_model`, `node.cpu_count` |
| RAM | `node.total_memory` |
| Storage | `node.storage_summary` |
| Network | `node.network_summary` |
| Load | `node.load_average` |
| Uptime | `node.uptime` |
| Last seen | `node.last_seen_at` |
| OS | `node.os_name`, `node.os_version` |
| Tags | `node.tags` |

**API:**
- `PATCH /users/preferences` to save field selections
- Preferences loaded with current_user on page render

---

## Mobile Experience (Swipe Navigation)

**Structure:**
```
┌─────────────────────────┐
│  ← Racks    R01  [Edit] │
├─────────────────────────┤
│                         │
│   (swipeable content)   │
│                         │
├─────────────────────────┤
│        ● ○              │
│   Elevation  Nodes      │
└─────────────────────────┘
```

**View 1 - Elevation:**
- Full-screen elevation diagram
- Front/Rear toggle
- Legend at bottom
- Tap node → swipe to View 2 and highlight

**View 2 - Nodes:**
- Summary bar at top
- Scrollable nodes list with configurable fields
- Gear icon for field settings

**Implementation:**
- Stimulus controller for swipe gestures
- CSS `scroll-snap` for smooth snapping
- Dot indicators show current view

---

## Edge Cases

### Empty Rack
```
┌────────────────────────┬─────────────────────────────────────┐
│  (all empty slots)     │  NO NODES IN RACK                   │
│                        │                                     │
│                        │  This rack is empty. Nodes will     │
│                        │  appear here when assigned to       │
│                        │  this rack with a position.         │
└────────────────────────┴─────────────────────────────────────┘
```

### Unpositioned Nodes
Nodes assigned to rack but without `rack_position` appear in a separate "Unpositioned Nodes" section below the main list. They don't appear in elevation.

### Very Tall Racks (>48U)
- Elevation panel gets internal scroll
- Sticky header with Front/Rear toggle stays visible

### Selection State
- Selection is ephemeral (not persisted)
- Cleared on page navigation

---

## Files to Change

| File | Change |
|------|--------|
| `app/views/equipment_racks/show.html.erb` | New 2-column layout |
| `app/components/rack_elevation_component.rb` | Add click handlers, selection state |
| `app/components/rack_elevation_component.html.erb` | Selection styling, clickable nodes |
| `app/javascript/controllers/rack_show_controller.js` | New controller for integrated view |
| `app/javascript/controllers/swipe_controller.js` | New controller for mobile swipe |
| `db/migrate/xxx_add_rack_node_preview_fields_to_users.rb` | New migration |
| `app/models/user.rb` | Add preference attribute |
| `app/controllers/users_controller.rb` | Add preferences endpoint |
| `spec/system/equipment_racks_spec.rb` | Update tests |

---

## Implementation Notes

1. **Stimulus Controllers:**
   - `rack_show_controller.js` - handles selection sync between elevation and list
   - `swipe_controller.js` - handles mobile swipe navigation

2. **Turbo Frames:**
   - Keep existing Front/Rear toggle frame
   - Node list updates don't need Turbo (client-side only)

3. **CSS:**
   - Use Tailwind's `lg:` breakpoint for desktop/mobile switch
   - `scroll-snap-type: x mandatory` for mobile swipe
   - `position: sticky` for elevation panel

4. **Performance:**
   - Node hardware data may need eager loading
   - Consider caching node summary methods
