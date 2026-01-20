# Remove Rooms Dropdown from Sidebar

**Date:** 2026-01-20
**Status:** Approved
**Goal:** UI cleanup - convert Rooms from expandable dropdown to simple link for consistency with other sidebar items

## Background

The sidebar currently has a Rooms dropdown that expands to show individual room links. This is inconsistent with other sidebar items (Nodes, Racks, etc.) which are simple links. The dropdown adds complexity without sufficient value.

## Changes

### 1. Template (`app/views/shared/_sidebar.html.erb`)

Replace the Rooms dropdown (lines 37-69) with a simple link using the existing `_sidebar_link` partial:

```erb
<%= render "shared/sidebar_link",
    path: rooms_path,
    icon_path: "M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4",
    label: "Rooms",
    collapsed: sidebar_collapsed? %>
```

**Removed:**
- `<button>` with `data-action="click->sidebar#toggleRooms"`
- Chevron icon and rotation logic
- Expandable rooms list container
- `data-sidebar-target="roomsChevron"` and `data-sidebar-target="roomsList"` elements

### 2. Stimulus Controller (`app/javascript/controllers/sidebar_controller.js`)

**Remove static values:**
- `roomsExpanded`
- `roomsUrl`

**Remove static targets:**
- `roomsChevron`
- `roomsList`

**Remove methods:**
- `toggleRooms()`
- `applyRoomsState()`

**Simplify existing methods:**
- `toggleCollapse()` - remove roomsExpanded reset and chevron transition logic
- `loadState()` - remove `sidebarRoomsExpanded` localStorage handling
- `saveState()` - remove `sidebarRoomsExpanded` localStorage handling
- `applyState()` - remove `applyRoomsState()` call and rooms-related logic

### 3. Helper (`app/helpers/sidebar_helper.rb`)

**Remove:**
```ruby
def sidebar_rooms
  Room.order(:name)
end
```

**Keep:**
```ruby
def sidebar_collapsed?
  cookies[:sidebar_collapsed] == "true"
end
```

### 4. Tests (`spec/system/sidebar_spec.rb`)

**Remove tests:**
- "shows rooms list when clicking Rooms button"
- "hides rooms list when clicking Rooms button again"
- "navigates to room page when clicking room name"
- "resets rooms dropdown when sidebar is collapsed"
- "rotates chevron icon when rooms are expanded/collapsed"
- Any other rooms expansion-specific tests

**Add test:**
- "clicking Rooms navigates to rooms index"

## Risk Assessment

**Low risk** - Self-contained feature removal with no impact on:
- Room model or database
- Room CRUD functionality
- Other sidebar behavior

## Files Changed

| File | Action |
|------|--------|
| `app/views/shared/_sidebar.html.erb` | Replace dropdown with simple link |
| `app/javascript/controllers/sidebar_controller.js` | Remove rooms state management |
| `app/helpers/sidebar_helper.rb` | Remove `sidebar_rooms` method |
| `spec/system/sidebar_spec.rb` | Remove dropdown tests, add link test |
