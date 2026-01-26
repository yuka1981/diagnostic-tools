# QPDM Color Migration Completion Design

**Date:** 2026-01-26
**Status:** Ready for implementation
**Depends on:** 2026-01-25-qpdm-color-theme-design.md (completed)

## Overview

Complete the QPDM color theme migration by addressing ~174 remaining instances of old Tailwind colors (blue, purple, amber, yellow, gray, emerald, green, red) that weren't migrated in the initial implementation.

## New Color Scales

Add two Ant Design Pro color scales to support role-specific and pending state colors.

### Geek Blue Scale (Login Role)

| Level | Hex | Usage |
|-------|-----|-------|
| 1 | #F0F5FF | Lightest background |
| 2 | #D6E4FF | Light background |
| 3 | #ADC6FF | Borders |
| 4 | #85A5FF | Light accents |
| 5 | #597EF7 | Hover states |
| 6 | #2F54EB | Default (login badges) |
| 7 | #1D39C4 | Hover (dark) |
| 8 | #10239E | Active/pressed |
| 9 | #061178 | Dark accent |
| 10 | #030852 | Darkest |

### Sunrise Yellow Scale (Pending States)

| Level | Hex | Usage |
|-------|-----|-------|
| 1 | #FEFFE6 | Lightest background |
| 2 | #FFFFB8 | Light background |
| 3 | #FFFB8F | Borders |
| 4 | #FFF566 | Light accents |
| 5 | #FFEC3D | Hover states |
| 6 | #FADB14 | Default (pending/warning) |
| 7 | #D4B106 | Hover (dark) |
| 8 | #AD8B00 | Active/pressed |
| 9 | #876800 | Dark accent |
| 10 | #614700 | Darkest |

### Semantic Aliases

```javascript
'login': 'geek-blue',     // Login role badges
'pending': 'sunrise-yellow' // Pending/warning states
```

## Migration Mapping

### Role Badges

| Old Class | New Class | Context |
|-----------|-----------|---------|
| `bg-blue-100` | `bg-primary-1` | Compute badge background |
| `text-blue-800` | `text-primary-8` | Compute badge text |
| `bg-purple-100` | `bg-login-1` | Login badge background |
| `text-purple-800` | `text-login-8` | Login badge text |
| `bg-amber-100` | `bg-warning-1` | Admin badge background |
| `text-amber-800` | `text-warning-8` | Admin badge text |

### Warning/Pending States

| Old Class | New Class | Context |
|-----------|-----------|---------|
| `bg-yellow-100` | `bg-pending-1` | Pending state background |
| `text-yellow-800` | `text-pending-8` | Pending state text |
| `bg-yellow-50` | `bg-pending-1` | Warning flash background |
| `border-yellow-500` | `border-pending-5` | Warning flash border |
| `text-yellow-500` | `text-pending-5` | Warning icon |
| `bg-amber-500` | `bg-warning-6` | Disk usage 75-90% |

### Flash Messages / Toasts

| State | Old Classes | New Classes |
|-------|-------------|-------------|
| Success | `bg-green-50 border-green-500 text-green-800` | `bg-success-1 border-success-5 text-success-8` |
| Error | `bg-red-50 border-red-500 text-red-800` | `bg-error-1 border-error-5 text-error-8` |
| Warning | `bg-yellow-50 border-yellow-500 text-yellow-800` | `bg-pending-1 border-pending-5 text-pending-8` |
| Info | `bg-blue-50 border-blue-500 text-blue-800` | `bg-primary-1 border-primary-5 text-primary-8` |

### Flash Message Icons

| State | Old | New |
|-------|-----|-----|
| Success | `text-green-500` | `text-success-5` |
| Error | `text-red-500` | `text-error-5` |
| Warning | `text-yellow-500` | `text-pending-5` |
| Info | `text-blue-500` | `text-primary-5` |

### Neutral/Muted States

| Old Class | New Class | Context |
|-----------|-----------|---------|
| `bg-gray-*` | `bg-neutral-*` | Muted backgrounds |
| `text-gray-*` | `text-neutral-*` | Muted text |

### Heatmap/Visualization

| Old Class | New Class | Context |
|-----------|-----------|---------|
| `bg-emerald-*` | `bg-success-*` | Online/healthy states |
| `bg-blue-500` | `bg-primary-6` | Disk usage <75% |

## Files to Modify

### 1. Tailwind Config
- `config/tailwind.config.js` - Add geek-blue and sunrise-yellow scales with semantic aliases

### 2. Helpers (~4 files)
- `app/helpers/application_helper.rb` - Disk usage bars, status badges
- `app/helpers/dashboard_helper.rb` - Role badges, warning states
- `app/helpers/nodes_helper.rb` - Role-specific styling
- Flash message helpers (if separate)

### 3. Views (~15-20 files)
- Role badge partials
- Flash message partials
- Dashboard/heatmap views
- Status indicator components

### 4. CSS Components
- `app/assets/tailwind/application.css` - Add `.badge-login`, `.flash-*` component classes if needed

### 5. Tests
- Helper specs with color expectations
- System specs checking for specific colors

## Implementation Order

1. **Config first** - Enables new classes
2. **CSS components** - Centralized styles
3. **Helpers** - Business logic
4. **Views** - Templates
5. **Tests** - Validation

## Success Criteria

1. Zero instances of old color classes in application code:
   - `blue-*` (except in comments/docs)
   - `purple-*`
   - `amber-*`
   - `yellow-*`
   - `gray-*`
   - `emerald-*`
   - `green-*`
   - `red-*`
2. All tests pass (`bin/rspec`)
3. No linting errors (`bin/rubocop -f github`)
4. Visual spot-check of key screens: dashboard, node list, flash messages

## Edge Cases

| Case | Approach |
|------|----------|
| Tailwind's `bg-black`/`text-white` | Keep DEFAULT keys (already handled) |
| Third-party gems with hardcoded colors | Leave as-is, document exceptions |
| Inline styles in mailers | Migrate if present |
| Stimulus controllers with color logic | Check for JS color references |

## Out of Scope

- Dark mode implementation (separate effort)
- Chart.js/visualization library colors (may need JS config)
- Email templates (often need inline styles)

## Rollback Plan

- Git revert if issues found
- Feature flag not needed (purely cosmetic change)
