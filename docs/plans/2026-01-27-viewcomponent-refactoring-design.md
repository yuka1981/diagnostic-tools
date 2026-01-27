# ViewComponent Refactoring Design

## Overview

Refactor complex views into reusable, testable ViewComponents. This addresses complexity management across tables, forms, cards, and slide-over panels.

## Goals

- **Complexity management** - Break down complex views into focused, single-purpose components
- **Testability** - Unit test view logic without system tests
- **Consistency** - Ensure UI patterns are applied uniformly across the app

## Approach

**Incremental rollout** - Refactor one component type at a time, validate it works, then move to the next.

## Components

### Implementation Order

1. `StatusBadgeComponent` (dependency for others)
2. `EmptyStateComponent` (dependency for Table)
3. `CardComponent`
4. `FormFieldComponent`
5. `TableComponent`
6. `SlideOverComponent`

---

### 1. StatusBadgeComponent

**Purpose:** Replace helper methods with a testable component for status badges.

**Interface:**
```erb
<%= render StatusBadgeComponent.new(status: :success, label: "Active") %>
<%= render StatusBadgeComponent.new(status: node.status) %>  <!-- auto-labels -->
```

**Variants:** `success`, `error`, `running`, `warning`, `muted`

**Maps to existing `COLOR_MAPS`:**
```ruby
{
  success: "bg-success-2 text-success-7 border border-success-2",
  error: "bg-error-1 text-error-7 border border-error-2",
  running: "bg-primary-1 text-primary-7 border border-primary-2",
  warning: "bg-warning-1 text-warning-7 border border-warning-2",
  muted: "bg-neutral-4 text-neutral-85 border border-neutral-8"
}
```

**Files:**
- `app/components/status_badge_component.rb`
- `app/components/status_badge_component.html.erb`

---

### 2. EmptyStateComponent

**Purpose:** Standardize empty state UI for tables and lists.

**Interface:**
```erb
<%= render EmptyStateComponent.new(
  icon: "inbox",
  title: "No nodes found",
  description: "Get started by adding your first node."
) do |empty| %>
  <% empty.with_action do %>
    <%= link_to "Add Node", new_node_path, class: "btn-primary" %>
  <% end %>
<% end %>
```

**Structure:**
- Centered layout with icon, title, description
- Optional action slot for CTA buttons
- Uses `lucide_icon` helper for icons

**Files:**
- `app/components/empty_state_component.rb`
- `app/components/empty_state_component.html.erb`

---

### 3. CardComponent

**Purpose:** Wrap the `card-netbox` pattern (316 occurrences) into a single component.

**Interface:**
```erb
<%= render CardComponent.new(title: "Nodes") do |card| %>
  <% card.with_action do %>
    <%= link_to "Add Node", new_node_path, class: "btn-primary" %>
  <% end %>

  <p>Your content here</p>
<% end %>
```

**Variants:**
- With header (title + optional actions)
- Without header (`title: nil`)
- Custom padding (`padding: false` for tables)

**Parameters:**
- `title:` - Optional header title
- `padding:` - Default `true`, set `false` for tables

**Slots:**
- `action` - Header action buttons
- Default slot - Card body content

**Files:**
- `app/components/card_component.rb`
- `app/components/card_component.html.erb`

---

### 4. FormFieldComponent

**Purpose:** Standardize label/input/helper text pattern across 70+ form fields.

**Interface (default text field):**
```erb
<%= render FormFieldComponent.new(
  form: f,
  attribute: :name,
  label: "Name",
  hint: "Helper text here",
  placeholder: "Enter name"
) %>
```

**Interface (custom input via slot):**
```erb
<%= render FormFieldComponent.new(form: f, attribute: :role, label: "Role") do |field| %>
  <% field.with_input do %>
    <%= f.select :role, Node::ROLES, {}, class: field.input_classes %>
  <% end %>
<% end %>
```

**Parameters:**
- `form:` - Form builder object
- `attribute:` - Field attribute name
- `label:` - Label text
- `hint:` - Optional helper text
- `placeholder:` - Optional placeholder
- `required:` - Shows required indicator

**Features:**
- Default renders text field
- Custom input via slot
- Exposes `input_classes` helper for consistent styling
- Error state styling when validation errors present

**Files:**
- `app/components/form_field_component.rb`
- `app/components/form_field_component.html.erb`

---

### 5. TableComponent

**Purpose:** Standardize 37 table views with consistent structure and bulk selection.

**Interface (basic table):**
```erb
<%= render TableComponent.new do |table| %>
  <% table.with_column(header: "Name") do |node| %>
    <%= node.name %>
  <% end %>

  <% table.with_column(header: "Status") do |node| %>
    <%= render StatusBadgeComponent.new(status: node.status) %>
  <% end %>

  <% table.with_rows(@nodes) %>
<% end %>
```

**Interface (with bulk actions):**
```erb
<%= render TableComponent.new(selectable: true, bulk_action_path: bulk_destroy_nodes_path) do |table| %>
  <% table.with_bulk_action(label: "Delete", method: :delete, confirm: "Delete selected?") %>

  <% table.with_column(header: "Name") { |node| node.name } %>
  <% table.with_rows(@nodes) %>
<% end %>
```

**Parameters:**
- `selectable:` - Enables checkbox column and bulk actions
- `bulk_action_path:` - Form action for bulk operations

**Slots:**
- `column` (many) - Table columns with header and block for cell content
- `bulk_action` (many) - Bulk action buttons
- `empty` - Empty state content (or uses EmptyStateComponent)

**Features:**
- Wraps in `CardComponent` automatically
- Checkbox column with Stimulus controller when `selectable: true`
- Animated bulk action bar
- Empty state when collection is empty

**Files:**
- `app/components/table_component.rb`
- `app/components/table_component.html.erb`

---

### 6. SlideOverComponent

**Purpose:** Encapsulate full-height side panel with tabs for detail views.

**Interface:**
```erb
<%= render SlideOverComponent.new(title: @benchmark_run.name) do |panel| %>
  <% panel.with_header_badge do %>
    <%= render StatusBadgeComponent.new(status: @benchmark_run.status) %>
  <% end %>

  <% panel.with_tab(name: "Summary", active: true) do %>
    <!-- Summary content -->
  <% end %>

  <% panel.with_tab(name: "Metrics") do %>
    <!-- Metrics content -->
  <% end %>

  <% panel.with_tab(name: "Logs") do %>
    <!-- Logs content -->
  <% end %>
<% end %>
```

**Parameters:**
- `title:` - Panel header title

**Slots:**
- `header_badge` - Status badge next to title
- `tab` (many) - Tab panels with `name:` and `active:` params

**Features:**
- Backdrop + slide-over container
- Header with title, badge slot, close button
- Tab navigation with bundled Stimulus controller
- First `active: true` tab shows by default
- Works with Turbo Frame for dynamic loading

**Files:**
- `app/components/slide_over_component.rb`
- `app/components/slide_over_component.html.erb`

---

## Testing Strategy

Each component gets RSpec unit tests:

```ruby
# spec/components/card_component_spec.rb
RSpec.describe CardComponent, type: :component do
  it "renders with title" do
    render_inline(CardComponent.new(title: "Test")) { "Content" }

    expect(page).to have_css(".card-header")
    expect(page).to have_text("Test")
    expect(page).to have_text("Content")
  end

  it "renders without header when title is nil" do
    render_inline(CardComponent.new) { "Content" }

    expect(page).not_to have_css(".card-header")
  end
end
```

## Migration Strategy

For each component:

1. **Build** - Create component with full test coverage
2. **Validate** - Migrate one view, run system tests
3. **Rollout** - Migrate remaining views incrementally
4. **Cleanup** - Remove replaced partials/helpers

## File Structure

```
app/components/
├── card_component.rb
├── card_component.html.erb
├── empty_state_component.rb
├── empty_state_component.html.erb
├── form_field_component.rb
├── form_field_component.html.erb
├── slide_over_component.rb
├── slide_over_component.html.erb
├── status_badge_component.rb
├── status_badge_component.html.erb
├── table_component.rb
└── table_component.html.erb

spec/components/
├── card_component_spec.rb
├── empty_state_component_spec.rb
├── form_field_component_spec.rb
├── slide_over_component_spec.rb
├── status_badge_component_spec.rb
└── table_component_spec.rb
```
