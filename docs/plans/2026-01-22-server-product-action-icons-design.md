# Server Product Action Icons Design

## Overview

Replace text action links (`View | Edit | Delete`) with icon buttons in the server product table for a cleaner, more compact UI.

## Changes

**Before:**
```
View | Edit | Delete
```

**After:**
```
[eye] [pencil] [trash]   (Heroicons Outline, with tooltips)
```

## Icon Specifications

| Action | Heroicon | Color | Hover |
|--------|----------|-------|-------|
| View | `eye` | `text-teal-600` | `hover:text-teal-700` |
| Edit | `pencil-square` | `text-slate-600` | `hover:text-slate-700` |
| Delete | `trash` | `text-red-600` | `hover:text-red-700` |

## Styling

- Icon size: `h-5 w-5` (20x20px)
- Container: `flex items-center gap-2`
- Accessibility: `title` attribute for tooltip, `<span class="sr-only">` for screen readers

## File to Modify

`app/views/settings/server_products/_product.html.erb` (lines 55-61)

## Out of Scope

- Confirmation modal redesign (keep existing `turbo_confirm`)
- Hover background effects
- Dropdown menu alternative
