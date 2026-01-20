# Rack Elevation Colors Redesign

**Date:** 2026-01-20
**Status:** Approved
**Goal:** Improve visual contrast in rack elevation diagrams - make nodes stand out from empty slots and improve hostname text readability.

## Background

The current rack elevation visualization has contrast issues:
1. Nodes don't stand out enough from empty slots, making it hard to quickly see where equipment is positioned
2. White hostname text on colored backgrounds can be hard to read

## Design Summary

- **Bolder node colors** - More saturated emerald and slate for better contrast against light empty slots
- **Text shadow** - Add subtle shadow behind hostname text for readability

---

## Color Changes

### Current vs New

| Element | Current | New |
|---------|---------|-----|
| Online nodes | `bg-emerald-500` | `bg-emerald-600` |
| Online hover | `hover:bg-emerald-600` | `hover:bg-emerald-700` |
| Offline nodes | `bg-slate-400` | `bg-slate-600` |
| Offline hover | `hover:bg-slate-500` | `hover:bg-slate-700` |
| Empty slots | `bg-slate-50` | `bg-slate-100` |

### Visual Result

```
BEFORE:                           AFTER:
┌────────────────────────┐        ┌────────────────────────┐
│  42 ░░░░░░░░░░░░░░░░░  │        │  42 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  │
│  41 ░░░░░░░░░░░░░░░░░  │        │  41 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  │
│  40 ████████████████   │        │  40 ████████████████   │
│  39 ███ Node-01 ████   │        │  39 ███ Node-01 ████   │  ← richer green
│  38 ████████████████   │        │  38 ████████████████   │
│  37 ░░░░░░░░░░░░░░░░░  │        │  37 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  │
│  35 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒   │        │  35 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓   │
│  34 ▒▒▒ Node-02 ▒▒▒▒   │        │  34 ▓▓▓ Node-02 ▓▓▓▓   │  ← deeper slate
└────────────────────────┘        └────────────────────────┘
```

---

## Text Shadow

Add subtle shadow behind white hostname text for better readability:

```css
text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3);
```

This lifts the text off the background, making it readable in all lighting conditions without changing the visual style.

---

## Implementation

### File: `app/components/rack_elevation_component.rb`

Update the `node_status_classes` method:

```ruby
def node_status_classes(node)
  if node.online?
    "bg-emerald-600 hover:bg-emerald-700 text-white"
  else
    "bg-slate-600 hover:bg-slate-700 text-white"
  end
end
```

### File: `app/components/rack_elevation_component.html.erb`

1. Update empty slot background (line 42):
```erb
<div class="absolute w-full border-b border-slate-200 bg-slate-100"
```

2. Add text-shadow to hostname span (line 53):
```erb
<span class="truncate px-2" style="text-shadow: 0 1px 2px rgba(0,0,0,0.3);">
  <%= node.hostname %>
</span>
```

### File: `app/components/rack_elevation_compact_component.rb`

Apply same color changes to `node_status_classes` method for consistency.

### File: `app/components/rack_elevation_compact_component.html.erb`

Apply same empty slot and text-shadow changes for consistency.

---

## Files Changed

| File | Change |
|------|--------|
| `app/components/rack_elevation_component.rb` | Update `node_status_classes` colors |
| `app/components/rack_elevation_component.html.erb` | Update empty slot bg, add text-shadow |
| `app/components/rack_elevation_compact_component.rb` | Update `node_status_classes` colors |
| `app/components/rack_elevation_compact_component.html.erb` | Update empty slot bg, add text-shadow |

---

## Notes

- No migration needed - CSS-only changes
- No new files or dependencies
- Changes apply to both full-size and compact elevation components
- Legend colors remain unchanged (they use the same palette and will still match)
