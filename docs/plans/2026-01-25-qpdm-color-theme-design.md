# QPDM Portal Color Theme Design

**Date:** 2026-01-25
**Status:** Ready for implementation
**Branch:** `feature/design-qpdm-color-theme`
**Worktree:** `.worktrees/design-qpdm-color-theme`

## Overview

Apply the QPDM Portal color theme from Figma to the HPC diagnostic tools application. This is a full rebrand replacing all colors (primary, success, error, warning, neutrals) with both Figma-named and semantic color aliases.

**Source:** [Figma Design](https://www.figma.com/design/5729KMyvQhfZrdzQWtEPzp/QPDM-Portal--Copy-?node-id=2731-246497&m=dev)

## Color Palette

### Primary Colors

| Name | Hex | Usage |
|------|-----|-------|
| QCT Blue | #005197 | Brand color, primary actions |
| Tech Blue 6 | #1890FF | Default primary, links |

### Tech Blue Scale (Primary)

| Level | Hex | Usage |
|-------|-----|-------|
| 1 | #E6F7FF | Lightest background |
| 2 | #BAE7FF | Light background, selected states |
| 3 | #91D5FF | Borders, light accents |
| 4 | #69C0FF | Hover states (light) |
| 5 | #40A9FF | Hover states |
| 6 | #1890FF | Default primary |
| 7 | #0878F2 | Hover (dark) |
| 8 | #006DCB | Active/pressed |
| 9 | #0262B4 | Dark accent |
| 10 | #005197 | Darkest, brand |

### Polar Green Scale (Success)

| Level | Hex |
|-------|-----|
| 1 | #EBF9ED |
| 2 | #D9F7BE |
| 3 | #B7EB8F |
| 4 | #95DE64 |
| 5 | #73D13D |
| 6 | #52C41A |
| 7 | #389E0D |
| 8 | #237804 |
| 9 | #135200 |
| 10 | #092B00 |

### Dust Red Scale (Error)

| Level | Hex |
|-------|-----|
| 1 | #FFEBEA |
| 2 | #FFCCC7 |
| 3 | #FFA39E |
| 4 | #FF7875 |
| 5 | #FF4D4F |
| 6 | #F5222D |
| 7 | #CF1322 |
| 8 | #A8071A |
| 9 | #820014 |
| 10 | #5C0011 |

### Warm Orange Scale (Warning)

| Level | Hex |
|-------|-----|
| 1 | #FFF2E7 |
| 2 | #FFE6CF |
| 3 | #FFD4A1 |
| 4 | #FFC887 |
| 5 | #FFBF75 |
| 6 | #FFB660 |
| 7 | #FFAF52 |
| 8 | #D97500 |
| 9 | #A55900 |
| 10 | #7E4400 |

### Bright Yellow

| Level | Hex |
|-------|-----|
| 1 | #FFF6E7 |
| 6 | #FFD400 |

### Neutral - Black Scale (Light backgrounds)

| Level | Hex |
|-------|-----|
| 2 | #FAFAFA |
| 4 | #F5F5F5 |
| 6 | #F0F0F0 |
| 8 | #E8E8E8 |
| 15 | #D9D9D9 |
| 25 | #BFBFBF |
| 45 | #8C8C8C |
| 85 | #262626 |

### Neutral - White Scale (Dark backgrounds)

| Level | Hex |
|-------|-----|
| 4 | #1D1D1D |
| 8 | #262626 |
| 12 | #303030 |
| 20 | #434343 |
| 45 | #7D7D7D |
| 85 | #DBDBDB |
| 100 | #FFFFFF |

## Tailwind Configuration

### Color Naming Strategy

Both Figma-named and semantic aliases will be available:

```javascript
// Figma names - exact match to design file
'tech-blue-6'  // #1890FF
'polar-green-6' // #52C41A
'dust-red-6'    // #F5222D

// Semantic aliases - for developer convenience
'primary-6'     // maps to tech-blue-6
'success-6'     // maps to polar-green-6
'error-6'       // maps to dust-red-6
```

## Migration Mapping

| Current | New (Semantic) | New (Figma) |
|---------|----------------|-------------|
| `slate-50` | `neutral-2` | `black-2` |
| `slate-100` | `neutral-4` | `black-4` |
| `slate-200` | `neutral-8` | `black-8` |
| `slate-300` | `neutral-15` | `black-15` |
| `slate-400` | `neutral-25` | `black-25` |
| `slate-500` | `neutral-45` | `black-45` |
| `slate-700` | `neutral-85` | `black-85` |
| `teal-600` | `primary-6` | `tech-blue-6` |
| `teal-700` | `primary-7` | `tech-blue-7` |
| `red-50` | `error-1` | `dust-red-1` |
| `red-200` | `error-2` | `dust-red-2` |
| `red-600` | `error-6` | `dust-red-6` |
| `green-*` | `success-*` | `polar-green-*` |

## Files to Modify

1. **`config/tailwind.config.js`** - Add complete color palette with both naming conventions
2. **`app/assets/tailwind/application.css`** - Update component classes
3. **View files** - Search and replace color classes across `.erb` files

## Implementation Steps

1. Create git worktree with feature branch
2. Update Tailwind config with full color palette
3. Update CSS component classes (`.btn-primary`, `.card`, etc.)
4. Find and replace color classes in view files
5. Verify build with `bin/dev`
6. Run linting with `bin/rubocop`

## Success Criteria

- All Tailwind colors reference the new palette
- No hardcoded `slate-*`, `teal-*`, `red-*`, `green-*` classes remain (except in comments)
- Application builds and renders correctly
- Linting passes
