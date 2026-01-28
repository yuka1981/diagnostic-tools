# E2E Test IDs Design

## Overview

Add comprehensive `data-testid` attributes across the HPC Diagnostic Tools web application to enable reliable E2E testing with Playwright and support external QA/automation teams.

## Goals

- Enable new E2E test coverage using Playwright
- Provide stable, well-documented selectors for external QA teams
- Complete planning and documentation upfront with phased implementation

## Naming Convention

**Pattern:** `{module}-{element}-{descriptor}` (kebab-case)

| Part | Description | Examples |
|------|-------------|----------|
| module | Feature area or component | `nodes`, `auth`, `benchmark-runs`, `status-badge` |
| element | UI element type | `table`, `form`, `button`, `input`, `modal`, `row` |
| descriptor | Specific identifier | `hostname`, `submit`, `filter-status` |

**Dynamic IDs:** For row-level elements, append a stable identifier (hostname, name) rather than database ID:
```
nodes-row-compute-001       # Good: stable across environments
nodes-row-123               # Avoid: database ID changes
```

## Implementation Phases

| Phase | Module | Scope | Rationale |
|-------|--------|-------|-----------|
| 1 | Shared Components | 7 ViewComponents | Highest leverage - propagates everywhere |
| 2 | Auth | Devise views | Gate to all E2E tests |
| 3 | Nodes | 10 views | Central entity |
| 4 | Benchmark Recipes | 5 views | Must exist before runs |
| 5 | Benchmark Runs | 7 views | Core workflow |
| 6 | Dashboard | 3 views | Aggregates data |
| 7 | Infrastructure | Sites, Rooms, Racks | Organizational hierarchy |
| 8 | Settings & Admin | SSH, Agent Releases, Products, API Keys | Configuration |
| 9 | Supporting | Tasks, Notifications, Profiling | Secondary features |

---

## Phase 1: Shared Components

### StatusBadgeComponent
```
status-badge-{status}           # status-badge-success, status-badge-failed, etc.
```

### TableComponent
```
{table_id}-table-container
{table_id}-table-header
{table_id}-table-body
{table_id}-table-empty
{table_id}-bulk-actions
```

### CardComponent
```
{card_id}-card
{card_id}-card-header
{card_id}-card-body
```

### SlideOverComponent
```
{slideover_id}-slideover-container
{slideover_id}-slideover-header
{slideover_id}-slideover-tabs
{slideover_id}-slideover-content
```

### EmptyStateComponent
```
{context}-empty-state
```

### FormFieldComponent
```
{form_id}-field-{name}
{form_id}-field-{name}-error
```

### NodeFormWizardComponent
```
nodes-wizard-container
nodes-wizard-step-{n}
nodes-wizard-input-{field}
```

---

## Phase 2: Auth Module

### Login
```
auth-form-login
auth-input-email
auth-input-password
auth-checkbox-remember-me
auth-button-submit
auth-link-forgot-password
auth-link-sign-up
auth-error-message
```

### Registration
```
auth-form-register
auth-input-email
auth-input-password
auth-input-password-confirmation
auth-button-submit
auth-link-sign-in
auth-error-message
```

### Password Reset
```
auth-form-forgot-password
auth-input-email
auth-button-submit
auth-form-reset-password
auth-input-password
auth-input-password-confirmation
auth-button-submit
```

### Shared Auth Elements
```
auth-flash-notice
auth-flash-alert
auth-logo
auth-container
```

---

## Phase 3: Nodes Module

### List Page
```
nodes-page-container
nodes-button-new
nodes-button-refresh
nodes-filter-form
nodes-filter-status
nodes-filter-site
nodes-filter-search
nodes-table-container
nodes-table-header
nodes-table-body
nodes-table-empty
nodes-bulk-actions
nodes-bulk-button-delete
nodes-bulk-button-collect
```

### Node Row
```
nodes-row-{hostname}
nodes-cell-checkbox-{hostname}
nodes-cell-hostname-{hostname}
nodes-cell-status-{hostname}
nodes-cell-agent-{hostname}
nodes-button-show-{hostname}
nodes-button-edit-{hostname}
nodes-button-collect-{hostname}
nodes-button-install-{hostname}
nodes-button-uninstall-{hostname}
nodes-button-delete-{hostname}
```

### Node Modal/Detail
```
nodes-modal-container
nodes-modal-header
nodes-modal-hostname
nodes-modal-tabs
nodes-modal-tab-overview
nodes-modal-tab-hardware
nodes-modal-tab-network
nodes-modal-tab-logs
nodes-modal-tab-benchmarks
nodes-modal-close-button
```

### Node Form
```
nodes-form-container
nodes-form-step-indicator
nodes-input-hostname
nodes-input-ip-address
nodes-select-site
nodes-select-room
nodes-select-rack
nodes-input-ssh-user
nodes-input-ssh-port
nodes-button-next
nodes-button-back
nodes-button-submit
nodes-form-error
```

---

## Phase 4: Benchmark Recipes Module

### List Page
```
recipes-page-container
recipes-button-new
recipes-table-container
recipes-table-header
recipes-table-body
recipes-table-empty
```

### Recipe Row
```
recipes-row-{name}
recipes-cell-name-{name}
recipes-cell-type-{name}
recipes-cell-status-{name}
recipes-button-show-{name}
recipes-button-edit-{name}
recipes-button-delete-{name}
recipes-button-run-{name}
```

### Recipe Form
```
recipes-form-container
recipes-input-name
recipes-select-benchmark-type
recipes-input-description
recipes-input-parameters
recipes-select-target-nodes
recipes-checkbox-enabled
recipes-button-submit
recipes-button-cancel
recipes-form-error
```

### Recipe Detail
```
recipes-detail-container
recipes-detail-header
recipes-detail-name
recipes-detail-type
recipes-detail-parameters
recipes-detail-runs-list
recipes-button-edit
recipes-button-delete
recipes-button-run
```

---

## Phase 5: Benchmark Runs Module

### List Page
```
benchmark-runs-page-container
benchmark-runs-button-new
benchmark-runs-filter-form
benchmark-runs-filter-status
benchmark-runs-filter-recipe
benchmark-runs-filter-node
benchmark-runs-filter-date-from
benchmark-runs-filter-date-to
benchmark-runs-button-filter-apply
benchmark-runs-button-filter-clear
benchmark-runs-table-container
benchmark-runs-table-header
benchmark-runs-table-body
benchmark-runs-table-empty
benchmark-runs-pagination
```

### Run Row
```
benchmark-runs-row-{id}
benchmark-runs-cell-id-{id}
benchmark-runs-cell-recipe-{id}
benchmark-runs-cell-node-{id}
benchmark-runs-cell-status-{id}
benchmark-runs-cell-started-{id}
benchmark-runs-cell-duration-{id}
benchmark-runs-button-show-{id}
benchmark-runs-button-cancel-{id}
benchmark-runs-button-delete-{id}
```

### Run Slide-over
```
benchmark-runs-slideover-container
benchmark-runs-slideover-header
benchmark-runs-slideover-status
benchmark-runs-slideover-tabs
benchmark-runs-slideover-tab-config
benchmark-runs-slideover-tab-results
benchmark-runs-slideover-tab-logs
benchmark-runs-slideover-config-card
benchmark-runs-slideover-results-card
benchmark-runs-slideover-results-gflops
benchmark-runs-slideover-results-time
benchmark-runs-slideover-logs-output
benchmark-runs-slideover-button-close
benchmark-runs-slideover-button-download
```

---

## Phase 6: Dashboard Module

### Main Page
```
dashboard-page-container
dashboard-header
dashboard-stats-container
```

### Stats Cards
```
dashboard-stat-total-nodes
dashboard-stat-nodes-online
dashboard-stat-nodes-offline
dashboard-stat-active-runs
dashboard-stat-completed-runs
dashboard-stat-failed-runs
```

### Heatmap
```
dashboard-heatmap-container
dashboard-heatmap-title
dashboard-heatmap-legend
dashboard-heatmap-cell-{node}
dashboard-heatmap-tooltip
```

### Filtered Runs
```
dashboard-recent-runs-container
dashboard-recent-runs-title
dashboard-recent-runs-list
dashboard-recent-runs-empty
dashboard-recent-runs-row-{id}
dashboard-recent-runs-link-view-all
```

### Quick Actions
```
dashboard-action-new-node
dashboard-action-new-run
dashboard-action-refresh
```

---

## Phase 7: Infrastructure Module

### Sites
```
sites-page-container
sites-button-new
sites-table-container
sites-table-body
sites-table-empty
sites-row-{name}
sites-button-show-{name}
sites-button-edit-{name}
sites-button-delete-{name}
sites-form-container
sites-input-name
sites-input-location
sites-input-description
sites-button-submit
sites-form-error
```

### Rooms
```
rooms-page-container
rooms-button-new
rooms-table-container
rooms-row-{name}
rooms-button-show-{name}
rooms-button-edit-{name}
rooms-button-delete-{name}
rooms-form-container
rooms-input-name
rooms-select-site
rooms-input-description
rooms-button-submit
rooms-form-error
```

### Racks
```
racks-page-container
racks-button-new
racks-table-container
racks-row-{name}
racks-button-show-{name}
racks-button-edit-{name}
racks-button-delete-{name}
racks-form-container
racks-input-name
racks-select-room
racks-input-capacity
racks-button-submit
racks-form-error
```

---

## Phase 8: Settings & Admin Module

### SSH Settings
```
ssh-settings-page-container
ssh-settings-form-container
ssh-settings-input-default-user
ssh-settings-input-default-port
ssh-settings-input-key-path
ssh-settings-input-timeout
ssh-settings-checkbox-verify-host-key
ssh-settings-input-jump-host
ssh-settings-input-jump-user
ssh-settings-input-jump-port
ssh-settings-button-submit
ssh-settings-button-test-connection
ssh-settings-form-error
```

### Agent Releases
```
agent-releases-page-container
agent-releases-button-new
agent-releases-table-container
agent-releases-row-{version}
agent-releases-cell-version-{version}
agent-releases-cell-status-{version}
agent-releases-button-download-{version}
agent-releases-button-set-default-{version}
agent-releases-button-delete-{version}
agent-releases-form-container
agent-releases-input-version
agent-releases-input-file
agent-releases-input-changelog
agent-releases-checkbox-default
agent-releases-button-submit
```

### Server Products
```
server-products-page-container
server-products-button-new
server-products-table-container
server-products-row-{name}
server-products-button-edit-{name}
server-products-button-delete-{name}
server-products-form-container
server-products-input-name
server-products-input-manufacturer
server-products-input-model
server-products-button-submit
```

### API Keys
```
api-keys-page-container
api-keys-button-new
api-keys-table-container
api-keys-row-{name}
api-keys-cell-name-{name}
api-keys-cell-created-{name}
api-keys-cell-last-used-{name}
api-keys-button-revoke-{name}
api-keys-form-container
api-keys-input-name
api-keys-input-description
api-keys-button-submit
api-keys-modal-token-display
api-keys-button-copy-token
```

---

## Phase 9: Supporting Features Module

### Tasks
```
tasks-page-container
tasks-filter-form
tasks-filter-status
tasks-table-container
tasks-table-body
tasks-table-empty
tasks-row-{id}
tasks-cell-type-{id}
tasks-cell-status-{id}
tasks-cell-created-{id}
tasks-cell-message-{id}
tasks-button-retry-{id}
tasks-button-cancel-{id}
tasks-button-delete-{id}
```

### Notifications
```
notifications-page-container
notifications-button-mark-all-read
notifications-list-container
notifications-list-empty
notifications-row-{id}
notifications-cell-message-{id}
notifications-cell-time-{id}
notifications-button-dismiss-{id}
notifications-badge-unread-count
```

### Profiling Runs
```
profiling-page-container
profiling-button-new
profiling-table-container
profiling-row-{id}
profiling-cell-node-{id}
profiling-cell-status-{id}
profiling-cell-started-{id}
profiling-button-show-{id}
profiling-button-delete-{id}
profiling-detail-container
profiling-detail-header
profiling-detail-results
profiling-detail-charts
profiling-detail-download
```

---

## Shared Layout & Navigation

### Sidebar
```
sidebar-container
sidebar-toggle-button
sidebar-logo
sidebar-section-organization
sidebar-link-dashboard
sidebar-link-sites
sidebar-link-rooms
sidebar-link-racks
sidebar-link-nodes
sidebar-link-benchmark-runs
sidebar-link-recipes
sidebar-link-profiling
sidebar-link-tasks
sidebar-link-notifications
sidebar-section-administration
sidebar-link-ssh-settings
sidebar-link-agent-releases
sidebar-link-server-products
sidebar-link-api-keys
```

### Navbar
```
navbar-container
navbar-breadcrumb
navbar-user-menu
navbar-user-name
navbar-link-profile
navbar-link-settings
navbar-button-logout
```

### Flash Messages
```
flash-container
flash-notice
flash-alert
flash-error
flash-button-dismiss
```

### Modal Container
```
modal-backdrop
modal-container
modal-close-button
```

---

## Implementation Guidelines

### Adding Test IDs in ERB

```erb
<%# Standard element %>
<button data-testid="nodes-button-new">New Node</button>

<%# Dynamic element with stable identifier %>
<tr data-testid="nodes-row-<%= node.hostname %>">

<%# ViewComponent with passed ID prefix %>
<%= render TableComponent.new(table_id: "nodes") %>
```

### ViewComponent Pattern

```ruby
# app/components/table_component.rb
class TableComponent < ViewComponent::Base
  def initialize(table_id:, **options)
    @table_id = table_id
    # ...
  end
end
```

```erb
<%# app/components/table_component.html.erb %>
<div data-testid="<%= @table_id %>-table-container">
  <thead data-testid="<%= @table_id %>-table-header">
  <tbody data-testid="<%= @table_id %>-table-body">
</div>
```

### Playwright Usage

```typescript
// Login helper
await page.getByTestId('auth-input-email').fill('user@example.com');
await page.getByTestId('auth-input-password').fill('password');
await page.getByTestId('auth-button-submit').click();

// Navigate to nodes
await page.getByTestId('sidebar-link-nodes').click();

// Interact with specific node row
await page.getByTestId('nodes-row-compute-001').hover();
await page.getByTestId('nodes-button-show-compute-001').click();

// Work with modal
await expect(page.getByTestId('nodes-modal-container')).toBeVisible();
await page.getByTestId('nodes-modal-tab-hardware').click();
```

### Playwright Configuration

No configuration changes needed - Playwright uses `data-testid` by default:

```typescript
// playwright.config.ts
// getByTestId() looks for data-testid by default
```

### Test ID Validation (Optional CI Check)

```bash
# Extract all test IDs from codebase
grep -roh 'data-testid="[^"]*"' app/ | sort -u > actual-ids.txt

# Compare against reference doc
# (implement as needed for your CI pipeline)
```

---

## Documentation Deliverables

1. **This design document** - `docs/plans/2026-01-28-e2e-test-ids-design.md`
2. **Test ID reference** - `docs/testing/test-id-reference.md` (to be created during Phase 1)
   - Complete catalog of all test IDs
   - Organized by module
   - Playwright usage examples
   - Dynamic ID patterns

---

## Success Criteria

- [ ] All ViewComponents have configurable test ID prefixes
- [ ] Each module has complete test ID coverage per this spec
- [ ] Test ID reference document is complete and accurate
- [ ] Playwright E2E tests use test IDs (not CSS selectors or text matching)
- [ ] External QA team can write tests using reference doc alone
