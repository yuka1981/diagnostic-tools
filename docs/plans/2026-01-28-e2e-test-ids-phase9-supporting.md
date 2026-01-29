# E2E Test IDs Phase 9: Supporting Features Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Supporting Features views (Tasks, Notifications, Profiling) to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `{module}-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: Tasks Index Page

**Files:**
- Modify: `app/views/tasks/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `tasks-page-container` |
| Auto-refresh control | `tasks-auto-refresh` |
| Filter bar frame | `tasks-filter-frame` |
| Tasks list frame | `tasks-list-frame` |
| Filter summary | `tasks-filter-summary` |
| Tasks table | `tasks-table` |
| Table header | `tasks-table-header` |
| Table body | `tasks-table-body` |
| Empty state | `tasks-table-empty` |
| Pagination | `tasks-pagination` |
| Per-page selector | `tasks-per-page` |

**Commit:** `feat(tasks): add testid support to tasks index page`

---

## Task 2: Tasks Filter Bar Partial

**Files:**
- Modify: `app/views/tasks/_filter_bar.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Filter form | `tasks-filter-form` |
| Search field | `tasks-filter-search` |
| Type select | `tasks-filter-type` |
| Status select | `tasks-filter-status` |
| Node select | `tasks-filter-node` |
| Recipe select | `tasks-filter-recipe` |
| Date range select | `tasks-filter-date` |
| Search button | `tasks-button-search` |
| Clear button | `tasks-button-clear` |

**Commit:** `feat(tasks): add testid support to tasks filter bar`

---

## Task 3: Task Row Partial

**Files:**
- Modify: `app/views/tasks/_task_row.html.erb`

**Test IDs to add (dynamic with task ID):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `tasks-row-{id}` |
| Expand toggle | `tasks-expand-{id}` |
| Type badge | `tasks-type-{id}` |
| Hostname link | `tasks-hostname-{id}` |
| Recipe name | `tasks-recipe-{id}` |
| Status badge | `tasks-status-{id}` |
| Started time | `tasks-started-{id}` |
| Duration | `tasks-duration-{id}` |
| Re-run button | `tasks-button-rerun-{id}` |
| View node button | `tasks-button-view-node-{id}` |
| Cancel button | `tasks-button-cancel-{id}` |
| Delete button | `tasks-button-delete-{id}` |

**Commit:** `feat(tasks): add testid support to task row partial`

---

## Task 4: Task Details Partial

**Files:**
- Modify: `app/views/tasks/_task_details.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Details container | `tasks-details-{id}` |
| Details table | `tasks-details-table-{id}` |
| Error message | `tasks-details-error-{id}` |
| Output section | `tasks-details-output-{id}` |

**Commit:** `feat(tasks): add testid support to task details partial`

---

## Task 5: Notifications Index Page

**Files:**
- Modify: `app/views/notifications/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `notifications-container` |
| Mark all read button | `notifications-button-mark-read` |
| Archive read button | `notifications-button-archive` |
| List container | `notifications-list` |
| Empty state | `notifications-empty` |
| Pagination | `notifications-pagination` |

**Commit:** `feat(notifications): add testid support to notifications index`

---

## Task 6: Notifications List Partial

**Files:**
- Modify: `app/views/notifications/_list.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| List frame | `notifications-list-frame` |
| List container | `notifications-list-container` |

**Commit:** `feat(notifications): add testid support to notifications list partial`

---

## Task 7: Notification Item Partial

**Files:**
- Modify: `app/views/notifications/_notification.html.erb`

**Test IDs to add (dynamic with notification ID):**

| Element | Test ID Pattern |
|---------|-----------------|
| Item container | `notifications-item-{id}` |
| Icon | `notifications-icon-{id}` |
| Message | `notifications-message-{id}` |
| Timestamp | `notifications-time-{id}` |
| Dismiss button | `notifications-button-dismiss-{id}` |
| Link (if present) | `notifications-link-{id}` |

**Commit:** `feat(notifications): add testid support to notification item partial`

---

## Task 8: Notifications Badge Partial

**Files:**
- Modify: `app/views/notifications/_badge.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Badge element | `notifications-badge` |
| Unread count | `notifications-unread-count` |

**Commit:** `feat(notifications): add testid support to notifications badge`

---

## Task 9: Profiling Run Modal (New)

**Files:**
- Modify: `app/views/nodes/profiling_runs/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `profiling-modal` |
| Modal title | `profiling-modal-title` |
| Form | `profiling-form` |
| Report radio | `profiling-radio-report` |
| Telemetry radio | `profiling-radio-telemetry` |
| Flame radio | `profiling-radio-flame` |
| Module name field | `profiling-input-module` |
| Duration field | `profiling-input-duration` |
| Cancel button | `profiling-button-cancel` |
| Submit button | `profiling-button-submit` |

**Commit:** `feat(profiling): add testid support to profiling run modal`

---

## Task 10: Profiling Run Show Page

**Files:**
- Modify: `app/views/nodes/profiling_runs/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `profiling-show-container` |
| Run type heading | `profiling-show-type` |
| Status badge | `profiling-show-status` |
| Details card | `profiling-show-details` |
| Output card | `profiling-show-output` |
| Artifacts card | `profiling-show-artifacts` |
| Artifacts table | `profiling-show-artifacts-table` |

**Commit:** `feat(profiling): add testid support to profiling run show page`

---

## Task 11: Profiling Run Row Partial

**Files:**
- Modify: `app/views/profiling_runs/_run_row.html.erb`

**Test IDs to add (dynamic with run ID):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `profiling-row-{id}` |
| Type cell | `profiling-type-{id}` |
| Recipe cell | `profiling-recipe-{id}` |
| Status badge | `profiling-status-{id}` |
| Started time | `profiling-started-{id}` |
| Duration | `profiling-duration-{id}` |
| View link | `profiling-link-view-{id}` |
| Artifacts count | `profiling-artifacts-{id}` |

**Commit:** `feat(profiling): add testid support to profiling run row partial`

---

## Task 12: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Supporting Features Module section.

**Commit:** `docs: add supporting features test IDs to reference document`

---

## Task 13: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/tasks/ app/views/notifications/ app/views/nodes/profiling_runs/ app/views/profiling_runs/`

---

## Success Criteria

- [ ] All supporting feature view files have data-testid attributes
- [ ] Dynamic test IDs use IDs (acceptable for tasks/notifications)
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/tasks/index.html.erb` | 11 |
| `app/views/tasks/_filter_bar.html.erb` | 9 |
| `app/views/tasks/_task_row.html.erb` | 12 (dynamic) |
| `app/views/tasks/_task_details.html.erb` | 4 (dynamic) |
| `app/views/notifications/index.html.erb` | 6 |
| `app/views/notifications/_list.html.erb` | 2 |
| `app/views/notifications/_notification.html.erb` | 6 (dynamic) |
| `app/views/notifications/_badge.html.erb` | 2 |
| `app/views/nodes/profiling_runs/new.html.erb` | 10 |
| `app/views/nodes/profiling_runs/show.html.erb` | 7 |
| `app/views/profiling_runs/_run_row.html.erb` | 8 (dynamic) |
