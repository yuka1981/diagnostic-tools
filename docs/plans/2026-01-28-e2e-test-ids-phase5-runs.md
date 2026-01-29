# E2E Test IDs Phase 5: Benchmark Runs Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Benchmark Runs views to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `benchmark-runs-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates

---

## Task 1: Benchmark Runs Index Page

**Files:**
- Modify: `app/views/benchmark_runs/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `benchmark-runs-page-container` |
| Filter form | `benchmark-runs-filter-form` |
| Search input | `benchmark-runs-filter-search` |
| Status select | `benchmark-runs-filter-status` |
| Node select | `benchmark-runs-filter-node` |
| Recipe select | `benchmark-runs-filter-recipe` |
| Search button | `benchmark-runs-button-search` |
| Clear filters button | `benchmark-runs-button-clear` |
| Results summary | `benchmark-runs-results-summary` |
| Runs table | `benchmark-runs-table` |
| Table header | `benchmark-runs-table-header` |
| Table body | `benchmark-runs-table-body` |
| Empty state | `benchmark-runs-table-empty` |
| Pagination | `benchmark-runs-pagination` |
| Pagination prev | `benchmark-runs-pagination-prev` |
| Pagination next | `benchmark-runs-pagination-next` |
| Slide-over modal | `benchmark-runs-slideover` |

**Commit:** `feat(benchmark-runs): add testid support to benchmark runs index`

---

## Task 2: Run Row Partial

**Files:**
- Modify: `app/views/benchmark_runs/_run_row.html.erb`

**Test IDs to add (dynamic with run ID):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row | `benchmark-runs-row-{id}` |
| ID cell | `benchmark-runs-id-{id}` |
| Recipe cell | `benchmark-runs-recipe-{id}` |
| Hostname link | `benchmark-runs-hostname-{id}` |
| Status badge | `benchmark-runs-status-{id}` |
| Gflops value | `benchmark-runs-gflops-{id}` |
| Duration value | `benchmark-runs-duration-{id}` |
| Created date | `benchmark-runs-created-{id}` |
| Cancel button | `benchmark-runs-button-cancel-{id}` |
| View button | `benchmark-runs-button-view-{id}` |

**Commit:** `feat(benchmark-runs): add testid support to run row partial`

---

## Task 3: Benchmark Runs Show Page

**Files:**
- Modify: `app/views/benchmark_runs/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `benchmark-runs-show-container` |
| Status icon | `benchmark-runs-show-status-icon` |
| Recipe heading | `benchmark-runs-show-recipe` |
| Status badge | `benchmark-runs-show-status` |
| Cancel button | `benchmark-runs-show-button-cancel` |
| Run details card | `benchmark-runs-show-details` |
| Results card | `benchmark-runs-show-results` |
| Error card | `benchmark-runs-show-error` |
| Config card | `benchmark-runs-show-config` |
| Logs card | `benchmark-runs-show-logs` |
| Logs toggle | `benchmark-runs-show-logs-toggle` |
| Logs content | `benchmark-runs-show-logs-content` |
| Artifacts card | `benchmark-runs-show-artifacts` |
| Artifacts table | `benchmark-runs-show-artifacts-table` |

**Commit:** `feat(benchmark-runs): add testid support to benchmark runs show page`

---

## Task 4: Results Card Partial

**Files:**
- Modify: `app/views/benchmark_runs/_results_card.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Card container | `benchmark-runs-results-card` |
| Result badge (PASS/FAIL) | `benchmark-runs-results-badge` |
| Waiting state | `benchmark-runs-results-waiting` |
| Spinner | `benchmark-runs-results-spinner` |
| Phase text | `benchmark-runs-results-phase` |
| Metrics table | `benchmark-runs-results-metrics` |
| Empty state | `benchmark-runs-results-empty` |

**Dynamic metric test IDs:**

| Element | Test ID Pattern |
|---------|-----------------|
| Metric row | `benchmark-runs-metric-{key}` |
| Metric value | `benchmark-runs-metric-value-{key}` |

**Commit:** `feat(benchmark-runs): add testid support to results card partial`

---

## Task 5: Configuration Card Partial

**Files:**
- Modify: `app/views/benchmark_runs/_configuration_card.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Card container | `benchmark-runs-config-card` |
| Recipe link | `benchmark-runs-config-recipe` |
| Command value | `benchmark-runs-config-command` |
| Timeout value | `benchmark-runs-config-timeout` |
| Arguments section | `benchmark-runs-config-args` |

**Commit:** `feat(benchmark-runs): add testid support to configuration card partial`

---

## Task 6: Slide-over Partial

**Files:**
- Modify: `app/views/benchmark_runs/_slide_over.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Backdrop | `benchmark-runs-slideover-backdrop` |
| Modal panel | `benchmark-runs-slideover-panel` |
| Title | `benchmark-runs-slideover-title` |
| Close button | `benchmark-runs-slideover-close` |
| Content frame | `benchmark-runs-slideover-content` |

**Commit:** `feat(benchmark-runs): add testid support to slide-over partial`

---

## Task 7: Slide-over Content Partial

**Files:**
- Modify: `app/views/benchmark_runs/_slide_over_content.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Content frame | `benchmark-runs-slideover-content-frame` |
| Header section | `benchmark-runs-slideover-header` |
| Recipe name | `benchmark-runs-slideover-recipe` |
| Status badge | `benchmark-runs-slideover-status` |
| Cancel button | `benchmark-runs-slideover-cancel` |
| Tabs container | `benchmark-runs-slideover-tabs` |
| Tab: Summary | `benchmark-runs-tab-summary` |
| Tab: Metrics | `benchmark-runs-tab-metrics` |
| Tab: Logs | `benchmark-runs-tab-logs` |
| Tab: Artifacts | `benchmark-runs-tab-artifacts` |
| Panel: Summary | `benchmark-runs-panel-summary` |
| Panel: Metrics | `benchmark-runs-panel-metrics` |
| Panel: Logs | `benchmark-runs-panel-logs` |
| Panel: Artifacts | `benchmark-runs-panel-artifacts` |
| Error message | `benchmark-runs-slideover-error` |
| Details table | `benchmark-runs-slideover-details` |
| Metrics table | `benchmark-runs-slideover-metrics` |
| Logs content | `benchmark-runs-slideover-logs` |
| Artifacts table | `benchmark-runs-slideover-artifacts` |
| View full details button | `benchmark-runs-slideover-view-full` |

**Commit:** `feat(benchmark-runs): add testid support to slide-over content partial`

---

## Task 8: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Benchmark Runs Module section.

**Commit:** `docs: add benchmark runs test IDs to reference document`

---

## Task 9: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/benchmark_runs/`

---

## Success Criteria

- [ ] All 7 benchmark run view files have data-testid attributes
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/benchmark_runs/index.html.erb` | 17 |
| `app/views/benchmark_runs/_run_row.html.erb` | 10 (dynamic) |
| `app/views/benchmark_runs/show.html.erb` | 14 |
| `app/views/benchmark_runs/_results_card.html.erb` | 9 |
| `app/views/benchmark_runs/_configuration_card.html.erb` | 5 |
| `app/views/benchmark_runs/_slide_over.html.erb` | 5 |
| `app/views/benchmark_runs/_slide_over_content.html.erb` | 20 |
