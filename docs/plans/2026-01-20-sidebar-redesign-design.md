# Sidebar Navigation Redesign - Design Document

## Overview

Redesign the side navigation to support:
1. Manual collapse/expand (default: expanded)
2. Expandable "Rooms" section showing individual rooms
3. State persistence via localStorage

## Requirements Summary

| Feature | Decision |
|---------|----------|
| Naming | Keep "Rooms" (not "Labs") |
| Rooms behavior | Click toggles expand/collapse to show room list |
| Collapsed display | Icons only (~64px width), tooltip on hover |
| Toggle position | Bottom of sidebar, near user profile |
| State persistence | localStorage |
| Room sub-items | Simple indented list, click navigates to room detail |

## Layout

### Expanded State (256px / w-64)

```
+-----------------------------+
| [Icon] HPC Diagnostics      |  <- Brand header
+-----------------------------+
| ORGANIZATION                |
|   Dashboard                 |
+-----------------------------+
| INVENTORY                   |
|   Nodes                     |
|   v Rooms  <----------------+-- Expandable (chevron rotates)
|      - Server Room A        |   <- Indented sub-items
|      - Data Center B        |
|   Racks                     |
+-----------------------------+
| BENCHMARKS                  |
|   Benchmark Runs            |
|   Recipes                   |
+-----------------------------+
| ADMIN                       |
|   API Keys                  |
|   SSH Settings              |
|   Agent Config              |
+-----------------------------+
| [Avatar] User Name          |
| Sign out                    |
| ---------------------------+
| [<<] Collapse sidebar       |  <- Collapse button
+-----------------------------+
```

### Collapsed State (64px / w-16)

```
+--------+
| [Icon] |  <- Brand icon only
+--------+
|   *    |  <- Dashboard
+--------+
|   *    |  <- Nodes
|   *    |  <- Rooms (no expand when collapsed)
|   *    |  <- Racks
+--------+
|   *    |  <- Benchmark Runs
|   *    |  <- Recipes
+--------+
|  [A]   |  <- Avatar initial
|  [>>]  |  <- Expand button
+--------+
```

### Behaviors

- **Expanded sidebar:**
  - Click "Rooms" label/chevron toggles sub-item list
  - Chevron rotates 90deg when expanded
  - Sub-items are indented, clicking navigates to room detail

- **Collapsed sidebar:**
  - No section headers visible
  - Hover on icon shows tooltip with label
  - Click Rooms icon navigates to Rooms index (no sub-items)
  - Click expand button returns to expanded state

- **Main content area:**
  - `lg:pl-64` when expanded
  - `lg:pl-16` when collapsed
  - Smooth transition

## Technical Design

### Stimulus Controller

**Controller:** `sidebar_controller.js`

**Targets:**
- `menu` - the aside element
- `content` - main content wrapper
- `collapseBtn` - collapse/expand button
- `expandableHeader` - clickable header for expandable sections
- `expandableList` - the collapsible list of sub-items
- `expandChevron` - chevron icon that rotates
- `label` - text labels hidden when collapsed
- `sectionHeader` - section headers hidden when collapsed

**Values:**
- `collapsed` (Boolean) - sidebar collapsed state
- `roomsExpanded` (Boolean) - rooms section expanded state

**Actions:**
- `toggleCollapse()` - toggle sidebar collapsed state
- `toggleRooms()` - toggle rooms section expanded state

**LocalStorage keys:**
- `sidebarCollapsed` - "true" or "false"
- `sidebarRoomsExpanded` - "true" or "false"

### Files to Modify

| File | Changes |
|------|---------|
| `app/views/shared/_sidebar.html.erb` | Complete restructure with data attributes, expandable Rooms, collapse button |
| `app/javascript/controllers/sidebar_controller.js` | Add collapse/expand logic, section toggle, localStorage |
| `app/views/layouts/dashboard.html.erb` | Dynamic `pl-64`/`pl-16` class, data attributes for content target |
| `app/helpers/sidebar_helper.rb` | New helper to provide rooms list for sidebar |
| `app/controllers/application_controller.rb` | Include SidebarHelper |

### CSS Approach

Use Tailwind classes with transitions:
- `transition-all duration-300 ease-in-out` for smooth width changes
- `group` and `group-hover:` for tooltips
- `rotate-90` for chevron animation
- No custom CSS file needed

### Data Flow

1. On page load, Stimulus controller reads localStorage
2. Controller applies initial state (collapsed/expanded, rooms expanded/collapsed)
3. User interactions update state and localStorage
4. State persists across page navigations and sessions

## Edge Cases

- No rooms in database: Show "No rooms" text or hide expand functionality
- Many rooms (10+): List scrolls within sidebar (existing `overflow-y-auto`)
- Mobile: Collapsed state not applicable (full sidebar or hidden)

## Testing

### Manual Testing
1. Click collapse button -> sidebar collapses to icon-only
2. Hover icons -> tooltips appear
3. Click expand button -> sidebar returns to full width
4. Refresh page -> state persists
5. Click Rooms chevron -> sub-items appear/disappear
6. Click room sub-item -> navigates to room detail

### Automated Testing
- System spec for sidebar collapse/expand behavior
- Helper spec for `sidebar_rooms` method
