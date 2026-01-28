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
