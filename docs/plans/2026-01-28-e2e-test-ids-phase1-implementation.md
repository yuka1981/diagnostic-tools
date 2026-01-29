# E2E Test IDs Phase 1: Shared Components Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `data-testid` attributes to all 7 ViewComponents to enable Playwright E2E testing.

**Architecture:** Each component receives an optional `testid` parameter. When provided, the component renders `data-testid` attributes on key elements. The testid acts as a prefix, with element-specific suffixes appended.

**Tech Stack:** Rails 7, ViewComponent, RSpec, ERB templates

---

## Task 1: StatusBadgeComponent

**Files:**
- Modify: `app/components/status_badge_component.rb`
- Modify: `app/components/status_badge_component.html.erb`
- Modify: `spec/components/status_badge_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/status_badge_component_spec.rb`:

```ruby
describe "test IDs" do
  it "renders data-testid when testid is provided" do
    render_inline(StatusBadgeComponent.new(status: :success, testid: "nodes-badge-status"))

    expect(page).to have_css("[data-testid='nodes-badge-status-success']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(StatusBadgeComponent.new(status: :success))

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/status_badge_component_spec.rb:99 -v`
Expected: FAIL with "expected to find css..."

**Step 3: Update the component class**

In `app/components/status_badge_component.rb`, modify the initialize method:

```ruby
def initialize(status:, label: nil, size: :default, testid: nil)
  @status = status
  @label = label
  @size = size
  @testid = testid
end
```

Add to private attr_reader:

```ruby
attr_reader :status, :label, :size, :testid
```

Add helper method:

```ruby
def testid_attribute
  return nil unless testid
  "#{testid}-#{status}"
end
```

**Step 4: Update the template**

Replace `app/components/status_badge_component.html.erb`:

```erb
<span class="inline-flex items-center rounded-sm font-medium <%= color_classes %> <%= size_classes %>"
      <%= "data-testid=#{testid_attribute}" if testid_attribute %>>
  <%= display_label %>
</span>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/status_badge_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/status_badge_component.rb app/components/status_badge_component.html.erb spec/components/status_badge_component_spec.rb
git commit -m "feat(components): add testid support to StatusBadgeComponent"
```

---

## Task 2: EmptyStateComponent

**Files:**
- Modify: `app/components/empty_state_component.rb`
- Modify: `app/components/empty_state_component.html.erb`
- Modify: `spec/components/empty_state_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/empty_state_component_spec.rb`:

```ruby
describe "test IDs" do
  it "renders data-testid on container when testid is provided" do
    render_inline(EmptyStateComponent.new(
      icon: "inbox",
      title: "No items",
      testid: "nodes-empty-state"
    ))

    expect(page).to have_css("[data-testid='nodes-empty-state']")
  end

  it "renders data-testid on action when present" do
    render_inline(EmptyStateComponent.new(
      icon: "inbox",
      title: "No items",
      testid: "nodes-empty-state"
    )) do |c|
      c.with_action { "<button>Add</button>".html_safe }
    end

    expect(page).to have_css("[data-testid='nodes-empty-state-action']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(EmptyStateComponent.new(icon: "inbox", title: "No items"))

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/empty_state_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/empty_state_component.rb`:

```ruby
def initialize(icon:, title:, description: nil, icon_class: "text-neutral-25", testid: nil)
  @icon = icon
  @title = title
  @description = description
  @icon_class = icon_class
  @testid = testid
end

private

attr_reader :icon, :title, :description, :icon_class, :testid
```

**Step 4: Update the template**

Replace `app/components/empty_state_component.html.erb`:

```erb
<div class="flex flex-col items-center justify-center py-12 text-center"
     <%= "data-testid=#{testid}" if testid %>>
  <div class="h-12 w-12 rounded-full bg-neutral-4 flex items-center justify-center mb-4">
    <%= helpers.lucide_icon(icon, class: "h-6 w-6 #{icon_class}") %>
  </div>
  <h3 class="text-sm font-semibold text-neutral-85"><%= title %></h3>
  <% if description.present? %>
    <p class="mt-1 text-sm text-neutral-45"><%= description %></p>
  <% end %>
  <% if action? %>
    <div class="mt-6 flex gap-3" <%= "data-testid=#{testid}-action" if testid %>>
      <%= action %>
    </div>
  <% end %>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/empty_state_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/empty_state_component.rb app/components/empty_state_component.html.erb spec/components/empty_state_component_spec.rb
git commit -m "feat(components): add testid support to EmptyStateComponent"
```

---

## Task 3: CardComponent

**Files:**
- Modify: `app/components/card_component.rb`
- Modify: `app/components/card_component.html.erb`
- Modify: `spec/components/card_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/card_component_spec.rb`:

```ruby
describe "test IDs" do
  it "renders data-testid on container when testid is provided" do
    render_inline(CardComponent.new(title: "Test", testid: "dashboard-stat")) do
      "Content"
    end

    expect(page).to have_css("[data-testid='dashboard-stat-card']")
  end

  it "renders data-testid on header when present" do
    render_inline(CardComponent.new(title: "Test", testid: "dashboard-stat")) do
      "Content"
    end

    expect(page).to have_css("[data-testid='dashboard-stat-card-header']")
  end

  it "renders data-testid on body" do
    render_inline(CardComponent.new(title: "Test", testid: "dashboard-stat")) do
      "Content"
    end

    expect(page).to have_css("[data-testid='dashboard-stat-card-body']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(CardComponent.new(title: "Test")) { "Content" }

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/card_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/card_component.rb`:

```ruby
def initialize(title: nil, padding: true, testid: nil, **options)
  @title = title
  @padding = padding
  @testid = testid
  @options = options
end

private

attr_reader :title, :padding, :testid, :options
```

**Step 4: Update the template**

Replace `app/components/card_component.html.erb`:

```erb
<div class="<%= card_classes %>" <%= "data-testid=#{testid}-card" if testid %>>
  <% if header? %>
    <div class="card-header" <%= "data-testid=#{testid}-card-header" if testid %>>
      <h3 class="card-title"><%= title %></h3>
      <% if action? %>
        <div><%= action %></div>
      <% end %>
    </div>
  <% end %>
  <div class="<%= body_classes %>" <%= "data-testid=#{testid}-card-body" if testid %>>
    <%= content %>
  </div>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/card_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/card_component.rb app/components/card_component.html.erb spec/components/card_component_spec.rb
git commit -m "feat(components): add testid support to CardComponent"
```

---

## Task 4: FormFieldComponent

**Files:**
- Modify: `app/components/form_field_component.rb`
- Modify: `app/components/form_field_component.html.erb`
- Modify: `spec/components/form_field_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/form_field_component_spec.rb`:

```ruby
describe "test IDs" do
  let(:form) do
    node = Node.new
    view_context = controller.view_context
    ActionView::Helpers::FormBuilder.new(:node, node, view_context, {})
  end

  it "renders data-testid on container when testid is provided" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      testid: "nodes-field-hostname"
    ))

    expect(page).to have_css("[data-testid='nodes-field-hostname']")
  end

  it "renders data-testid on error container when errors present" do
    node = Node.new
    node.errors.add(:hostname, "can't be blank")
    form = ActionView::Helpers::FormBuilder.new(:node, node, controller.view_context, {})

    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      testid: "nodes-field-hostname"
    ))

    expect(page).to have_css("[data-testid='nodes-field-hostname-error']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    ))

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/form_field_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/form_field_component.rb`:

```ruby
def initialize(form:, attribute:, label:, hint: nil, placeholder: nil, required: false, testid: nil)
  @form = form
  @attribute = attribute
  @label = label
  @hint = hint
  @placeholder = placeholder
  @required = required
  @testid = testid
end

private

attr_reader :form, :attribute, :label, :hint, :placeholder, :required, :testid
```

**Step 4: Update the template**

Replace `app/components/form_field_component.html.erb`:

```erb
<div <%= "data-testid=#{testid}" if testid %>>
  <label for="<%= field_id %>" class="block text-sm font-bold text-neutral-85 mb-1">
    <%= label %>
    <% if required %>
      <span class="text-error-5">*</span>
    <% end %>
  </label>

  <% if input? %>
    <%= input %>
  <% else %>
    <%= form.text_field attribute,
        placeholder: placeholder,
        class: input_classes,
        "aria-describedby": aria_describedby %>
  <% end %>

  <% if errors? %>
    <div id="<%= error_id %>" role="alert" <%= "data-testid=#{testid}-error" if testid %>>
      <% error_messages.each do |message| %>
        <p class="mt-1 text-xs text-error-6"><%= message %></p>
      <% end %>
    </div>
  <% elsif hint.present? %>
    <p id="<%= hint_id %>" class="mt-1 text-xs text-neutral-45"><%= hint %></p>
  <% end %>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/form_field_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/form_field_component.rb app/components/form_field_component.html.erb spec/components/form_field_component_spec.rb
git commit -m "feat(components): add testid support to FormFieldComponent"
```

---

## Task 5: TableComponent

**Files:**
- Modify: `app/components/table_component.rb`
- Modify: `app/components/table_component.html.erb`
- Modify: `spec/components/table_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/table_component_spec.rb`:

```ruby
describe "test IDs" do
  it "renders data-testid on container when testid is provided" do
    render_inline(TableComponent.new(collection: nodes, testid: "nodes")) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("[data-testid='nodes-table-container']")
  end

  it "renders data-testid on header" do
    render_inline(TableComponent.new(collection: nodes, testid: "nodes")) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("[data-testid='nodes-table-header']")
  end

  it "renders data-testid on body" do
    render_inline(TableComponent.new(collection: nodes, testid: "nodes")) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("[data-testid='nodes-table-body']")
  end

  it "renders data-testid on empty state" do
    render_inline(TableComponent.new(collection: [], testid: "nodes")) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
      table.with_empty { "<div>No items</div>".html_safe }
    end

    expect(page).to have_css("[data-testid='nodes-table-empty']")
  end

  it "renders data-testid on bulk actions" do
    render_inline(TableComponent.new(
      collection: nodes,
      selectable: true,
      bulk_action_path: "/nodes/bulk_destroy",
      testid: "nodes"
    )) do |table|
      table.with_bulk_action(label: "Delete", method: :delete)
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("[data-testid='nodes-bulk-actions']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/table_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/table_component.rb`:

```ruby
def initialize(collection:, selectable: false, bulk_action_path: nil, id_method: :id, item_name: "item", param_name: "ids", testid: nil)
  @collection = collection
  @selectable = selectable
  @bulk_action_path = bulk_action_path
  @id_method = id_method
  @item_name = item_name
  @param_name = param_name
  @testid = testid
end

private

attr_reader :collection, :bulk_action_path, :id_method, :item_name, :param_name, :testid
```

**Step 4: Update the template**

Replace `app/components/table_component.html.erb`:

```erb
<div class="card-netbox"
     <%= "data-testid=#{testid}-table-container" if testid %>
     <%= "data-controller=bulk-select" if selectable? %>
     <%= "data-bulk-select-item-name-value=#{item_name}" if selectable? %>
     <%= "data-bulk-select-param-name-value=#{param_name}" if selectable? %>>
  <% if selectable? && bulk_actions.any? %>
    <div data-bulk-select-target="actionBar"
         <%= "data-testid=#{testid}-bulk-actions" if testid %>
         class="grid transition-[grid-template-rows] duration-300 ease-in-out"
         style="grid-template-rows: 0fr;"
         data-expanded-style="grid-template-rows: 1fr;"
         data-collapsed-style="grid-template-rows: 0fr;">
      <div class="overflow-hidden min-h-0">
        <div class="bg-neutral-4 border-b border-neutral-8 px-4 py-3 flex items-center justify-between">
          <span class="text-sm text-neutral-85 font-bold" data-bulk-select-target="count">0 item(s) selected</span>
          <div class="flex items-center gap-3">
            <button type="button"
                    data-action="click->bulk-select#clearAll"
                    class="text-sm text-neutral-45 hover:text-neutral-85">
              Clear
            </button>
            <% bulk_actions.each do |action| %>
              <%= form_with url: bulk_action_path,
                            method: action.http_method,
                            data: {
                              bulk_select_target: "form",
                              turbo_confirm: action.confirm
                            },
                            class: "inline" do |f| %>
                <div data-bulk-select-target="hiddenInputs"></div>
                <button type="submit" class="btn-danger text-sm">
                  <%= action.label %>
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
  <% end %>

  <div class="overflow-x-auto">
    <% if empty? %>
      <div <%= "data-testid=#{testid}-table-empty" if testid %>>
        <%= empty %>
      </div>
    <% else %>
      <table class="min-w-full divide-y divide-neutral-8 text-sm">
        <thead class="bg-neutral-2" <%= "data-testid=#{testid}-table-header" if testid %>>
          <tr>
            <% if selectable? %>
              <th scope="col" class="w-10 border-b">
                <div class="flex items-center justify-center h-full py-2">
                  <input type="checkbox"
                         data-bulk-select-target="selectAll"
                         data-action="change->bulk-select#toggleAll"
                         class="rounded border-neutral-15 text-primary-6 focus:ring-primary-5">
                </div>
              </th>
            <% end %>
            <% columns.each do |column| %>
              <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-neutral-45 border-b">
                <%= column.header %>
              </th>
            <% end %>
          </tr>
        </thead>
        <tbody class="divide-y divide-neutral-8 bg-white" <%= "data-testid=#{testid}-table-body" if testid %>>
          <% collection.each do |item| %>
            <tr class="hover:bg-neutral-2">
              <% if selectable? %>
                <td class="w-10">
                  <div class="flex items-center justify-center h-full py-2">
                    <input type="checkbox"
                           value="<%= item.send(id_method) %>"
                           data-bulk-select-target="checkbox"
                           data-action="change->bulk-select#toggle"
                           class="rounded border-neutral-15 text-primary-6 focus:ring-primary-5">
                  </div>
                </td>
              <% end %>
              <% columns.each do |column| %>
                <td class="px-3 py-2">
                  <%= column.cell_content(item) %>
                </td>
              <% end %>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>
  </div>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/table_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/table_component.rb app/components/table_component.html.erb spec/components/table_component_spec.rb
git commit -m "feat(components): add testid support to TableComponent"
```

---

## Task 6: SlideOverComponent

**Files:**
- Modify: `app/components/slide_over_component.rb`
- Modify: `app/components/slide_over_component.html.erb`
- Modify: `spec/components/slide_over_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/slide_over_component_spec.rb`:

```ruby
describe "test IDs" do
  it "renders data-testid on container when testid is provided" do
    render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
    end

    expect(page).to have_css("[data-testid='nodes-modal-container']")
  end

  it "renders data-testid on header" do
    render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
    end

    expect(page).to have_css("[data-testid='nodes-modal-header']")
  end

  it "renders data-testid on close button" do
    render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
    end

    expect(page).to have_css("[data-testid='nodes-modal-close-button']")
  end

  it "renders data-testid on tabs container" do
    render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
      c.with_tab(name: "Hardware", active: false) { "Content" }
    end

    expect(page).to have_css("[data-testid='nodes-modal-tabs']")
  end

  it "renders data-testid on content area" do
    render_inline(SlideOverComponent.new(title: "Details", testid: "nodes-modal")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
    end

    expect(page).to have_css("[data-testid='nodes-modal-content']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(SlideOverComponent.new(title: "Details")) do |c|
      c.with_tab(name: "Overview", active: true) { "Content" }
    end

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/slide_over_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/slide_over_component.rb`:

```ruby
def initialize(title:, testid: nil)
  @title = title
  @testid = testid
end

private

attr_reader :title, :testid
```

**Step 4: Update the template**

Replace `app/components/slide_over_component.html.erb`:

```erb
<%# Backdrop %>
<div data-slide-over-target="backdrop"
     data-action="click->slide-over#backdropClick"
     class="hidden fixed inset-0 z-40 bg-neutral-85/60 backdrop-blur-sm opacity-0 transition-opacity duration-300 ease-in-out">
</div>

<%# Modal Panel %>
<div data-slide-over-target="panel"
     data-action="click->slide-over#panelClick"
     role="dialog"
     aria-modal="true"
     aria-labelledby="slide-over-title"
     <%= "data-testid=#{testid}-container" if testid %>
     class="hidden fixed inset-0 z-50 flex items-center justify-center p-4 opacity-0 scale-95 transition-all duration-300 ease-in-out">

  <div data-slide-over-target="modalContent" class="w-full max-w-2xl max-h-[90vh] bg-white shadow-2xl ring-1 ring-neutral-8 rounded-lg overflow-hidden">
    <%# Header %>
    <div class="flex items-center justify-between border-b border-neutral-8 px-6 py-4"
         <%= "data-testid=#{testid}-header" if testid %>>
      <div class="flex items-center gap-3">
        <h2 id="slide-over-title" class="text-lg font-semibold text-neutral-85">
          <%= title %>
        </h2>
        <% if header_badge? %>
          <%= header_badge %>
        <% end %>
      </div>
      <button type="button"
              data-slide-over-target="closeButton"
              data-action="click->slide-over#close"
              <%= "data-testid=#{testid}-close-button" if testid %>
              class="rounded-lg p-2 text-neutral-35 hover:bg-neutral-4 hover:text-neutral-45 focus:outline-none focus:ring-2 focus:ring-primary-5 transition-colors">
        <span class="sr-only">Close panel</span>
        <%= helpers.lucide_icon("x", class: "h-5 w-5") %>
      </button>
    </div>

    <%# Tabs %>
    <div data-controller="tabs">
      <%# Tab Navigation %>
      <div class="border-b border-neutral-8 bg-white"
           <%= "data-testid=#{testid}-tabs" if testid %>>
        <nav class="flex px-6" aria-label="Tabs" role="tablist" data-action="keydown->tabs#handleKeydown">
          <% tabs.each_with_index do |tab, index| %>
            <button type="button"
                    id="<%= tab.tab_id %>"
                    role="tab"
                    aria-selected="<%= tab.active %>"
                    aria-controls="<%= tab.panel_id %>"
                    <%= 'tabindex="-1"' unless tab.active %>
                    data-tabs-target="tab"
                    data-action="click->tabs#select"
                    class="<%= tab.active_tab_classes %>">
              <%= tab.name %>
            </button>
          <% end %>
        </nav>
      </div>

      <%# Tab Panels %>
      <div class="p-6 max-h-[60vh] overflow-y-auto"
           <%= "data-testid=#{testid}-content" if testid %>>
        <% tabs.each do |tab| %>
          <div id="<%= tab.panel_id %>"
               role="tabpanel"
               aria-labelledby="<%= tab.tab_id %>"
               aria-hidden="<%= !tab.active %>"
               class="<%= tab.panel_classes %>"
               data-tabs-target="panel">
            <%= tab.call %>
          </div>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/slide_over_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/slide_over_component.rb app/components/slide_over_component.html.erb spec/components/slide_over_component_spec.rb
git commit -m "feat(components): add testid support to SlideOverComponent"
```

---

## Task 7: NodeFormWizardComponent

**Files:**
- Modify: `app/components/node_form_wizard_component.rb`
- Modify: `app/components/node_form_wizard_component.html.erb`
- Modify: `spec/components/node_form_wizard_component_spec.rb`

**Step 1: Write the failing test**

Add to `spec/components/node_form_wizard_component_spec.rb`:

```ruby
describe "test IDs" do
  let(:node) { Node.new }

  it "renders data-testid on wizard container" do
    render_inline(NodeFormWizardComponent.new(node: node, testid: "nodes-wizard"))

    expect(page).to have_css("[data-testid='nodes-wizard-container']")
  end

  it "renders data-testid on form" do
    render_inline(NodeFormWizardComponent.new(node: node, testid: "nodes-wizard"))

    expect(page).to have_css("form[data-testid='nodes-wizard-form']")
  end

  it "renders data-testid on step indicators" do
    render_inline(NodeFormWizardComponent.new(node: node, testid: "nodes-wizard"))

    expect(page).to have_css("[data-testid='nodes-wizard-step-1']")
    expect(page).to have_css("[data-testid='nodes-wizard-step-2']")
    expect(page).to have_css("[data-testid='nodes-wizard-step-3']")
  end

  it "renders data-testid on navigation buttons" do
    render_inline(NodeFormWizardComponent.new(node: node, testid: "nodes-wizard"))

    expect(page).to have_css("[data-testid='nodes-wizard-button-back']")
    expect(page).to have_css("[data-testid='nodes-wizard-button-next']")
    expect(page).to have_css("[data-testid='nodes-wizard-button-submit']")
    expect(page).to have_css("[data-testid='nodes-wizard-button-cancel']")
  end

  it "does not render data-testid when testid is not provided" do
    render_inline(NodeFormWizardComponent.new(node: node))

    expect(page).not_to have_css("[data-testid]")
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/components/node_form_wizard_component_spec.rb -v`
Expected: FAIL

**Step 3: Update the component class**

In `app/components/node_form_wizard_component.rb`:

```ruby
def initialize(node:, api_keys: [], agent_config: nil, testid: nil)
  @node = node
  @api_keys = api_keys
  @agent_config = agent_config || SshSetting.current
  @testid = testid
end

private

attr_reader :node, :api_keys, :agent_config, :testid
```

**Step 4: Update the template**

This is a larger template. Key changes to make in `app/components/node_form_wizard_component.html.erb`:

On the outer div (line 1):
```erb
<div data-controller="wizard" data-wizard-total-value="3" data-wizard-current-value="1"
     <%= "data-testid=#{testid}-container" if testid %>>
```

On each step indicator button (around line 7-11):
```erb
<button type="button"
        data-wizard-target="indicator"
        data-step="<%= index + 1 %>"
        data-action="click->wizard#goToStep"
        <%= "data-testid=#{testid}-step-#{index + 1}" if testid %>
        class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium transition-colors <%= index == 0 ? 'bg-primary-6 text-white' : 'bg-neutral-15 text-neutral-45' %>">
```

On the form (line 35):
```erb
<%= form_with(model: node, url: form_url, method: form_method, class: "space-y-6", data: form_data.merge(testid ? { testid: "#{testid}-form" } : {})) do |f| %>
```

On back button (line 307-311):
```erb
<button type="button"
        data-wizard-target="backButton"
        data-action="click->wizard#back"
        <%= "data-testid=#{testid}-button-back" if testid %>
        class="hidden btn-secondary">
```

On cancel link (line 314-316):
```erb
<%= link_to "Cancel", nodes_path,
    class: "btn-secondary",
    data: { turbo_frame: "node_modal" }.merge(testid ? { testid: "#{testid}-button-cancel" } : {}) %>
```

On next button (line 317-321):
```erb
<button type="button"
        data-wizard-target="nextButton"
        data-action="click->wizard#next"
        <%= "data-testid=#{testid}-button-next" if testid %>
        class="btn-primary">
```

On submit button (line 323-325):
```erb
<%= f.submit "Save Node",
    class: "hidden btn-primary",
    data: { wizard_target: "submitButton", hostname_validation_target: "submit" }.merge(testid ? { testid: "#{testid}-button-submit" } : {}) %>
```

**Step 5: Run test to verify it passes**

Run: `bin/rspec spec/components/node_form_wizard_component_spec.rb -v`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add app/components/node_form_wizard_component.rb app/components/node_form_wizard_component.html.erb spec/components/node_form_wizard_component_spec.rb
git commit -m "feat(components): add testid support to NodeFormWizardComponent"
```

---

## Task 8: Run Full Test Suite & Final Commit

**Step 1: Run all component tests**

Run: `bin/rspec spec/components/ -v`
Expected: All tests PASS

**Step 2: Run rubocop**

Run: `bin/rubocop app/components/ spec/components/`
Expected: No offenses

**Step 3: Create summary commit (if all tasks done separately)**

This step is optional if each task was committed individually.

---

## Task 9: Create Test ID Reference Document

**Files:**
- Create: `docs/testing/test-id-reference.md`

**Step 1: Create the reference document**

```markdown
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

### CardComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-card` | Card container |
| `{testid}-card-header` | Card header |
| `{testid}-card-body` | Card body |

### FormFieldComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}` | Field container |
| `{testid}-error` | Error message container |

### TableComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-table-container` | Outer container |
| `{testid}-table-header` | Table thead |
| `{testid}-table-body` | Table tbody |
| `{testid}-table-empty` | Empty state wrapper |
| `{testid}-bulk-actions` | Bulk action bar |

### SlideOverComponent

| Test ID Pattern | Element |
|----------------|---------|
| `{testid}-container` | Modal panel |
| `{testid}-header` | Header section |
| `{testid}-close-button` | Close button |
| `{testid}-tabs` | Tab navigation |
| `{testid}-content` | Tab content area |

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
```

**Step 2: Commit**

```bash
mkdir -p docs/testing
git add docs/testing/test-id-reference.md
git commit -m "docs: add test ID reference for shared components"
```

---

## Success Criteria

- [ ] All 7 ViewComponents accept optional `testid` parameter
- [ ] Test IDs only render when `testid` is provided (no pollution when not needed)
- [ ] All component specs pass with new test ID tests
- [ ] Rubocop passes with no offenses
- [ ] Test ID reference document created
