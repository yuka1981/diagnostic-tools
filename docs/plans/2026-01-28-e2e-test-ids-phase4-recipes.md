# E2E Test IDs Phase 4: Benchmark Recipes Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Benchmark Recipes views to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `recipes-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: Recipes Index Page

**Files:**
- Modify: `app/views/benchmark_recipes/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `recipes-page-container` |
| Add Recipe button | `recipes-button-new` |
| Table | `recipes-table` |
| Table header | `recipes-table-header` |
| Table body | `recipes-table-body` |
| Empty state | `recipes-table-empty` |
| Empty add button | `recipes-empty-add` |

**Dynamic row test IDs (by recipe name/slug):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `recipes-row-{slug}` |
| Name link | `recipes-link-{slug}` |
| Command cell | `recipes-command-{slug}` |
| Status badge | `recipes-status-{slug}` |
| View button | `recipes-button-view-{slug}` |
| Edit button | `recipes-button-edit-{slug}` |

**Commit:** `feat(recipes): add testid support to recipes index page`

---

## Task 2: Recipes Show Page

**Files:**
- Modify: `app/views/benchmark_recipes/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `recipes-show-container` |
| Recipe name heading | `recipes-show-name` |
| Status badge | `recipes-show-status` |
| Edit button | `recipes-show-button-edit` |
| Archive button | `recipes-show-button-archive` |
| Activate button | `recipes-show-button-activate` |
| Overview card | `recipes-show-overview` |
| Technical details card | `recipes-show-technical` |
| Default profile card | `recipes-show-profile` |
| Profile JSON display | `recipes-show-profile-json` |
| Danger zone | `recipes-show-danger-zone` |
| Delete button | `recipes-show-button-delete` |

**Commit:** `feat(recipes): add testid support to recipes show page`

---

## Task 3: Recipes Form Partial

**Files:**
- Modify: `app/views/benchmark_recipes/_form.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Form element | `recipes-form` |
| Error container | `recipes-form-errors` |
| Name field | `recipes-input-name` |
| Version field | `recipes-input-version` |
| Description field | `recipes-input-description` |
| Slug field | `recipes-input-slug` |
| Status select | `recipes-select-status` |
| Command field | `recipes-input-command` |
| Timeout field | `recipes-input-timeout` |
| Default profile textarea | `recipes-input-profile` |
| Cancel button | `recipes-button-cancel` |
| Submit button | `recipes-button-submit` |

**Commit:** `feat(recipes): add testid support to recipes form partial`

---

## Task 4: Recipes New Page

**Files:**
- Modify: `app/views/benchmark_recipes/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `recipes-new-container` |
| Page title | `recipes-new-title` |

**Commit:** `feat(recipes): add testid support to recipes new page`

---

## Task 5: Recipes Edit Page

**Files:**
- Modify: `app/views/benchmark_recipes/edit.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `recipes-edit-container` |
| Page title | `recipes-edit-title` |

**Commit:** `feat(recipes): add testid support to recipes edit page`

---

## Task 6: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Benchmark Recipes Module section.

**Commit:** `docs: add benchmark recipes test IDs to reference document`

---

## Task 7: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/benchmark_recipes/`

---

## Success Criteria

- [ ] All 5 recipe view files have data-testid attributes
- [ ] Dynamic test IDs use slug (not database ID)
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/benchmark_recipes/index.html.erb` | 13 (7 static + 6 per row) |
| `app/views/benchmark_recipes/show.html.erb` | 12 |
| `app/views/benchmark_recipes/_form.html.erb` | 12 |
| `app/views/benchmark_recipes/new.html.erb` | 2 |
| `app/views/benchmark_recipes/edit.html.erb` | 2 |
