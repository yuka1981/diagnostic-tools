# Room Rack Integration Redesign

**Date:** 2026-01-20
**Status:** Approved
**Goal:** Improve the compact rack elevation view in the Room show page - fix text readability, add rich hover preview cards, and move legend to top.

## Background

The Room show page displays compact rack elevations grouped by row. Current issues:
1. Hostname text on nodes is hard to read (same contrast issue as full elevation)
2. Hover tooltip is too simple (just hostname, position, status)
3. Legend is at bottom - users see racks before understanding the color coding

## Design Summary

- **Color & text fixes** - Apply same improvements from elevation colors redesign
- **Mini card preview** - Rich hover card showing hostname, position, CPU, RAM
- **Legend position** - Move from bottom to top of section

---

## Color & Text Readability Fixes

Apply consistent styling with the full-size elevation component:

### Color Changes

| Element | Current | New |
|---------|---------|-----|
| Online nodes | `bg-emerald-500` | `bg-emerald-600` |
| Online hover | `hover:bg-emerald-600` | `hover:bg-emerald-700` |
| Offline nodes | `bg-slate-400` | `bg-slate-600` |
| Offline hover | `hover:bg-slate-500` | `hover:bg-slate-700` |
| Empty slots | `bg-slate-50` | `bg-slate-100` |

### Text Shadow

```css
text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
```

---

## Mini Card Preview

### Visual Design

```
┌─────────────────────────────────────────┐
│  Row A                                  │
│  ┌─────┐  ┌─────┐  ┌─────┐              │
│  │ R01 │  │ R02 │  │ R03 │              │
│  │░░░░░│  │░░░░░│  │░░░░░│              │
│  │░░░░░│  │█████│←─┼──────────────────┐ │
│  │█████│  │█████│  │░░░░░│            │ │
│  │█████│  │░░░░░│  │█████│  ┌─────────▼─────────┐
│  │░░░░░│  │░░░░░│  │█████│  │ compute-node-05   │
│  └─────┘  └─────┘  └─────┘  │ U35-U38 (4U)      │
│                             │                   │
│                             │ CPU  2x Xeon 8380 │
│                             │ RAM  512 GB       │
│                             │                   │
│                             │ View Node →       │
│                             └───────────────────┘
└─────────────────────────────────────────┘
```

### Card Content

- **Header**: Hostname (bold)
- **Position**: U range and height (e.g., "U35-U38 (4U)")
- **CPU**: Processor model/count
- **RAM**: Total memory
- **Link**: "View Node →" to full node page

### Behavior

| Platform | Trigger | Dismiss |
|----------|---------|---------|
| Desktop | Hover after 200ms delay | Mouse leave |
| Touch/Mobile | Tap | Tap outside or tap X button |

### Positioning

- Card appears to the right of the hovered node
- If near right edge, appears to the left instead
- Absolute positioning relative to rack container

---

## Legend Position

Move legend from bottom to top of Rack Elevation Overview:

### Before

```
┌─────────────────────────────────────────┐
│  Rack Elevation Overview                │
├─────────────────────────────────────────┤
│  Row A                                  │
│  ┌─────┐  ┌─────┐  ┌─────┐              │
│  │ ... │  │ ... │  │ ... │              │
│  └─────┘  └─────┘  └─────┘              │
│  ─────────────────────────────────────  │
│  ● Online  ○ Offline  ░ Empty           │
└─────────────────────────────────────────┘
```

### After

```
┌─────────────────────────────────────────┐
│  Rack Elevation Overview                │
├─────────────────────────────────────────┤
│  ● Online  ○ Offline  ░ Empty           │
│  ─────────────────────────────────────  │
│  Row A                                  │
│  ┌─────┐  ┌─────┐  ┌─────┐              │
│  │ ... │  │ ... │  │ ... │              │
│  └─────┘  └─────┘  └─────┘              │
└─────────────────────────────────────────┘
```

---

## Implementation

### Files to Change

| File | Change |
|------|--------|
| `app/components/rack_elevation_compact_component.rb` | Update `node_status_classes` colors |
| `app/components/rack_elevation_compact_component.html.erb` | Add text-shadow, data attributes for preview |
| `app/views/rooms/show.html.erb` | Move legend to top of section |
| `app/javascript/controllers/node_preview_controller.js` | New controller for hover/click card |

### Data Attributes Approach

Embed node data in HTML for instant hover response (no fetch latency):

```erb
<div class="..."
     data-controller="node-preview"
     data-node-preview-hostname-value="<%= node.hostname %>"
     data-node-preview-position-value="U<%= node.rack_position %>-U<%= node.rack_position + node.rack_height - 1 %>"
     data-node-preview-height-value="<%= node.rack_height %>U"
     data-node-preview-cpu-value="<%= node.cpu_summary %>"
     data-node-preview-ram-value="<%= node.ram_summary %>"
     data-node-preview-url-value="<%= node_path(node) %>">
```

### Stimulus Controller

```javascript
// app/javascript/controllers/node_preview_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    hostname: String,
    position: String,
    height: String,
    cpu: String,
    ram: String,
    url: String
  }

  connect() {
    this.isTouch = 'ontouchstart' in window
    this.hoverTimeout = null
  }

  // Desktop: show on mouseenter after delay
  mouseEnter() {
    if (this.isTouch) return
    this.hoverTimeout = setTimeout(() => this.showCard(), 200)
  }

  mouseLeave() {
    clearTimeout(this.hoverTimeout)
    this.hideCard()
  }

  // Touch: show on click
  click(event) {
    if (!this.isTouch) return
    event.preventDefault()
    this.showCard()
  }

  showCard() {
    // Create and position card
  }

  hideCard() {
    // Remove card
  }
}
```

### Node Summary Methods

May need to add helper methods to Node model if not present:

```ruby
# app/models/node.rb
def cpu_summary
  "#{cpu_count}x #{cpu_model}" if cpu_model.present?
end

def ram_summary
  "#{total_memory_gb} GB" if total_memory.present?
end
```

---

## Notes

- Color changes should match `feature/rack-elevation-colors` branch for consistency
- Preview card uses same styling as other cards in the app (`.card-netbox` or similar)
- Touch detection uses `'ontouchstart' in window` - consider hybrid devices
- Card content is static (embedded in HTML) - no additional API calls needed
