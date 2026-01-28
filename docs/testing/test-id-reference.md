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
