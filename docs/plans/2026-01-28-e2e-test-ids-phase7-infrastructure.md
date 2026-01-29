# E2E Test IDs Phase 7: Infrastructure Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Infrastructure views (Sites, Rooms) to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `{module}-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: Sites Index Page

**Files:**
- Modify: `app/views/sites/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `sites-page-container` |
| Add Site button | `sites-button-new` |
| Sites table | `sites-table` |
| Table header | `sites-table-header` |
| Table body | `sites-table-body` |
| Empty state | `sites-table-empty` |
| Empty add button | `sites-empty-add` |

**Dynamic row test IDs (by site name):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `sites-row-{name}` |
| Name link | `sites-link-{name}` |
| Rooms count | `sites-rooms-{name}` |
| Nodes count | `sites-nodes-{name}` |
| View button | `sites-button-view-{name}` |
| Edit button | `sites-button-edit-{name}` |

**Commit:** `feat(sites): add testid support to sites index page`

---

## Task 2: Sites Show Page

**Files:**
- Modify: `app/views/sites/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `sites-show-container` |
| Site name heading | `sites-show-name` |
| Edit button | `sites-show-button-edit` |
| Add Room button | `sites-show-button-add-room` |
| Overview card | `sites-show-overview` |
| Statistics card | `sites-show-statistics` |
| Rooms list card | `sites-show-rooms` |
| Rooms table | `sites-show-rooms-table` |
| Rooms tbody | `sites-show-rooms-tbody` |
| Rooms empty | `sites-show-rooms-empty` |
| Danger zone | `sites-show-danger-zone` |
| Delete button | `sites-show-button-delete` |

**Dynamic room row test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Room row | `sites-room-row-{name}` |
| Room link | `sites-room-link-{name}` |

**Commit:** `feat(sites): add testid support to sites show page`

---

## Task 3: Sites Form Partial

**Files:**
- Modify: `app/views/sites/_form.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Form element | `sites-form` |
| Error container | `sites-form-errors` |
| Name field | `sites-input-name` |
| Description field | `sites-input-description` |
| Cancel button | `sites-button-cancel` |
| Submit button | `sites-button-submit` |

**Commit:** `feat(sites): add testid support to sites form partial`

---

## Task 4: Sites New Page

**Files:**
- Modify: `app/views/sites/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `sites-new-container` |
| Page title | `sites-new-title` |

**Commit:** `feat(sites): add testid support to sites new page`

---

## Task 5: Sites Edit Page

**Files:**
- Modify: `app/views/sites/edit.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `sites-edit-container` |
| Page title | `sites-edit-title` |

**Commit:** `feat(sites): add testid support to sites edit page`

---

## Task 6: Rooms Index Page

**Files:**
- Modify: `app/views/rooms/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `rooms-page-container` |
| Add Room button | `rooms-button-new` |
| Site filter | `rooms-filter-site` |
| Clear filter link | `rooms-filter-clear` |
| Rooms table | `rooms-table` |
| Table header | `rooms-table-header` |
| Table body | `rooms-table-body` |
| Empty state | `rooms-table-empty` |
| Empty add button | `rooms-empty-add` |

**Dynamic row test IDs (by room name):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `rooms-row-{name}` |
| Name link | `rooms-link-{name}` |
| Site name | `rooms-site-{name}` |
| Racks count | `rooms-racks-{name}` |
| Utilization bar | `rooms-utilization-{name}` |
| View button | `rooms-button-view-{name}` |
| Edit button | `rooms-button-edit-{name}` |

**Commit:** `feat(rooms): add testid support to rooms index page`

---

## Task 7: Rooms Show Page

**Files:**
- Modify: `app/views/rooms/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `rooms-show-container` |
| Room name heading | `rooms-show-name` |
| At capacity badge | `rooms-show-capacity-badge` |
| Edit button | `rooms-show-button-edit` |
| Add Rack button | `rooms-show-button-add-rack` |
| Overview card | `rooms-show-overview` |
| Capacity card | `rooms-show-capacity` |
| Racks list card | `rooms-show-racks` |
| Racks table | `rooms-show-racks-table` |
| Racks tbody | `rooms-show-racks-tbody` |
| Racks empty | `rooms-show-racks-empty` |
| Danger zone | `rooms-show-danger-zone` |
| Delete button | `rooms-show-button-delete` |

**Dynamic rack row test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Rack row | `rooms-rack-row-{name}` |
| Rack link | `rooms-rack-link-{name}` |

**Commit:** `feat(rooms): add testid support to rooms show page`

---

## Task 8: Rooms Form Partial

**Files:**
- Modify: `app/views/rooms/_form.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Form element | `rooms-form` |
| Error container | `rooms-form-errors` |
| Site select | `rooms-select-site` |
| Name field | `rooms-input-name` |
| Description field | `rooms-input-description` |
| Floor number field | `rooms-input-floor` |
| Building wing field | `rooms-input-wing` |
| Grid coordinates field | `rooms-input-grid` |
| Floor area field | `rooms-input-area` |
| Max rack count field | `rooms-input-max-racks` |
| Power capacity field | `rooms-input-power` |
| Cooling capacity field | `rooms-input-cooling` |
| Cancel button | `rooms-button-cancel` |
| Submit button | `rooms-button-submit` |

**Commit:** `feat(rooms): add testid support to rooms form partial`

---

## Task 9: Rooms New Page

**Files:**
- Modify: `app/views/rooms/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `rooms-new-container` |
| Page title | `rooms-new-title` |

**Commit:** `feat(rooms): add testid support to rooms new page`

---

## Task 10: Rooms Edit Page

**Files:**
- Modify: `app/views/rooms/edit.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `rooms-edit-container` |
| Page title | `rooms-edit-title` |

**Commit:** `feat(rooms): add testid support to rooms edit page`

---

## Task 11: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Infrastructure Module section (Sites and Rooms).

**Commit:** `docs: add infrastructure test IDs to reference document`

---

## Task 12: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/sites/ app/views/rooms/`

---

## Success Criteria

- [ ] All 10 infrastructure view files have data-testid attributes
- [ ] Dynamic test IDs use names (not database IDs)
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/sites/index.html.erb` | 13 (7 static + 6 per row) |
| `app/views/sites/show.html.erb` | 14 (+ dynamic) |
| `app/views/sites/_form.html.erb` | 6 |
| `app/views/sites/new.html.erb` | 2 |
| `app/views/sites/edit.html.erb` | 2 |
| `app/views/rooms/index.html.erb` | 16 (9 static + 7 per row) |
| `app/views/rooms/show.html.erb` | 15 (+ dynamic) |
| `app/views/rooms/_form.html.erb` | 14 |
| `app/views/rooms/new.html.erb` | 2 |
| `app/views/rooms/edit.html.erb` | 2 |
