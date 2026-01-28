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
