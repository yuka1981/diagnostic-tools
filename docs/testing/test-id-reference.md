# Test ID Reference

This document catalogs all `data-testid` attributes available for E2E testing with Playwright.

## Usage with Playwright

```typescript
// Basic usage
await page.getByTestId('nodes-table-container').waitFor();

// Click a button
await page.getByTestId('nodes-wizard-button-next').click();

// Fill a form field (combine with other locators)
await page.getByTestId('nodes-field-hostname').locator('input').fill('compute-001');
```

## Shared Components

Components accept a `testid` parameter that serves as a prefix for all test IDs within that component.

### StatusBadgeComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-{status}` | Badge span (e.g., `nodes-badge-status-success`) |

**Usage:**
```erb
<%= render StatusBadgeComponent.new(status: :success, testid: "nodes-badge-status") %>
```

### EmptyStateComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}` | Container div |
| `{testid}-action` | Action button container |

**Usage:**
```erb
<%= render EmptyStateComponent.new(icon: "inbox", title: "No items", testid: "nodes-empty-state") %>
```

### CardComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-card` | Card container |
| `{testid}-card-header` | Card header |
| `{testid}-card-body` | Card body |

**Usage:**
```erb
<%= render CardComponent.new(title: "Stats", testid: "dashboard-stat") do %>
  Content here
<% end %>
```

### FormFieldComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}` | Field container |
| `{testid}-error` | Error message container |

**Usage:**
```erb
<%= render FormFieldComponent.new(form: f, attribute: :hostname, label: "Hostname", testid: "nodes-field-hostname") %>
```

### TableComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-table-container` | Outer container |
| `{testid}-table-header` | Table thead |
| `{testid}-table-body` | Table tbody |
| `{testid}-table-empty` | Empty state wrapper |
| `{testid}-bulk-actions` | Bulk action bar |

**Usage:**
```erb
<%= render TableComponent.new(collection: @nodes, testid: "nodes") do |table| %>
  <% table.with_column(header: "Hostname") { |node| node.hostname } %>
<% end %>
```

### SlideOverComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-container` | Modal panel |
| `{testid}-header` | Header section |
| `{testid}-close-button` | Close button |
| `{testid}-tabs` | Tab navigation |
| `{testid}-content` | Tab content area |

**Usage:**
```erb
<%= render SlideOverComponent.new(title: "Node Details", testid: "nodes-modal") do |c| %>
  <% c.with_tab(name: "Overview", active: true) { "Content" } %>
<% end %>
```

### NodeFormWizardComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-container` | Wizard container |
| `{testid}-form` | Form element |
| `{testid}-step-{n}` | Step indicator (1, 2, 3) |
| `{testid}-button-back` | Back button |
| `{testid}-button-next` | Next button |
| `{testid}-button-submit` | Submit button |
| `{testid}-button-cancel` | Cancel link |

**Usage:**
```erb
<%= render NodeFormWizardComponent.new(node: @node, testid: "nodes-wizard") %>
```

## Naming Convention

Test IDs follow the pattern: `{module}-{element}-{descriptor}`

- **module**: Feature area (e.g., `nodes`, `benchmark-runs`, `dashboard`)
- **element**: UI element type (e.g., `table`, `button`, `field`)
- **descriptor**: Specific identifier (e.g., `hostname`, `submit`, `status`)

### Examples

```
nodes-table-container
nodes-button-new
nodes-field-hostname
benchmark-runs-filter-status
dashboard-stat-total-nodes
```

## Dynamic Test IDs

For row-level elements, append a stable identifier (hostname, name) rather than database ID:

```erb
<%# Good: stable across environments %>
data-testid="nodes-row-<%= node.hostname %>"

<%# Avoid: database ID changes %>
data-testid="nodes-row-<%= node.id %>"
```

---

## Auth Module (Phase 2)

Auth views use static test IDs since they don't need dynamic prefixes.

### Login View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-logo` | Logo image |
| `auth-tab-login` | Login tab link |
| `auth-tab-signup` | Sign up tab link |
| `auth-flash-alert` | Flash alert message |
| `auth-form-login` | Login form |
| `auth-input-email` | Email input |
| `auth-input-password` | Password input |
| `auth-button-password-toggle` | Password visibility toggle |
| `auth-button-submit` | Submit button |
| `auth-link-forgot-password` | Forgot password link |
| `auth-link-sign-up` | Create account link |
| `auth-link-help` | Need help link |

**Playwright Example:**
```typescript
// Login flow
await page.getByTestId('auth-input-email').fill('user@example.com');
await page.getByTestId('auth-input-password').fill('password123');
await page.getByTestId('auth-button-submit').click();

// Check for error
await expect(page.getByTestId('auth-flash-alert')).toBeVisible();
```

### Registration View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-register` | Registration form |
| `auth-input-name` | Name input |
| `auth-input-email` | Email input |
| `auth-input-password` | Password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-button-submit` | Submit button |
| `auth-link-sign-in` | Sign in link |

### Forgot Password View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-forgot-password` | Forgot password form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |
| `auth-link-sign-in` | Back to login link |
| `auth-link-sign-up` | Create account link |

### Reset Password View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-reset-password` | Reset password form |
| `auth-input-password` | New password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-button-submit` | Submit button |

### Edit Profile View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-edit-profile` | Edit profile form |
| `auth-input-email` | Email input |
| `auth-input-password` | New password input |
| `auth-input-password-confirmation` | Password confirmation input |
| `auth-input-current-password` | Current password input |
| `auth-link-back` | Back link |
| `auth-button-submit` | Submit button |
| `auth-danger-zone` | Danger zone card |
| `auth-button-cancel-account` | Cancel account button |

### Confirmation View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-resend-confirmation` | Resend confirmation form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |

### Unlock View

| Test ID | Element |
|---------|---------|
| `auth-container` | Main container |
| `auth-form-resend-unlock` | Resend unlock form |
| `auth-input-email` | Email input |
| `auth-button-submit` | Submit button |

### Shared Elements

| Test ID | Element |
|---------|---------|
| `auth-error-message` | Error message container |
| `auth-link-sign-in` | Log in link (shared partial) |
| `auth-link-sign-up` | Sign up link (shared partial) |
| `auth-link-forgot-password` | Forgot password link (shared partial) |
| `auth-link-resend-confirmation` | Resend confirmation link |
| `auth-link-resend-unlock` | Resend unlock link |
| `auth-button-oauth-{provider}` | OmniAuth provider button |

---

## Nodes Module

The Nodes module provides node inventory management, monitoring, and benchmark execution.

### Nodes Index Page

| Test ID | Element |
|---------|---------|
| `nodes-page-container` | Page container |
| `nodes-button-new` | New node button |
| `nodes-button-import` | Import nodes button |
| `nodes-table-frame` | Turbo frame for nodes table |

### Nodes Table

| Test ID | Element |
|---------|---------|
| `nodes-bulk-actions` | Bulk actions bar |
| `nodes-bulk-count` | Selected count display |
| `nodes-bulk-clear` | Clear selection button |
| `nodes-bulk-delete` | Bulk delete button |
| `nodes-table` | Main table element |
| `nodes-table-header` | Table header (thead) |
| `nodes-table-body` | Table body (tbody) |
| `nodes-table-empty` | Empty state container |
| `nodes-empty-add` | Empty state add button |
| `nodes-empty-import` | Empty state import button |

### Node Row (dynamic with hostname)

| Test ID Pattern | Element |
|-----------------|---------|
| `nodes-row-{hostname}` | Table row |
| `nodes-checkbox-{hostname}` | Selection checkbox |
| `nodes-link-{hostname}` | Hostname link |
| `nodes-ip-{hostname}` | IP address cell |
| `nodes-role-{hostname}` | Role badge |
| `nodes-arch-{hostname}` | Architecture cell |
| `nodes-status-{hostname}` | Status badge |
| `nodes-last-seen-{hostname}` | Last seen timestamp |
| `nodes-button-install-{hostname}` | Install agent button |
| `nodes-button-update-{hostname}` | Update agent button |
| `nodes-button-uninstall-{hostname}` | Uninstall agent button |
| `nodes-button-collect-{hostname}` | Collect data button |
| `nodes-button-edit-{hostname}` | Edit node button |
| `nodes-button-delete-{hostname}` | Delete node button |

**Playwright Example:**
```typescript
// Select a specific node
await page.getByTestId('nodes-checkbox-compute-001').click();

// Check node status
await expect(page.getByTestId('nodes-status-compute-001')).toContainText('Online');

// Perform action on node
await page.getByTestId('nodes-button-collect-compute-001').click();
```

### Node Show Page

| Test ID | Element |
|---------|---------|
| `nodes-show-container` | Page container |
| `nodes-show-hostname` | Hostname heading |
| `nodes-show-status` | Status badge |
| `nodes-show-button-collect` | Collect data button |
| `nodes-show-button-benchmark` | Run benchmark button |
| `nodes-show-button-update` | Update agent button |
| `nodes-show-button-edit` | Edit node button |
| `nodes-show-button-delete` | Delete node button |
| `nodes-tab-overview` | Overview tab |
| `nodes-tab-hardware` | Hardware tab |
| `nodes-tab-benchmarks` | Benchmarks tab |
| `nodes-tab-logs` | Logs tab |
| `nodes-tab-profiling` | Profiling tab |
| `nodes-panel-overview` | Overview panel |
| `nodes-panel-hardware` | Hardware panel |
| `nodes-panel-benchmarks` | Benchmarks panel |
| `nodes-panel-logs` | Logs panel |
| `nodes-panel-profiling` | Profiling panel |

### Node Overview

| Test ID | Element |
|---------|---------|
| `nodes-overview-details` | Node details card |
| `nodes-overview-os` | OS information card |
| `nodes-overview-product` | Product information card |
| `nodes-overview-runs` | Recent runs card |
| `nodes-overview-runs-tbody` | Runs table body |
| `nodes-overview-runs-link` | Run detail link |

### Node Hardware

| Test ID | Element |
|---------|---------|
| `nodes-hardware-system` | System information card |
| `nodes-hardware-bios` | BIOS information card |
| `nodes-hardware-cpu` | CPU information card |
| `nodes-hardware-memory-os` | OS memory card |
| `nodes-hardware-memory-topology` | Memory topology card |
| `nodes-hardware-memory-toggle` | Memory devices toggle |
| `nodes-hardware-memory-devices` | Memory devices table |
| `nodes-hardware-network` | Network interfaces card |
| `nodes-hardware-storage` | Storage devices card |

### Node Logs

| Test ID | Element |
|---------|---------|
| `nodes-logs-card` | Logs container card |
| `nodes-logs-live-indicator` | Live streaming indicator |
| `nodes-logs-output` | Log output container |

### Node Profiling

| Test ID | Element |
|---------|---------|
| `nodes-profiling-quick` | Quick actions card |
| `nodes-profiling-button-report` | Generate report button |
| `nodes-profiling-button-telemetry` | View telemetry button |
| `nodes-profiling-button-flame` | Flame graph button |
| `nodes-profiling-link-custom` | Custom profiling link |
| `nodes-profiling-runs` | Profiling runs card |
| `nodes-profiling-runs-tbody` | Profiling runs table body |

### Node Form (New/Edit)

| Test ID | Element |
|---------|---------|
| `nodes-form-modal` | Form modal container |
| `nodes-form-title` | Modal title |

### Import Modal

| Test ID | Element |
|---------|---------|
| `nodes-import-modal` | Import modal container |
| `nodes-import-requirements` | Requirements section |
| `nodes-import-errors` | Error messages container |
| `nodes-import-dropzone` | File drop zone |
| `nodes-import-file` | File input |
| `nodes-import-submit` | Submit button |
| `nodes-import-cancel` | Cancel button |

### Install Agent Modal

| Test ID | Element |
|---------|---------|
| `nodes-install-modal` | Install modal container |
| `nodes-install-requirements` | Requirements section |
| `nodes-install-security` | Security information |
| `nodes-install-form` | Install form |
| `nodes-install-sudo-password` | Sudo password input |
| `nodes-install-ssh-password` | SSH password input |
| `nodes-install-api-key` | API key input |
| `nodes-install-server-url` | Server URL input |
| `nodes-install-submit` | Submit button |

### Update Agent Modal

| Test ID | Element |
|---------|---------|
| `nodes-update-modal` | Update modal container |
| `nodes-update-status` | Current status display |
| `nodes-update-form` | Update form |
| `nodes-update-ssh-password` | SSH password input |
| `nodes-update-sudo-password` | Sudo password input |
| `nodes-update-releases` | Available releases list |
| `nodes-update-release-{version}` | Release version option |
| `nodes-update-force` | Force update checkbox |
| `nodes-update-submit` | Submit button |

### Uninstall Agent Modal

| Test ID | Element |
|---------|---------|
| `nodes-uninstall-modal` | Uninstall modal container |
| `nodes-uninstall-alert` | Warning alert |
| `nodes-uninstall-credentials` | Credentials section |
| `nodes-uninstall-form` | Uninstall form |
| `nodes-uninstall-sudo-password` | Sudo password input |
| `nodes-uninstall-ssh-password` | SSH password input |
| `nodes-uninstall-submit` | Submit button |

### Node Benchmark Runs Index

| Test ID | Element |
|---------|---------|
| `nodes-benchmarks-container` | Benchmarks page container |
| `nodes-benchmarks-button-run` | Run benchmark button |
| `nodes-benchmarks-table` | Benchmark runs table |
| `nodes-benchmarks-tbody` | Benchmark runs table body |
| `nodes-benchmarks-pagination` | Pagination controls |
| `nodes-benchmarks-empty` | Empty state container |

### Node Benchmark Run Modal

| Test ID | Element |
|---------|---------|
| `nodes-benchmark-modal` | Benchmark modal container |
| `nodes-benchmark-config` | Configuration section |
| `nodes-benchmark-workdir` | Working directory display |
| `nodes-benchmark-agentpath` | Agent path display |
| `nodes-benchmark-token-status` | Token status indicator |
| `nodes-benchmark-preflight` | Preflight check section |
| `nodes-benchmark-preflight-alert` | Preflight alert |
| `nodes-benchmark-link-settings` | Settings link |
| `nodes-benchmark-form` | Benchmark form |
| `nodes-benchmark-recipe` | Recipe selector |
| `nodes-benchmark-defaults` | Default parameters section |
| `nodes-benchmark-copy-defaults` | Copy defaults button |
| `nodes-benchmark-overrides` | Parameter overrides input |
| `nodes-benchmark-logpath` | Log path input |
| `nodes-benchmark-cancel` | Cancel button |
| `nodes-benchmark-submit` | Submit button |

---

## Benchmark Recipes Module

The Benchmark Recipes module manages benchmark configurations with slug-based identification for stable E2E test IDs.

### Recipes Index Page

| Test ID | Element |
|---------|---------|
| `recipes-page-container` | Page container |
| `recipes-button-new` | New recipe button |
| `recipes-table` | Main table element |
| `recipes-table-header` | Table header (thead) |
| `recipes-table-body` | Table body (tbody) |
| `recipes-table-empty` | Empty state container |
| `recipes-empty-add` | Empty state add button |

### Recipe Row (dynamic with slug)

| Test ID Pattern | Element |
|-----------------|---------|
| `recipes-row-{slug}` | Table row |
| `recipes-link-{slug}` | Recipe name link |
| `recipes-command-{slug}` | Command cell |
| `recipes-status-{slug}` | Status badge |
| `recipes-button-view-{slug}` | View recipe button |
| `recipes-button-edit-{slug}` | Edit recipe button |

**Playwright Example:**
```typescript
// Click on a specific recipe
await page.getByTestId('recipes-link-hpcg-benchmark').click();

// Check recipe status
await expect(page.getByTestId('recipes-status-hpcg-benchmark')).toContainText('Active');

// Edit a recipe
await page.getByTestId('recipes-button-edit-hpcg-benchmark').click();
```

### Recipes Show Page

| Test ID | Element |
|---------|---------|
| `recipes-show-container` | Page container |
| `recipes-show-name` | Recipe name heading |
| `recipes-show-status` | Status badge |
| `recipes-show-button-edit` | Edit recipe button |
| `recipes-show-button-archive` | Archive recipe button |
| `recipes-show-button-activate` | Activate recipe button |
| `recipes-show-overview` | Overview section card |
| `recipes-show-technical` | Technical details card |
| `recipes-show-profile` | Profile section card |
| `recipes-show-profile-json` | Profile JSON display |
| `recipes-show-danger-zone` | Danger zone card |
| `recipes-show-button-delete` | Delete recipe button |

### Recipes Form

| Test ID | Element |
|---------|---------|
| `recipes-form` | Form element |
| `recipes-form-errors` | Form errors container |
| `recipes-input-name` | Name input |
| `recipes-input-version` | Version input |
| `recipes-input-description` | Description textarea |
| `recipes-input-slug` | Slug input |
| `recipes-select-status` | Status select |
| `recipes-input-command` | Command input |
| `recipes-input-timeout` | Timeout input |
| `recipes-input-profile` | Profile JSON input |
| `recipes-button-cancel` | Cancel button |
| `recipes-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Fill out recipe form
await page.getByTestId('recipes-input-name').fill('HPCG Benchmark');
await page.getByTestId('recipes-input-slug').fill('hpcg-benchmark');
await page.getByTestId('recipes-input-command').fill('hpcg --n 256');
await page.getByTestId('recipes-select-status').selectOption('active');
await page.getByTestId('recipes-button-submit').click();
```

### Recipes New Page

| Test ID | Element |
|---------|---------|
| `recipes-new-container` | Page container |
| `recipes-new-title` | Page title |

### Recipes Edit Page

| Test ID | Element |
|---------|---------|
| `recipes-edit-container` | Page container |
| `recipes-edit-title` | Page title |

---

## Benchmark Runs Module

The Benchmark Runs module displays benchmark execution history with filtering, pagination, and detailed run information via slide-over panels.

### Benchmark Runs Index Page

| Test ID | Element |
|---------|---------|
| `benchmark-runs-page-container` | Page container |
| `benchmark-runs-filter-form` | Filter form |
| `benchmark-runs-filter-search` | Search input |
| `benchmark-runs-filter-status` | Status filter select |
| `benchmark-runs-filter-node` | Node filter select |
| `benchmark-runs-filter-recipe` | Recipe filter select |
| `benchmark-runs-button-search` | Search button |
| `benchmark-runs-button-clear` | Clear filters button |
| `benchmark-runs-results-summary` | Results summary text |
| `benchmark-runs-table` | Main table element |
| `benchmark-runs-table-header` | Table header (thead) |
| `benchmark-runs-table-body` | Table body (tbody) |
| `benchmark-runs-table-empty` | Empty state container |
| `benchmark-runs-pagination` | Pagination container |
| `benchmark-runs-pagination-prev` | Previous page button |
| `benchmark-runs-pagination-next` | Next page button |
| `benchmark-runs-slideover` | Slide-over container |

### Run Row (dynamic with ID)

| Test ID Pattern | Element |
|-----------------|---------|
| `benchmark-runs-row-{id}` | Table row |
| `benchmark-runs-id-{id}` | Run ID cell |
| `benchmark-runs-recipe-{id}` | Recipe name cell |
| `benchmark-runs-hostname-{id}` | Hostname cell |
| `benchmark-runs-status-{id}` | Status badge |
| `benchmark-runs-gflops-{id}` | GFLOPS metric cell |
| `benchmark-runs-duration-{id}` | Duration cell |
| `benchmark-runs-created-{id}` | Created timestamp cell |
| `benchmark-runs-button-cancel-{id}` | Cancel run button |
| `benchmark-runs-button-view-{id}` | View run button |

**Playwright Example:**
```typescript
// Click on a specific run
await page.getByTestId('benchmark-runs-row-123').click();

// Check run status
await expect(page.getByTestId('benchmark-runs-status-123')).toContainText('Completed');

// Cancel a running benchmark
await page.getByTestId('benchmark-runs-button-cancel-456').click();
```

### Benchmark Runs Show Page

| Test ID | Element |
|---------|---------|
| `benchmark-runs-show-container` | Page container |
| `benchmark-runs-show-status-icon` | Status icon |
| `benchmark-runs-show-recipe` | Recipe name display |
| `benchmark-runs-show-status` | Status badge |
| `benchmark-runs-show-button-cancel` | Cancel run button |
| `benchmark-runs-show-details` | Details card |
| `benchmark-runs-show-results` | Results card |
| `benchmark-runs-show-error` | Error display card |
| `benchmark-runs-show-config` | Configuration card |
| `benchmark-runs-show-logs` | Logs card |
| `benchmark-runs-show-logs-toggle` | Logs expand/collapse toggle |
| `benchmark-runs-show-logs-content` | Logs content container |
| `benchmark-runs-show-artifacts` | Artifacts card |
| `benchmark-runs-show-artifacts-table` | Artifacts table |

### Results Card

| Test ID | Element |
|---------|---------|
| `benchmark-runs-results-card` | Results card container |
| `benchmark-runs-results-badge` | Results status badge |
| `benchmark-runs-results-waiting` | Waiting for results indicator |
| `benchmark-runs-results-spinner` | Loading spinner |
| `benchmark-runs-results-phase` | Current phase display |
| `benchmark-runs-results-metrics` | Metrics container |
| `benchmark-runs-results-empty` | Empty results state |
| `benchmark-runs-metric-{key}` | Metric label (dynamic) |
| `benchmark-runs-metric-value-{key}` | Metric value (dynamic) |

**Playwright Example:**
```typescript
// Wait for results to load
await page.getByTestId('benchmark-runs-results-card').waitFor();

// Check specific metric
await expect(page.getByTestId('benchmark-runs-metric-value-gflops')).toContainText('125.6');
```

### Configuration Card

| Test ID | Element |
|---------|---------|
| `benchmark-runs-config-card` | Configuration card container |
| `benchmark-runs-config-recipe` | Recipe configuration display |
| `benchmark-runs-config-command` | Command display |
| `benchmark-runs-config-timeout` | Timeout display |
| `benchmark-runs-config-args` | Arguments display |

### Slide-over

| Test ID | Element |
|---------|---------|
| `benchmark-runs-slideover-backdrop` | Slide-over backdrop |
| `benchmark-runs-slideover-panel` | Slide-over panel |
| `benchmark-runs-slideover-title` | Slide-over title |
| `benchmark-runs-slideover-close` | Close button |
| `benchmark-runs-slideover-content` | Content container |

### Slide-over Content

| Test ID | Element |
|---------|---------|
| `benchmark-runs-slideover-content-frame` | Content turbo frame |
| `benchmark-runs-slideover-header` | Header section |
| `benchmark-runs-slideover-recipe` | Recipe name display |
| `benchmark-runs-slideover-status` | Status badge |
| `benchmark-runs-slideover-cancel` | Cancel button |
| `benchmark-runs-slideover-tabs` | Tab navigation |
| `benchmark-runs-tab-summary` | Summary tab |
| `benchmark-runs-tab-metrics` | Metrics tab |
| `benchmark-runs-tab-logs` | Logs tab |
| `benchmark-runs-tab-artifacts` | Artifacts tab |
| `benchmark-runs-panel-summary` | Summary panel |
| `benchmark-runs-panel-metrics` | Metrics panel |
| `benchmark-runs-panel-logs` | Logs panel |
| `benchmark-runs-panel-artifacts` | Artifacts panel |
| `benchmark-runs-slideover-error` | Error display |
| `benchmark-runs-slideover-details` | Details section |
| `benchmark-runs-slideover-metrics` | Metrics section |
| `benchmark-runs-slideover-logs` | Logs section |
| `benchmark-runs-slideover-artifacts` | Artifacts section |
| `benchmark-runs-slideover-view-full` | View full page link |

**Playwright Example:**
```typescript
// Open slide-over from table row
await page.getByTestId('benchmark-runs-button-view-123').click();
await page.getByTestId('benchmark-runs-slideover-panel').waitFor();

// Switch tabs
await page.getByTestId('benchmark-runs-tab-logs').click();
await expect(page.getByTestId('benchmark-runs-panel-logs')).toBeVisible();

// Close slide-over
await page.getByTestId('benchmark-runs-slideover-close').click();
```

---

## Dashboard Module

The Dashboard module provides an overview of the HPC cluster with availability stats, a node heatmap, and recent benchmark runs.

### Dashboard Index Page

| Test ID | Element |
|---------|---------|
| `dashboard-page-container` | Main page container |
| `dashboard-stat-availability` | Availability stat card |
| `dashboard-stat-availability-value` | Availability percentage value |
| `dashboard-stat-availability-bar` | Availability progress bar |
| `dashboard-stat-health` | Health stat card |
| `dashboard-stat-health-value` | Health percentage value |
| `dashboard-stat-health-bar` | Health progress bar |
| `dashboard-stat-queue` | Queue stat card |
| `dashboard-stat-queue-total` | Total queue count |
| `dashboard-stat-queue-active` | Active queue count |
| `dashboard-stat-queue-pending` | Pending queue count |
| `dashboard-stat-storage` | Storage stat card |
| `dashboard-stat-storage-value` | Storage usage value |
| `dashboard-stat-storage-bar` | Storage usage bar |
| `dashboard-quick-actions` | Quick actions section |
| `dashboard-action-nodes` | Nodes quick action button |
| `dashboard-action-runs` | Runs quick action button |
| `dashboard-action-recipes` | Recipes quick action button |
| `dashboard-action-import` | Import quick action button |

**Playwright Example:**
```typescript
// Check dashboard stats
await page.getByTestId('dashboard-page-container').waitFor();
await expect(page.getByTestId('dashboard-stat-availability-value')).toContainText('%');

// Navigate via quick actions
await page.getByTestId('dashboard-action-nodes').click();
```

### Heatmap

#### Static Elements

| Test ID | Element |
|---------|---------|
| `dashboard-heatmap-container` | Heatmap container |
| `dashboard-heatmap-title` | Heatmap section title |
| `dashboard-heatmap-selected` | Selected nodes count display |
| `dashboard-heatmap-clear` | Clear selection button |
| `dashboard-heatmap-grid` | Heatmap grid container |
| `dashboard-heatmap-summary` | Heatmap summary section |
| `dashboard-heatmap-empty` | Empty state when no nodes |

#### Dynamic Elements

| Test ID Pattern | Element |
|-----------------|---------|
| `dashboard-heatmap-role-{role}` | Role section container |
| `dashboard-heatmap-role-label-{role}` | Role section label |
| `dashboard-heatmap-node-{hostname}` | Individual node cell |

**Playwright Example:**
```typescript
// Check heatmap loads
await page.getByTestId('dashboard-heatmap-container').waitFor();

// Click on a specific node
await page.getByTestId('dashboard-heatmap-node-compute-001').click();

// Check selection count
await expect(page.getByTestId('dashboard-heatmap-selected')).toContainText('1');

// Clear selection
await page.getByTestId('dashboard-heatmap-clear').click();
```

### Filtered Runs

#### Static Elements

| Test ID | Element |
|---------|---------|
| `dashboard-runs-frame` | Runs section turbo frame |
| `dashboard-runs-heading` | Runs section heading |
| `dashboard-runs-view-all` | View all runs link |
| `dashboard-runs-list` | Runs list container |
| `dashboard-runs-empty` | Empty state when no runs |

#### Dynamic Elements

| Test ID Pattern | Element |
|-----------------|---------|
| `dashboard-run-{id}` | Run row container |
| `dashboard-run-status-{id}` | Run status badge |
| `dashboard-run-recipe-{id}` | Run recipe name |
| `dashboard-run-hostname-{id}` | Run hostname |
| `dashboard-run-time-{id}` | Run timestamp |
| `dashboard-run-badge-{id}` | Run result badge |

**Playwright Example:**
```typescript
// Wait for runs to load
await page.getByTestId('dashboard-runs-frame').waitFor();

// Check specific run
await expect(page.getByTestId('dashboard-run-status-123')).toContainText('Completed');

// Click on a run
await page.getByTestId('dashboard-run-123').click();

// Navigate to all runs
await page.getByTestId('dashboard-runs-view-all').click();
```

---

## Infrastructure Module

The Infrastructure module manages physical locations (Sites and Rooms) for organizing HPC cluster resources.

### Sites Index Page

#### Static Elements

| Test ID | Element |
|---------|---------|
| `sites-page-container` | Page container |
| `sites-button-new` | New site button |
| `sites-table` | Main table element |
| `sites-table-header` | Table header (thead) |
| `sites-table-body` | Table body (tbody) |
| `sites-table-empty` | Empty state container |
| `sites-empty-add` | Empty state add button |

#### Dynamic Elements (by name)

| Test ID Pattern | Element |
|-----------------|---------|
| `sites-row-{name}` | Table row |
| `sites-link-{name}` | Site name link |
| `sites-rooms-{name}` | Rooms count cell |
| `sites-nodes-{name}` | Nodes count cell |
| `sites-button-view-{name}` | View site button |
| `sites-button-edit-{name}` | Edit site button |

**Playwright Example:**
```typescript
// Click on a specific site
await page.getByTestId('sites-link-datacenter-west').click();

// Check site rooms count
await expect(page.getByTestId('sites-rooms-datacenter-west')).toContainText('5');

// Edit a site
await page.getByTestId('sites-button-edit-datacenter-west').click();
```

### Sites Show Page

| Test ID | Element |
|---------|---------|
| `sites-show-container` | Page container |
| `sites-show-name` | Site name heading |
| `sites-show-button-edit` | Edit site button |
| `sites-show-button-add-room` | Add room button |
| `sites-show-overview` | Overview section card |
| `sites-show-statistics` | Statistics section card |
| `sites-show-rooms` | Rooms section card |
| `sites-show-rooms-table` | Rooms table element |
| `sites-show-rooms-tbody` | Rooms table body |
| `sites-show-rooms-empty` | Empty state when no rooms |
| `sites-show-danger-zone` | Danger zone card |
| `sites-show-button-delete` | Delete site button |

#### Dynamic Elements (by name)

| Test ID Pattern | Element |
|-----------------|---------|
| `sites-room-row-{name}` | Room table row |
| `sites-room-link-{name}` | Room name link |

**Playwright Example:**
```typescript
// View site details
await page.getByTestId('sites-show-container').waitFor();
await expect(page.getByTestId('sites-show-name')).toContainText('Datacenter West');

// Add a new room
await page.getByTestId('sites-show-button-add-room').click();

// Click on a room
await page.getByTestId('sites-room-link-server-room-a').click();
```

### Sites Form

| Test ID | Element |
|---------|---------|
| `sites-form` | Form element |
| `sites-form-errors` | Form errors container |
| `sites-input-name` | Name input |
| `sites-input-description` | Description textarea |
| `sites-button-cancel` | Cancel button |
| `sites-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Fill out site form
await page.getByTestId('sites-input-name').fill('Datacenter East');
await page.getByTestId('sites-input-description').fill('Primary east coast facility');
await page.getByTestId('sites-button-submit').click();
```

### Sites New Page

| Test ID | Element |
|---------|---------|
| `sites-new-container` | Page container |
| `sites-new-title` | Page title |

### Sites Edit Page

| Test ID | Element |
|---------|---------|
| `sites-edit-container` | Page container |
| `sites-edit-title` | Page title |

---

### Rooms Index Page

#### Static Elements

| Test ID | Element |
|---------|---------|
| `rooms-page-container` | Page container |
| `rooms-button-new` | New room button |
| `rooms-filter-site` | Site filter select |
| `rooms-filter-clear` | Clear filter button |
| `rooms-table` | Main table element |
| `rooms-table-header` | Table header (thead) |
| `rooms-table-body` | Table body (tbody) |
| `rooms-table-empty` | Empty state container |
| `rooms-empty-add` | Empty state add button |

#### Dynamic Elements (by name)

| Test ID Pattern | Element |
|-----------------|---------|
| `rooms-row-{name}` | Table row |
| `rooms-link-{name}` | Room name link |
| `rooms-site-{name}` | Site name cell |
| `rooms-racks-{name}` | Racks count cell |
| `rooms-utilization-{name}` | Utilization percentage cell |
| `rooms-button-view-{name}` | View room button |
| `rooms-button-edit-{name}` | Edit room button |

**Playwright Example:**
```typescript
// Filter rooms by site
await page.getByTestId('rooms-filter-site').selectOption('datacenter-west');

// Click on a specific room
await page.getByTestId('rooms-link-server-room-a').click();

// Check room utilization
await expect(page.getByTestId('rooms-utilization-server-room-a')).toContainText('%');

// Clear filter
await page.getByTestId('rooms-filter-clear').click();
```

### Rooms Show Page

| Test ID | Element |
|---------|---------|
| `rooms-show-container` | Page container |
| `rooms-show-name` | Room name heading |
| `rooms-show-capacity-badge` | Capacity badge |
| `rooms-show-button-edit` | Edit room button |
| `rooms-show-button-add-rack` | Add rack button |
| `rooms-show-overview` | Overview section card |
| `rooms-show-capacity` | Capacity section card |
| `rooms-show-racks` | Racks section card |
| `rooms-show-racks-table` | Racks table element |
| `rooms-show-racks-tbody` | Racks table body |
| `rooms-show-racks-empty` | Empty state when no racks |
| `rooms-show-danger-zone` | Danger zone card |
| `rooms-show-button-delete` | Delete room button |

#### Dynamic Elements (by name)

| Test ID Pattern | Element |
|-----------------|---------|
| `rooms-rack-row-{name}` | Rack table row |
| `rooms-rack-link-{name}` | Rack name link |

**Playwright Example:**
```typescript
// View room details
await page.getByTestId('rooms-show-container').waitFor();
await expect(page.getByTestId('rooms-show-name')).toContainText('Server Room A');

// Check capacity badge
await expect(page.getByTestId('rooms-show-capacity-badge')).toBeVisible();

// Add a new rack
await page.getByTestId('rooms-show-button-add-rack').click();

// Click on a rack
await page.getByTestId('rooms-rack-link-rack-01').click();
```

### Rooms Form

| Test ID | Element |
|---------|---------|
| `rooms-form` | Form element |
| `rooms-form-errors` | Form errors container |
| `rooms-select-site` | Site select dropdown |
| `rooms-input-name` | Name input |
| `rooms-input-description` | Description textarea |
| `rooms-input-floor` | Floor input |
| `rooms-input-wing` | Wing input |
| `rooms-input-grid` | Grid reference input |
| `rooms-input-area` | Area (sq ft) input |
| `rooms-input-max-racks` | Max racks input |
| `rooms-input-power` | Power capacity input |
| `rooms-input-cooling` | Cooling capacity input |
| `rooms-button-cancel` | Cancel button |
| `rooms-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Fill out room form
await page.getByTestId('rooms-select-site').selectOption('datacenter-west');
await page.getByTestId('rooms-input-name').fill('Server Room B');
await page.getByTestId('rooms-input-floor').fill('2');
await page.getByTestId('rooms-input-max-racks').fill('50');
await page.getByTestId('rooms-input-power').fill('500');
await page.getByTestId('rooms-button-submit').click();
```

### Rooms New Page

| Test ID | Element |
|---------|---------|
| `rooms-new-container` | Page container |
| `rooms-new-title` | Page title |

### Rooms Edit Page

| Test ID | Element |
|---------|---------|
| `rooms-edit-container` | Page container |
| `rooms-edit-title` | Page title |

---

## Settings & Admin Module

The Settings & Admin module manages SSH defaults, agent configuration, agent releases, server products, and API keys.

### SSH Settings Page

| Test ID | Element |
|---------|---------|
| `ssh-settings-container` | Page container |
| `ssh-settings-form` | Settings form |
| `ssh-settings-input-bastion-host` | Bastion host input |
| `ssh-settings-input-bastion-user` | Bastion user input |
| `ssh-settings-input-bastion-port` | Bastion port input |
| `ssh-settings-input-user` | SSH user input |
| `ssh-settings-input-port` | SSH port input |
| `ssh-settings-input-key` | SSH key textarea |
| `ssh-settings-input-password` | SSH password input |
| `ssh-settings-input-sudo` | Sudo credential input |
| `ssh-settings-input-timeout` | Timeout input |
| `ssh-settings-checkbox-verify` | Verify host key checkbox |
| `ssh-settings-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Configure SSH settings
await page.getByTestId('ssh-settings-input-bastion-host').fill('bastion.example.com');
await page.getByTestId('ssh-settings-input-user').fill('admin');
await page.getByTestId('ssh-settings-checkbox-verify').check();
await page.getByTestId('ssh-settings-button-submit').click();
```

### Agent Configuration Page

| Test ID | Element |
|---------|---------|
| `agent-config-container` | Page container |
| `agent-config-form` | Configuration form |
| `agent-config-input-url` | Server URL input |
| `agent-config-input-path` | Agent path input |
| `agent-config-input-workdir` | Working directory input |
| `agent-config-button-submit` | Submit button |
| `agent-config-releases` | Releases section |
| `agent-config-button-new-release` | New release button |

**Playwright Example:**
```typescript
// Configure agent settings
await page.getByTestId('agent-config-input-url').fill('https://hpc-portal.com');
await page.getByTestId('agent-config-input-path').fill('/usr/local/bin/hpc-agent');
await page.getByTestId('agent-config-button-submit').click();
```

### Agent Releases Index Page

#### Static Elements

| Test ID | Element |
|---------|---------|
| `agent-releases-container` | Page container |
| `agent-releases-button-new` | New release button |
| `agent-releases-table` | Main table element |
| `agent-releases-table-header` | Table header (thead) |
| `agent-releases-table-body` | Table body (tbody) |
| `agent-releases-empty` | Empty state container |

#### Dynamic Elements (by version)

| Test ID Pattern | Element |
|-----------------|---------|
| `agent-releases-row-{version}` | Table row |
| `agent-releases-version-{version}` | Version cell link |
| `agent-releases-status-{version}` | Status badge |
| `agent-releases-button-view-{version}` | View release button |
| `agent-releases-button-edit-{version}` | Edit release button |

**Playwright Example:**
```typescript
// Click on a specific release
await page.getByTestId('agent-releases-version-v1.2.0').click();

// Check release status
await expect(page.getByTestId('agent-releases-status-v1.2.0')).toContainText('Active');

// Edit a release
await page.getByTestId('agent-releases-button-edit-v1.2.0').click();
```

### Agent Releases Show Page

| Test ID | Element |
|---------|---------|
| `agent-releases-show-container` | Page container |
| `agent-releases-show-version` | Version heading |
| `agent-releases-show-status` | Status badge |
| `agent-releases-show-latest` | Latest badge |
| `agent-releases-show-button-edit` | Edit release button |
| `agent-releases-show-button-deprecate` | Deprecate button |
| `agent-releases-show-button-activate` | Activate button |
| `agent-releases-show-button-recall` | Recall button |
| `agent-releases-show-overview` | Overview card |
| `agent-releases-show-binaries` | Binaries card |
| `agent-releases-show-binaries-table` | Binaries table |
| `agent-releases-show-copy-checksum` | Copy checksum button |
| `agent-releases-show-notes` | Release notes card |
| `agent-releases-show-danger` | Danger zone card |
| `agent-releases-show-button-delete` | Delete release button |

#### Dynamic Elements (by architecture)

| Test ID Pattern | Element |
|-----------------|---------|
| `agent-releases-binary-{arch}` | Binary row |
| `agent-releases-download-{arch}` | Download button |

**Playwright Example:**
```typescript
// View release details
await page.getByTestId('agent-releases-show-container').waitFor();
await expect(page.getByTestId('agent-releases-show-version')).toContainText('v1.2.0');

// Download a binary
await page.getByTestId('agent-releases-download-linux-amd64').click();

// Deprecate a release
await page.getByTestId('agent-releases-show-button-deprecate').click();
```

### Agent Releases Form

| Test ID | Element |
|---------|---------|
| `agent-releases-form` | Form element |
| `agent-releases-form-errors` | Form errors container |
| `agent-releases-input-version` | Version input |
| `agent-releases-select-status` | Status select |
| `agent-releases-input-binary` | Binary file input |
| `agent-releases-input-notes` | Release notes textarea |
| `agent-releases-button-cancel` | Cancel button |
| `agent-releases-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Fill out release form
await page.getByTestId('agent-releases-input-version').fill('v1.3.0');
await page.getByTestId('agent-releases-input-binary').setInputFiles('agent-v1.3.0');
await page.getByTestId('agent-releases-input-notes').fill('## What\'s New\n\n- Feature 1');
await page.getByTestId('agent-releases-button-submit').click();
```

### Server Products Index Page

#### Static Elements

| Test ID | Element |
|---------|---------|
| `server-products-container` | Page container |
| `server-products-button-sync` | Sync from QCT button |
| `server-products-button-new` | Add product button |
| `server-products-last-sync` | Last sync timestamp |
| `server-products-filter-form` | Filter form |
| `server-products-filter-search` | Search input |
| `server-products-filter-series` | Series filter select |
| `server-products-filter-form-factor` | Form factor filter select |
| `server-products-button-filter` | Filter button |
| `server-products-button-clear` | Clear button |
| `server-products-table` | Main table element |
| `server-products-table-body` | Table body (tbody) |
| `server-products-empty` | Empty state container |
| `server-products-pagination` | Pagination container |

#### Dynamic Elements (by parameterized name)

| Test ID Pattern | Element |
|-----------------|---------|
| `server-products-row-{name}` | Table row |
| `server-products-name-{name}` | Product name link |
| `server-products-button-view-{name}` | View product button |
| `server-products-button-edit-{name}` | Edit product button |

**Playwright Example:**
```typescript
// Filter products
await page.getByTestId('server-products-filter-search').fill('QuantaGrid');
await page.getByTestId('server-products-filter-series').selectOption('QuantaGrid');
await page.getByTestId('server-products-button-filter').click();

// Click on a specific product
await page.getByTestId('server-products-name-quantagrid-d54q-2u').click();

// Clear filters
await page.getByTestId('server-products-button-clear').click();
```

### Server Products Form

| Test ID | Element |
|---------|---------|
| `server-products-form` | Form element |
| `server-products-form-errors` | Form errors container |
| `server-products-input-name` | Name input |
| `server-products-input-series` | Series input |
| `server-products-select-form-factor` | Form factor select |
| `server-products-input-rack-height` | Rack height input |
| `server-products-input-url` | QCT URL input |
| `server-products-input-cpu-gen` | CPU generations input |
| `server-products-select-sockets` | Socket count select |
| `server-products-input-tdp` | Max TDP input |
| `server-products-checkbox-gpu` | GPU support checkbox |
| `server-products-input-max-memory` | Max memory input |
| `server-products-input-dimm-slots` | DIMM slots input |
| `server-products-input-memory-types` | Memory types input |
| `server-products-input-memory-speed` | Memory speed input |
| `server-products-input-images` | Images file input |
| `server-products-button-cancel` | Cancel button |
| `server-products-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Fill out product form
await page.getByTestId('server-products-input-name').fill('QuantaGrid D54Q-2U');
await page.getByTestId('server-products-input-series').fill('QuantaGrid');
await page.getByTestId('server-products-select-form-factor').selectOption('2U');
await page.getByTestId('server-products-input-cpu-gen').fill('5th Gen Xeon');
await page.getByTestId('server-products-checkbox-gpu').check();
await page.getByTestId('server-products-button-submit').click();
```

### API Keys Index Page

#### Static Elements

| Test ID | Element |
|---------|---------|
| `api-keys-container` | Page container |
| `api-keys-button-new` | Generate key button |
| `api-keys-table` | Main table element |
| `api-keys-table-header` | Table header (thead) |
| `api-keys-table-body` | Table body (tbody) |
| `api-keys-empty` | Empty state container |

#### Dynamic Elements (by parameterized name)

| Test ID Pattern | Element |
|-----------------|---------|
| `api-keys-row-{name}` | Table row |
| `api-keys-name-{name}` | Name cell |
| `api-keys-token-{name}` | Token display |
| `api-keys-status-{name}` | Status badge |
| `api-keys-last-used-{name}` | Last used cell |
| `api-keys-button-revoke-{name}` | Revoke button |
| `api-keys-button-delete-{name}` | Delete button |

**Playwright Example:**
```typescript
// Generate a new API key
await page.getByTestId('api-keys-button-new').click();

// Check key status
await expect(page.getByTestId('api-keys-status-cluster-alpha')).toContainText('Active');

// Revoke a key
await page.getByTestId('api-keys-button-revoke-cluster-alpha').click();

// Delete a revoked key
await page.getByTestId('api-keys-button-delete-cluster-alpha').click();
```

### API Keys New Page

| Test ID | Element |
|---------|---------|
| `api-keys-new-container` | Page container |
| `api-keys-form` | Form element |
| `api-keys-form-errors` | Form errors container |
| `api-keys-input-name` | Name input |
| `api-keys-button-cancel` | Cancel button |
| `api-keys-button-generate` | Generate button |

**Playwright Example:**
```typescript
// Generate a new API key
await page.getByTestId('api-keys-input-name').fill('Compute Cluster Alpha');
await page.getByTestId('api-keys-button-generate').click();
```

---

## Supporting Features Module

The Supporting Features module covers Tasks, Notifications, and Profiling views.

### Tasks Index Page

| Test ID | Element |
|---------|---------|
| `tasks-page-container` | Page container |
| `tasks-auto-refresh` | Auto-refresh control |
| `tasks-filter-frame` | Filter bar frame |
| `tasks-list-frame` | Tasks list turbo frame |
| `tasks-filter-summary` | Filter summary text |
| `tasks-table` | Main table element |
| `tasks-table-header` | Table header (thead) |
| `tasks-table-body` | Table body (tbody) |
| `tasks-table-empty` | Empty state container |
| `tasks-pagination` | Pagination controls |
| `tasks-per-page` | Per-page selector |

### Tasks Filter Bar

| Test ID | Element |
|---------|---------|
| `tasks-filter-form` | Filter form |
| `tasks-filter-search` | Search input |
| `tasks-filter-type` | Type filter select |
| `tasks-filter-status` | Status filter select |
| `tasks-filter-node` | Node filter select |
| `tasks-filter-recipe` | Recipe filter select |
| `tasks-filter-date` | Date range filter select |
| `tasks-button-search` | Search button |
| `tasks-button-clear` | Clear filters button |

**Playwright Example:**
```typescript
// Filter tasks by status
await page.getByTestId('tasks-filter-status').selectOption('running');

// Search for a task
await page.getByTestId('tasks-filter-search').fill('hpcg');
await page.getByTestId('tasks-button-search').click();

// Clear all filters
await page.getByTestId('tasks-button-clear').click();
```

### Task Row (dynamic with task ID)

| Test ID Pattern | Element |
|-----------------|---------|
| `tasks-row-{id}` | Table row |
| `tasks-expand-{id}` | Expand toggle |
| `tasks-type-{id}` | Type badge |
| `tasks-hostname-{id}` | Hostname link |
| `tasks-recipe-{id}` | Recipe name |
| `tasks-status-{id}` | Status badge |
| `tasks-started-{id}` | Started time |
| `tasks-duration-{id}` | Duration |
| `tasks-button-rerun-{id}` | Re-run button |
| `tasks-button-view-node-{id}` | View node button |
| `tasks-button-cancel-{id}` | Cancel button |
| `tasks-button-delete-{id}` | Delete button |

**Playwright Example:**
```typescript
// Expand a task row
await page.getByTestId('tasks-expand-42').click();

// Check task status
await expect(page.getByTestId('tasks-status-42')).toContainText('Running');

// Cancel a running task
await page.getByTestId('tasks-button-cancel-42').click();
```

### Task Details (dynamic with task ID)

| Test ID Pattern | Element |
|-----------------|---------|
| `tasks-details-{id}` | Details container |
| `tasks-details-table-{id}` | Details table |
| `tasks-details-error-{id}` | Error message |
| `tasks-details-output-{id}` | Output/artifacts section |

**Playwright Example:**
```typescript
// Expand task and check details
await page.getByTestId('tasks-expand-42').click();
await page.getByTestId('tasks-details-42').waitFor();

// Check for error
await expect(page.getByTestId('tasks-details-error-42')).toContainText('timeout');
```

---

### Notifications Index Page

| Test ID | Element |
|---------|---------|
| `notifications-container` | Page container |
| `notifications-button-mark-read` | Mark all read button |
| `notifications-button-archive` | Archive read button |
| `notifications-list` | List container |
| `notifications-empty` | Empty state |
| `notifications-pagination` | Pagination controls |

### Notifications List Partial

| Test ID | Element |
|---------|---------|
| `notifications-list-frame` | List turbo frame |
| `notifications-list-container` | List container |

### Notification Item (dynamic with notification ID)

| Test ID Pattern | Element |
|-----------------|---------|
| `notifications-item-{id}` | Item container |
| `notifications-icon-{id}` | Icon |
| `notifications-message-{id}` | Message text |
| `notifications-time-{id}` | Timestamp |
| `notifications-button-dismiss-{id}` | Dismiss button |
| `notifications-link-{id}` | Link (if present) |

**Playwright Example:**
```typescript
// Dismiss a notification
await page.getByTestId('notifications-button-dismiss-5').click();

// Click notification link
await page.getByTestId('notifications-link-5').click();

// Mark all as read
await page.getByTestId('notifications-button-mark-read').click();
```

### Notifications Badge

| Test ID | Element |
|---------|---------|
| `notifications-badge` | Badge element |
| `notifications-unread-count` | Unread count |

**Playwright Example:**
```typescript
// Check unread count
await expect(page.getByTestId('notifications-unread-count')).toContainText('3');
```

---

### Profiling Run Modal (New)

| Test ID | Element |
|---------|---------|
| `profiling-modal` | Modal container |
| `profiling-form` | Form element |
| `profiling-radio-report` | Report radio |
| `profiling-radio-telemetry` | Telemetry radio |
| `profiling-radio-flame` | Flame graph radio |
| `profiling-input-module` | Module name field |
| `profiling-input-duration` | Duration field |
| `profiling-button-cancel` | Cancel button |
| `profiling-button-submit` | Submit button |

**Playwright Example:**
```typescript
// Start a profiling run
await page.getByTestId('profiling-radio-flame').click();
await page.getByTestId('profiling-input-duration').fill('30');
await page.getByTestId('profiling-button-submit').click();
```

### Profiling Run Show Page

| Test ID | Element |
|---------|---------|
| `profiling-show-container` | Page container |
| `profiling-show-type` | Run type heading |
| `profiling-show-status` | Status badge |
| `profiling-show-details` | Details card |
| `profiling-show-output` | Output card |
| `profiling-show-artifacts` | Artifacts card |
| `profiling-show-artifacts-table` | Artifacts table |
| `profiling-show-error` | Error display |

**Playwright Example:**
```typescript
// Check profiling run status
await page.getByTestId('profiling-show-container').waitFor();
await expect(page.getByTestId('profiling-show-status')).toContainText('Completed');

// Check artifacts
await expect(page.getByTestId('profiling-show-artifacts-table')).toBeVisible();
```

### Profiling Run Row (dynamic with run ID)

| Test ID Pattern | Element |
|-----------------|---------|
| `profiling-row-{id}` | Row |
| `profiling-type-{id}` | Type cell |
| `profiling-recipe-{id}` | Recipe cell |
| `profiling-status-{id}` | Status badge |
| `profiling-started-{id}` | Started time |
| `profiling-duration-{id}` | Duration |
| `profiling-link-view-{id}` | View link |
| `profiling-artifacts-{id}` | Artifacts count |

**Playwright Example:**
```typescript
// Check profiling run status
await expect(page.getByTestId('profiling-status-7')).toContainText('Running');

// View a profiling run
await page.getByTestId('profiling-link-view-7').click();
```