# E2E Test IDs Phase 3: Nodes Module Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all Nodes module views to enable Playwright E2E testing.

**Architecture:** Views add `data-testid` attributes directly to key elements. Test IDs follow the `nodes-{element}-{descriptor}` pattern.

**Tech Stack:** Rails 7, ERB templates, ViewComponents

---

## Task 1: Nodes Index Page

**Files:**
- Modify: `app/views/nodes/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `nodes-page-container` |
| Add Node button | `nodes-button-new` |
| Import CSV button | `nodes-button-import` |
| Table turbo frame | `nodes-table-frame` |

**Commit:** `feat(nodes): add testid support to nodes index page`

---

## Task 2: Nodes Table Partial

**Files:**
- Modify: `app/views/nodes/_table.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Bulk action bar | `nodes-bulk-actions` |
| Selection count | `nodes-bulk-count` |
| Clear selection button | `nodes-bulk-clear` |
| Delete selected button | `nodes-bulk-delete` |
| Table element | `nodes-table` |
| Table header | `nodes-table-header` |
| Table body | `nodes-table-body` |
| Empty state | `nodes-table-empty` |
| Empty state add button | `nodes-empty-add` |
| Empty state import button | `nodes-empty-import` |

**Commit:** `feat(nodes): add testid support to nodes table partial`

---

## Task 3: Node Row Partial

**Files:**
- Modify: `app/views/nodes/_node.html.erb`

**Test IDs to add (dynamic with hostname):**

| Element | Test ID Pattern |
|---------|-----------------|
| Row element | `nodes-row-{hostname}` |
| Checkbox | `nodes-checkbox-{hostname}` |
| Hostname link | `nodes-link-{hostname}` |
| IP display | `nodes-ip-{hostname}` |
| Role badge | `nodes-role-{hostname}` |
| Architecture | `nodes-arch-{hostname}` |
| Status badge | `nodes-status-{hostname}` |
| Last seen | `nodes-last-seen-{hostname}` |
| Install button | `nodes-button-install-{hostname}` |
| Update button | `nodes-button-update-{hostname}` |
| Uninstall button | `nodes-button-uninstall-{hostname}` |
| Collect button | `nodes-button-collect-{hostname}` |
| Edit button | `nodes-button-edit-{hostname}` |
| Delete button | `nodes-button-delete-{hostname}` |

**Commit:** `feat(nodes): add testid support to node row partial`

---

## Task 4: Node Show Page

**Files:**
- Modify: `app/views/nodes/show.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `nodes-show-container` |
| Hostname heading | `nodes-show-hostname` |
| Status badge | `nodes-show-status` |
| Collect button | `nodes-show-button-collect` |
| Benchmark button | `nodes-show-button-benchmark` |
| Update Agent button | `nodes-show-button-update` |
| Edit button | `nodes-show-button-edit` |
| Delete button | `nodes-show-button-delete` |
| Tab: Overview | `nodes-tab-overview` |
| Tab: Hardware | `nodes-tab-hardware` |
| Tab: Benchmark History | `nodes-tab-benchmarks` |
| Tab: Logs | `nodes-tab-logs` |
| Tab: Profiling | `nodes-tab-profiling` |
| Tab panel: Overview | `nodes-panel-overview` |
| Tab panel: Hardware | `nodes-panel-hardware` |
| Tab panel: Benchmarks | `nodes-panel-benchmarks` |
| Tab panel: Logs | `nodes-panel-logs` |
| Tab panel: Profiling | `nodes-panel-profiling` |

**Commit:** `feat(nodes): add testid support to node show page`

---

## Task 5: Node Overview Partial

**Files:**
- Modify: `app/views/nodes/_overview.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Node details card | `nodes-overview-details` |
| OS card | `nodes-overview-os` |
| Server product card | `nodes-overview-product` |
| Recent runs card | `nodes-overview-runs` |
| Recent runs table body | `nodes-overview-runs-tbody` |
| View all runs link | `nodes-overview-runs-link` |

**Commit:** `feat(nodes): add testid support to node overview partial`

---

## Task 6: Node Hardware Partial

**Files:**
- Modify: `app/views/nodes/_hardware.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| System info table | `nodes-hardware-system` |
| BIOS info table | `nodes-hardware-bios` |
| CPU details table | `nodes-hardware-cpu` |
| Memory OS view table | `nodes-hardware-memory-os` |
| Memory topology section | `nodes-hardware-memory-topology` |
| Memory topology toggle | `nodes-hardware-memory-toggle` |
| Memory devices table | `nodes-hardware-memory-devices` |
| Network section | `nodes-hardware-network` |
| Storage table | `nodes-hardware-storage` |

**Commit:** `feat(nodes): add testid support to node hardware partial`

---

## Task 7: Node Logs Partial

**Files:**
- Modify: `app/views/nodes/_logs.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Logs card | `nodes-logs-card` |
| Live indicator | `nodes-logs-live-indicator` |
| Log output container | `nodes-logs-output` |

**Commit:** `feat(nodes): add testid support to node logs partial`

---

## Task 8: Node Profiling Partial

**Files:**
- Modify: `app/views/nodes/_profiling.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Quick profiles section | `nodes-profiling-quick` |
| System report button | `nodes-profiling-button-report` |
| Telemetry button | `nodes-profiling-button-telemetry` |
| Flame graph button | `nodes-profiling-button-flame` |
| Custom profile link | `nodes-profiling-link-custom` |
| Recent runs table | `nodes-profiling-runs` |
| Recent runs tbody | `nodes-profiling-runs-tbody` |

**Commit:** `feat(nodes): add testid support to node profiling partial`

---

## Task 9: Node Form (New/Edit)

**Files:**
- Modify: `app/views/nodes/new.html.erb`
- Modify: `app/views/nodes/edit.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-form-modal` |
| Modal title | `nodes-form-title` |

Note: The NodeFormWizardComponent already supports testid parameter from Phase 1.

**Commit:** `feat(nodes): add testid support to node form modals`

---

## Task 10: Import Modal

**Files:**
- Modify: `app/views/nodes/imports/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-import-modal` |
| Requirements info | `nodes-import-requirements` |
| Error display | `nodes-import-errors` |
| File drop zone | `nodes-import-dropzone` |
| File input | `nodes-import-file` |
| Submit button | `nodes-import-submit` |
| Cancel button | `nodes-import-cancel` |

**Commit:** `feat(nodes): add testid support to import modal`

---

## Task 11: Install Agent Modal

**Files:**
- Modify: `app/views/nodes/installs/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-install-modal` |
| Requirements info | `nodes-install-requirements` |
| Security warning | `nodes-install-security` |
| Form | `nodes-install-form` |
| Sudo password field | `nodes-install-sudo-password` |
| SSH password field | `nodes-install-ssh-password` |
| API key select | `nodes-install-api-key` |
| Server URL field | `nodes-install-server-url` |
| Submit button | `nodes-install-submit` |

**Commit:** `feat(nodes): add testid support to install agent modal`

---

## Task 12: Update Agent Modal

**Files:**
- Modify: `app/views/nodes/updates/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-update-modal` |
| Status alert | `nodes-update-status` |
| Form | `nodes-update-form` |
| SSH password field | `nodes-update-ssh-password` |
| Sudo password field | `nodes-update-sudo-password` |
| Release selection | `nodes-update-releases` |
| Release radio (dynamic) | `nodes-update-release-{version}` |
| Force update checkbox | `nodes-update-force` |
| Submit button | `nodes-update-submit` |

**Commit:** `feat(nodes): add testid support to update agent modal`

---

## Task 13: Uninstall Agent Modal

**Files:**
- Modify: `app/views/nodes/uninstalls/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-uninstall-modal` |
| Confirmation alert | `nodes-uninstall-alert` |
| Credentials status | `nodes-uninstall-credentials` |
| Form | `nodes-uninstall-form` |
| Sudo password field | `nodes-uninstall-sudo-password` |
| SSH password field | `nodes-uninstall-ssh-password` |
| Submit button | `nodes-uninstall-submit` |

**Commit:** `feat(nodes): add testid support to uninstall agent modal`

---

## Task 14: Node Benchmark Runs Index

**Files:**
- Modify: `app/views/nodes/benchmark_runs/index.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Page container | `nodes-benchmarks-container` |
| Run benchmark button | `nodes-benchmarks-button-run` |
| Runs table | `nodes-benchmarks-table` |
| Table body | `nodes-benchmarks-tbody` |
| Pagination | `nodes-benchmarks-pagination` |
| Empty state | `nodes-benchmarks-empty` |

**Commit:** `feat(nodes): add testid support to node benchmark runs index`

---

## Task 15: Node Benchmark Run Modal

**Files:**
- Modify: `app/views/nodes/benchmark_runs/new.html.erb`

**Test IDs to add:**

| Element | Test ID |
|---------|---------|
| Modal container | `nodes-benchmark-modal` |
| Config summary | `nodes-benchmark-config` |
| Work dir value | `nodes-benchmark-workdir` |
| Agent path value | `nodes-benchmark-agentpath` |
| API token status | `nodes-benchmark-token-status` |
| Preflight checks | `nodes-benchmark-preflight` |
| Preflight alert | `nodes-benchmark-preflight-alert` |
| Edit settings link | `nodes-benchmark-link-settings` |
| Form | `nodes-benchmark-form` |
| Recipe select | `nodes-benchmark-recipe` |
| Recipe defaults | `nodes-benchmark-defaults` |
| Copy defaults button | `nodes-benchmark-copy-defaults` |
| Argument overrides | `nodes-benchmark-overrides` |
| Log path field | `nodes-benchmark-logpath` |
| Cancel button | `nodes-benchmark-cancel` |
| Submit button | `nodes-benchmark-submit` |

**Commit:** `feat(nodes): add testid support to node benchmark run modal`

---

## Task 16: Update Test ID Reference Document

**Files:**
- Modify: `docs/testing/test-id-reference.md`

Append the Nodes Module section with all test IDs documented above.

**Commit:** `docs: add nodes module test IDs to reference document`

---

## Task 17: Run Verification

**Step 1:** Run `bin/rails runner "puts 'Views load OK'"`
**Step 2:** Run `bin/rubocop app/views/nodes/`

---

## Success Criteria

- [ ] All 19 node view files have data-testid attributes
- [ ] Dynamic test IDs use hostname (not database ID)
- [ ] Test ID reference document updated
- [ ] All views load without syntax errors

---

## File Summary

| File | Test IDs |
|------|----------|
| `app/views/nodes/index.html.erb` | 4 |
| `app/views/nodes/_table.html.erb` | 10 |
| `app/views/nodes/_node.html.erb` | 14 (dynamic) |
| `app/views/nodes/show.html.erb` | 17 |
| `app/views/nodes/_overview.html.erb` | 6 |
| `app/views/nodes/_hardware.html.erb` | 9 |
| `app/views/nodes/_logs.html.erb` | 3 |
| `app/views/nodes/_profiling.html.erb` | 7 |
| `app/views/nodes/new.html.erb` | 2 |
| `app/views/nodes/edit.html.erb` | 2 |
| `app/views/nodes/imports/new.html.erb` | 7 |
| `app/views/nodes/installs/new.html.erb` | 9 |
| `app/views/nodes/updates/new.html.erb` | 9 |
| `app/views/nodes/uninstalls/new.html.erb` | 7 |
| `app/views/nodes/benchmark_runs/index.html.erb` | 6 |
| `app/views/nodes/benchmark_runs/new.html.erb` | 16 |
