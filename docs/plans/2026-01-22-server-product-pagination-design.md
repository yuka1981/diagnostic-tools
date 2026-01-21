# Server Product Page Number Navigation Design

## Overview

Add clickable page numbers to the server products list pagination, replacing the minimal Previous/Next buttons with a full hybrid pagination pattern.

**Target display:**
```
Showing 21 to 30 of 87 results

[Previous] [1] [...] [3] [4] [5] [6] [7] [...] [9] [Next]
                         ↑ current (teal)
```

## Requirements

- Hybrid pagination: sliding window + first/last pages with ellipsis for gaps
- Button styling matching existing NetBox-inspired design
- Desktop only (mobile support deferred)
- Preserve filter params (series, form_factor, q) across navigation

## Implementation

### Kaminari Custom Theme

Create custom view templates in `app/views/kaminari/`:

| File | Purpose |
|------|---------|
| `_paginator.html.erb` | Main container with nav element |
| `_page.html.erb` | Page number link (`btn-secondary`) |
| `_current_page.html.erb` | Current page (`btn-primary`, non-clickable) |
| `_gap.html.erb` | Ellipsis element |
| `_first_page.html.erb` | Link to page 1 |
| `_last_page.html.erb` | Link to last page |
| `_prev_page.html.erb` | Previous button |
| `_next_page.html.erb` | Next button |

### View Change

Replace manual pagination in `app/views/settings/server_products/index.html.erb` (lines 101-112) with:

```erb
<%= paginate @server_products,
    params: { series: params[:series], form_factor: params[:form_factor], q: params[:q] },
    window: 2,
    outer_window: 1 %>
```

### Styling

| Element | Class |
|---------|-------|
| Page numbers | `btn-secondary` |
| Current page | `btn-primary` |
| Previous/Next | `btn-secondary` |
| Disabled buttons | `btn-secondary opacity-50 cursor-not-allowed` |
| Ellipsis | `px-3 py-2 text-slate-400` |
| Container | `flex items-center justify-center gap-1` |

### Accessibility

- `aria-label="Pagination"` on nav container
- `aria-current="page"` on current page
- `aria-disabled="true"` on disabled buttons
- Screen reader text for ellipsis

## Testing

### Manual Checklist

- [ ] Pagination appears only when total pages > 1
- [ ] Clicking page numbers navigates correctly
- [ ] Current page highlighted and not clickable
- [ ] Ellipsis appears when gaps exist
- [ ] First/last pages always visible
- [ ] Previous disabled on page 1, Next disabled on last page
- [ ] Filter params preserved across navigation

### Spec Coverage

Add to `spec/requests/settings/server_products_spec.rb`:
- Pagination links rendered when products exceed page size
- Current page has correct styling
- Filter params preserved in pagination links

## Files Changed

- `app/views/settings/server_products/index.html.erb` - Replace manual pagination
- `app/views/kaminari/*.html.erb` - New custom theme partials (8 files)
- `spec/requests/settings/server_products_spec.rb` - Add pagination specs

## Out of Scope

- Mobile responsive behavior (future work)
- Turbo Frame partial page updates
- Per-page size selector
