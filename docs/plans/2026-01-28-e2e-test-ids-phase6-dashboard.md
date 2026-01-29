# E2E Test IDs Phase 6: Dashboard Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Dashboard views to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `dashboard-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: Dashboard Index Page

**Files:**
- Modify: `app/views/dashboard/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `dashboard-page-container` |
| Node Availability card | `dashboard-stat-availability` |
| Availability percentage | `dashboard-stat-availability-value` |
| Availability progress bar | `dashboard-stat-availability-bar` |
| Benchmark Health card | `dashboard-stat-health` |
| Success rate percentage | `dashboard-stat-health-value` |
| Success rate progress bar | `dashboard-stat-health-bar` |
| Queue Status card | `dashboard-stat-queue` |
| Total tasks count | `dashboard-stat-queue-total` |
| Active tasks badge | `dashboard-stat-queue-active` |
| Pending tasks badge | `dashboard-stat-queue-pending` |
| Cluster Storage card | `dashboard-stat-storage` |
| Storage percentage | `dashboard-stat-storage-value` |
| Storage progress bar | `dashboard-stat-storage-bar` |
| Quick actions section | `dashboard-quick-actions` |
| View Nodes action | `dashboard-action-nodes` |
| View Runs action | `dashboard-action-runs` |
| View Recipes action | `dashboard-action-recipes` |
| Import CSV action | `dashboard-action-import` |

**Commit:** `feat(dashboard): add testid support to dashboard index page`

---

## Task 2: Heatmap Partial

**Files:**
- Modify: `app/views/dashboard/_heatmap.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Heatmap container | `dashboard-heatmap-container` |
| Heatmap title | `dashboard-heatmap-title` |
| Selected node label | `dashboard-heatmap-selected` |
| Clear filter button | `dashboard-heatmap-clear` |
| Heatmap grid | `dashboard-heatmap-grid` |
| Node count summary | `dashboard-heatmap-summary` |
| Empty state | `dashboard-heatmap-empty` |

**Dynamic test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Role group | `dashboard-heatmap-role-{role}` |
| Role label | `dashboard-heatmap-role-label-{role}` |
| Node cell | `dashboard-heatmap-node-{hostname}` |

**Commit:** `feat(dashboard): add testid support to heatmap partial`

---

## Task 3: Filtered Runs Partial

**Files:**
- Modify: `app/views/dashboard/_filtered_runs.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Runs frame | `dashboard-runs-frame` |
| Runs heading | `dashboard-runs-heading` |
| View all link | `dashboard-runs-view-all` |
| Runs list | `dashboard-runs-list` |
| Empty state | `dashboard-runs-empty` |

**Dynamic test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Run item | `dashboard-run-{id}` |
| Run status icon | `dashboard-run-status-{id}` |
| Run recipe name | `dashboard-run-recipe-{id}` |
| Run hostname | `dashboard-run-hostname-{id}` |
| Run timestamp | `dashboard-run-time-{id}` |
| Run status badge | `dashboard-run-badge-{id}` |

**Commit:** `feat(dashboard): add testid support to filtered runs partial`

---

## Task 4: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Dashboard Module section.

**Commit:** `docs: add dashboard test IDs to reference document`

---

## Task 5: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/dashboard/`

---

## Success Criteria

- [ ] All 3 dashboard view files have data-testid attributes
- [ ] Dynamic test IDs use hostname for nodes
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/dashboard/index.html.erb` | 18 |
| `app/views/dashboard/_heatmap.html.erb` | 10 (+ dynamic) |
| `app/views/dashboard/_filtered_runs.html.erb` | 11 (+ dynamic) |
