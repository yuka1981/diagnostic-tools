# ViewComponent Refactoring Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor complex views into reusable, testable ViewComponents following TDD.

**Architecture:** Six components built incrementally: StatusBadgeComponent, EmptyStateComponent, CardComponent, FormFieldComponent, TableComponent, SlideOverComponent. Each component wraps existing Tailwind patterns.

**Tech Stack:** Rails 7.2, ViewComponent gem (already installed), RSpec, Tailwind CSS

---

## Task 1: StatusBadgeComponent

**Files:**
- Create: `app/components/status_badge_component.rb`
- Create: `app/components/status_badge_component.html.erb`
- Create: `spec/components/status_badge_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/status_badge_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StatusBadgeComponent, type: :component do
  describe "status variants" do
    it "renders success variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :success))

      expect(page).to have_css("span.bg-success-2.text-success-7.border-success-2")
      expect(page).to have_text("Success")
    end

    it "renders error variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :error))

      expect(page).to have_css("span.bg-error-1.text-error-7.border-error-2")
      expect(page).to have_text("Error")
    end

    it "renders running variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :running))

      expect(page).to have_css("span.bg-primary-1.text-primary-7.border-primary-2")
      expect(page).to have_text("Running")
    end

    it "renders warning variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :warning))

      expect(page).to have_css("span.bg-warning-1.text-warning-7.border-warning-2")
      expect(page).to have_text("Warning")
    end

    it "renders muted variant with correct classes" do
      render_inline(StatusBadgeComponent.new(status: :muted))

      expect(page).to have_css("span.bg-neutral-4.text-neutral-85.border-neutral-8")
      expect(page).to have_text("Muted")
    end

    it "falls back to muted for unknown status" do
      render_inline(StatusBadgeComponent.new(status: :unknown_status))

      expect(page).to have_css("span.bg-neutral-4")
    end
  end

  describe "custom label" do
    it "uses custom label when provided" do
      render_inline(StatusBadgeComponent.new(status: :success, label: "Active"))

      expect(page).to have_text("Active")
      expect(page).not_to have_text("Success")
    end
  end

  describe "status string mapping" do
    it "maps 'completed' to success variant" do
      render_inline(StatusBadgeComponent.new(status: "completed"))

      expect(page).to have_css("span.bg-success-2")
    end

    it "maps 'failed' to error variant" do
      render_inline(StatusBadgeComponent.new(status: "failed"))

      expect(page).to have_css("span.bg-error-1")
    end

    it "maps 'pending' to warning variant" do
      render_inline(StatusBadgeComponent.new(status: "pending"))

      expect(page).to have_css("span.bg-warning-1")
    end

    it "maps 'cancelled' to muted variant" do
      render_inline(StatusBadgeComponent.new(status: "cancelled"))

      expect(page).to have_css("span.bg-neutral-4")
    end
  end

  describe "size variants" do
    it "renders default size" do
      render_inline(StatusBadgeComponent.new(status: :success))

      expect(page).to have_css("span.px-2.py-0\\.5.text-xs")
    end

    it "renders small size" do
      render_inline(StatusBadgeComponent.new(status: :success, size: :small))

      expect(page).to have_css("span.px-1\\.5.py-0\\.5.text-\\[9px\\]")
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/status_badge_component_spec.rb`
Expected: FAIL with "uninitialized constant StatusBadgeComponent"

### Step 3: Write the component Ruby class

Create `app/components/status_badge_component.rb`:

```ruby
# frozen_string_literal: true

class StatusBadgeComponent < ViewComponent::Base
  STATUS_COLORS = {
    success: "bg-success-2 text-success-7 border border-success-2",
    error: "bg-error-1 text-error-7 border border-error-2",
    running: "bg-primary-1 text-primary-7 border border-primary-2",
    warning: "bg-warning-1 text-warning-7 border border-warning-2",
    muted: "bg-neutral-4 text-neutral-85 border border-neutral-8"
  }.freeze

  STATUS_MAPPING = {
    "success" => :success,
    "completed" => :success,
    "passed" => :success,
    "online" => :success,
    "failed" => :error,
    "offline" => :error,
    "error" => :error,
    "running" => :running,
    "pending" => :warning,
    "warning" => :warning,
    "unknown" => :warning,
    "cancelled" => :muted
  }.freeze

  SIZE_CLASSES = {
    default: "px-2 py-0.5 text-xs",
    small: "px-1.5 py-0.5 text-[9px]"
  }.freeze

  def initialize(status:, label: nil, size: :default)
    @status = status
    @label = label
    @size = size
  end

  def color_classes
    variant = STATUS_MAPPING[status.to_s] || status.to_sym
    STATUS_COLORS.fetch(variant, STATUS_COLORS[:muted])
  end

  def size_classes
    SIZE_CLASSES.fetch(size, SIZE_CLASSES[:default])
  end

  def display_label
    label || status.to_s.titleize
  end

  private

  attr_reader :status, :label, :size
end
```

### Step 4: Write the component template

Create `app/components/status_badge_component.html.erb`:

```erb
<span class="inline-flex items-center rounded-sm font-medium <%= color_classes %> <%= size_classes %>">
  <%= display_label %>
</span>
```

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/status_badge_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/status_badge_component.rb app/components/status_badge_component.html.erb spec/components/status_badge_component_spec.rb
git commit -m "feat: add StatusBadgeComponent with TDD"
```

---

## Task 2: EmptyStateComponent

**Files:**
- Create: `app/components/empty_state_component.rb`
- Create: `app/components/empty_state_component.html.erb`
- Create: `spec/components/empty_state_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/empty_state_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmptyStateComponent, type: :component do
  it "renders with icon, title, and description" do
    render_inline(EmptyStateComponent.new(
      icon: "inbox",
      title: "No items found",
      description: "Get started by creating your first item."
    ))

    expect(page).to have_css("div.flex.flex-col.items-center.justify-center.py-12")
    expect(page).to have_text("No items found")
    expect(page).to have_text("Get started by creating your first item.")
  end

  it "renders action slot content" do
    render_inline(EmptyStateComponent.new(
      icon: "server",
      title: "No nodes",
      description: "Add a node to get started."
    )) do |component|
      component.with_action do
        '<a href="/nodes/new" class="btn-primary">Add Node</a>'.html_safe
      end
    end

    expect(page).to have_css("div.mt-6.flex.gap-3")
    expect(page).to have_link("Add Node", href: "/nodes/new")
  end

  it "renders without description" do
    render_inline(EmptyStateComponent.new(
      icon: "file",
      title: "No files"
    ))

    expect(page).to have_text("No files")
    expect(page).not_to have_css("p.mt-1")
  end

  it "renders with custom icon classes" do
    render_inline(EmptyStateComponent.new(
      icon: "alert-circle",
      title: "Error",
      icon_class: "text-error-5"
    ))

    expect(page).to have_css("svg.text-error-5") | have_css("[data-lucide='alert-circle']")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/empty_state_component_spec.rb`
Expected: FAIL with "uninitialized constant EmptyStateComponent"

### Step 3: Write the component Ruby class

Create `app/components/empty_state_component.rb`:

```ruby
# frozen_string_literal: true

class EmptyStateComponent < ViewComponent::Base
  renders_one :action

  def initialize(icon:, title:, description: nil, icon_class: "text-neutral-25")
    @icon = icon
    @title = title
    @description = description
    @icon_class = icon_class
  end

  private

  attr_reader :icon, :title, :description, :icon_class
end
```

### Step 4: Write the component template

Create `app/components/empty_state_component.html.erb`:

```erb
<div class="flex flex-col items-center justify-center py-12 text-center">
  <div class="h-12 w-12 rounded-full bg-neutral-4 flex items-center justify-center mb-4">
    <%= lucide_icon(icon, class: "h-6 w-6 #{icon_class}") %>
  </div>
  <h3 class="text-sm font-semibold text-neutral-85"><%= title %></h3>
  <% if description.present? %>
    <p class="mt-1 text-sm text-neutral-45"><%= description %></p>
  <% end %>
  <% if action? %>
    <div class="mt-6 flex gap-3">
      <%= action %>
    </div>
  <% end %>
</div>
```

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/empty_state_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/empty_state_component.rb app/components/empty_state_component.html.erb spec/components/empty_state_component_spec.rb
git commit -m "feat: add EmptyStateComponent with TDD"
```

---

## Task 3: CardComponent

**Files:**
- Create: `app/components/card_component.rb`
- Create: `app/components/card_component.html.erb`
- Create: `spec/components/card_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/card_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CardComponent, type: :component do
  it "renders with title and content" do
    render_inline(CardComponent.new(title: "Test Card")) do
      "Card content here"
    end

    expect(page).to have_css("div.card-netbox")
    expect(page).to have_css("div.card-header")
    expect(page).to have_css("h3.card-title", text: "Test Card")
    expect(page).to have_text("Card content here")
  end

  it "renders action slot in header" do
    render_inline(CardComponent.new(title: "Nodes")) do |card|
      card.with_action do
        '<a href="/nodes/new" class="btn-primary">Add</a>'.html_safe
      end
      "Content"
    end

    expect(page).to have_css("div.card-header")
    expect(page).to have_link("Add", href: "/nodes/new")
  end

  it "renders without header when title is nil" do
    render_inline(CardComponent.new) do
      "Just content"
    end

    expect(page).to have_css("div.card-netbox")
    expect(page).not_to have_css("div.card-header")
    expect(page).to have_text("Just content")
  end

  it "renders with padding by default" do
    render_inline(CardComponent.new(title: "Padded")) do
      "Content"
    end

    expect(page).to have_css("div.p-4")
  end

  it "renders without padding when padding: false" do
    render_inline(CardComponent.new(title: "No Padding", padding: false)) do
      "Table goes here"
    end

    expect(page).not_to have_css("div.p-4")
  end

  it "accepts custom CSS classes" do
    render_inline(CardComponent.new(title: "Custom", class: "mt-4")) do
      "Content"
    end

    expect(page).to have_css("div.card-netbox.mt-4")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/card_component_spec.rb`
Expected: FAIL with "uninitialized constant CardComponent"

### Step 3: Write the component Ruby class

Create `app/components/card_component.rb`:

```ruby
# frozen_string_literal: true

class CardComponent < ViewComponent::Base
  renders_one :action

  def initialize(title: nil, padding: true, **options)
    @title = title
    @padding = padding
    @options = options
  end

  def card_classes
    classes = ["card-netbox"]
    classes << options[:class] if options[:class]
    classes.join(" ")
  end

  def body_classes
    padding ? "p-4" : nil
  end

  def header?
    title.present?
  end

  private

  attr_reader :title, :padding, :options
end
```

### Step 4: Write the component template

Create `app/components/card_component.html.erb`:

```erb
<div class="<%= card_classes %>">
  <% if header? %>
    <div class="card-header">
      <h3 class="card-title"><%= title %></h3>
      <% if action? %>
        <div><%= action %></div>
      <% end %>
    </div>
  <% end %>
  <div class="<%= body_classes %>">
    <%= content %>
  </div>
</div>
```

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/card_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/card_component.rb app/components/card_component.html.erb spec/components/card_component_spec.rb
git commit -m "feat: add CardComponent with TDD"
```

---

## Task 4: FormFieldComponent

**Files:**
- Create: `app/components/form_field_component.rb`
- Create: `app/components/form_field_component.html.erb`
- Create: `spec/components/form_field_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/form_field_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFieldComponent, type: :component do
  let(:node) { Node.new }
  let(:form) do
    view = ActionView::Base.empty
    view.extend(ActionView::Helpers::FormHelper)
    view.extend(ActionView::Helpers::FormTagHelper)
    ActionView::Helpers::FormBuilder.new(:node, node, view, {})
  end

  it "renders label and text field" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    ))

    expect(page).to have_css("label", text: "Hostname")
    expect(page).to have_css("input[type='text'][name='node[hostname]']")
  end

  it "renders hint text" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      hint: "Enter the server hostname"
    ))

    expect(page).to have_css("p.text-xs.text-neutral-45", text: "Enter the server hostname")
  end

  it "renders placeholder" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      placeholder: "e.g., compute-001"
    ))

    expect(page).to have_css("input[placeholder='e.g., compute-001']")
  end

  it "renders required indicator" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname",
      required: true
    ))

    expect(page).to have_css("span.text-error-5", text: "*")
  end

  it "renders custom input via slot" do
    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :role,
      label: "Role"
    )) do |field|
      field.with_input do
        '<select name="node[role]"><option>compute</option></select>'.html_safe
      end
    end

    expect(page).to have_css("select[name='node[role]']")
    expect(page).not_to have_css("input[type='text']")
  end

  it "applies error styling when model has errors" do
    node.errors.add(:hostname, "can't be blank")

    render_inline(FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    ))

    expect(page).to have_css("input.border-error-3")
    expect(page).to have_css("p.text-error-6", text: "can't be blank")
  end

  it "exposes input_classes method" do
    component = FormFieldComponent.new(
      form: form,
      attribute: :hostname,
      label: "Hostname"
    )

    expect(component.input_classes).to include("rounded-md")
    expect(component.input_classes).to include("border-neutral-15")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/form_field_component_spec.rb`
Expected: FAIL with "uninitialized constant FormFieldComponent"

### Step 3: Write the component Ruby class

Create `app/components/form_field_component.rb`:

```ruby
# frozen_string_literal: true

class FormFieldComponent < ViewComponent::Base
  renders_one :input

  BASE_INPUT_CLASSES = "block w-full rounded-md shadow-sm focus:border-primary-5 focus:ring-primary-5 sm:text-sm"
  NORMAL_BORDER = "border-neutral-15"
  ERROR_BORDER = "border-error-3 focus:border-error-5 focus:ring-error-5"

  def initialize(form:, attribute:, label:, hint: nil, placeholder: nil, required: false)
    @form = form
    @attribute = attribute
    @label = label
    @hint = hint
    @placeholder = placeholder
    @required = required
  end

  def input_classes
    border_class = errors? ? ERROR_BORDER : NORMAL_BORDER
    "#{BASE_INPUT_CLASSES} #{border_class}"
  end

  def errors?
    form.object&.errors&.[](attribute)&.any?
  end

  def error_messages
    form.object&.errors&.[](attribute) || []
  end

  private

  attr_reader :form, :attribute, :label, :hint, :placeholder, :required
end
```

### Step 4: Write the component template

Create `app/components/form_field_component.html.erb`:

```erb
<div>
  <%= form.label attribute, class: "block text-sm font-bold text-neutral-85 mb-1" do %>
    <%= label %>
    <% if required %>
      <span class="text-error-5">*</span>
    <% end %>
  <% end %>

  <% if input? %>
    <%= input %>
  <% else %>
    <%= form.text_field attribute,
        placeholder: placeholder,
        class: input_classes %>
  <% end %>

  <% if errors? %>
    <% error_messages.each do |message| %>
      <p class="mt-1 text-xs text-error-6"><%= message %></p>
    <% end %>
  <% elsif hint.present? %>
    <p class="mt-1 text-xs text-neutral-45"><%= hint %></p>
  <% end %>
</div>
```

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/form_field_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/form_field_component.rb app/components/form_field_component.html.erb spec/components/form_field_component_spec.rb
git commit -m "feat: add FormFieldComponent with TDD"
```

---

## Task 5: TableComponent

**Files:**
- Create: `app/components/table_component.rb`
- Create: `app/components/table_component.html.erb`
- Create: `spec/components/table_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/table_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe TableComponent, type: :component do
  let(:nodes) do
    [
      OpenStruct.new(id: 1, hostname: "node-1", status: "online"),
      OpenStruct.new(id: 2, hostname: "node-2", status: "offline")
    ]
  end

  it "renders table with columns and rows" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Hostname") { |node| node.hostname }
      table.with_column(header: "Status") { |node| node.status }
    end

    expect(page).to have_css("table.min-w-full")
    expect(page).to have_css("thead.bg-neutral-2")
    expect(page).to have_css("th", text: "Hostname")
    expect(page).to have_css("th", text: "Status")
    expect(page).to have_css("td", text: "node-1")
    expect(page).to have_css("td", text: "node-2")
  end

  it "wraps in card-netbox" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("div.card-netbox table")
  end

  it "renders empty state when collection is empty" do
    render_inline(TableComponent.new(collection: [])) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
      table.with_empty do
        '<div class="py-12">No items found</div>'.html_safe
      end
    end

    expect(page).not_to have_css("table")
    expect(page).to have_text("No items found")
  end

  describe "selectable tables" do
    it "renders checkbox column when selectable" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("input[type='checkbox'][data-bulk-select-target='selectAll']")
      expect(page).to have_css("input[type='checkbox'][data-bulk-select-target='checkbox']", count: 2)
    end

    it "renders bulk action bar when selectable" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_bulk_action(label: "Delete", method: :delete, confirm: "Are you sure?")
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("[data-bulk-select-target='actionBar']")
      expect(page).to have_button("Delete")
    end

    it "uses item id for checkbox value" do
      render_inline(TableComponent.new(
        collection: nodes,
        selectable: true,
        bulk_action_path: "/nodes/bulk_destroy"
      )) do |table|
        table.with_column(header: "Name") { |n| n.hostname }
      end

      expect(page).to have_css("input[type='checkbox'][value='1']")
      expect(page).to have_css("input[type='checkbox'][value='2']")
    end
  end

  it "applies hover effect on rows" do
    render_inline(TableComponent.new(collection: nodes)) do |table|
      table.with_column(header: "Name") { |n| n.hostname }
    end

    expect(page).to have_css("tr.hover\\:bg-neutral-2")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/table_component_spec.rb`
Expected: FAIL with "uninitialized constant TableComponent"

### Step 3: Write the component Ruby class

Create `app/components/table_component.rb`:

```ruby
# frozen_string_literal: true

class TableComponent < ViewComponent::Base
  renders_many :columns, ->(header:, &block) {
    TableColumnComponent.new(header: header, block: block)
  }
  renders_many :bulk_actions, ->(label:, method: :post, confirm: nil) {
    TableBulkActionComponent.new(label: label, method: method, confirm: confirm)
  }
  renders_one :empty

  def initialize(collection:, selectable: false, bulk_action_path: nil, id_method: :id)
    @collection = collection
    @selectable = selectable
    @bulk_action_path = bulk_action_path
    @id_method = id_method
  end

  def selectable?
    @selectable && @bulk_action_path.present?
  end

  def empty?
    collection.empty?
  end

  private

  attr_reader :collection, :bulk_action_path, :id_method

  class TableColumnComponent < ViewComponent::Base
    attr_reader :header, :block

    def initialize(header:, block:)
      @header = header
      @block = block
    end

    def call
      # This component doesn't render directly - it provides data to parent
    end

    def cell_content(item)
      block.call(item)
    end
  end

  class TableBulkActionComponent < ViewComponent::Base
    attr_reader :label, :method, :confirm

    def initialize(label:, method:, confirm:)
      @label = label
      @method = method
      @confirm = confirm
    end
  end
end
```

### Step 4: Write the component template

Create `app/components/table_component.html.erb`:

```erb
<div class="card-netbox" data-controller="<%= 'bulk-select' if selectable? %>">
  <% if selectable? && bulk_actions.any? %>
    <div data-bulk-select-target="actionBar"
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
                            method: action.method,
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
      <%= empty %>
    <% else %>
      <table class="min-w-full divide-y divide-neutral-8 text-sm">
        <thead class="bg-neutral-2">
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
        <tbody class="divide-y divide-neutral-8 bg-white">
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

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/table_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/table_component.rb app/components/table_component.html.erb spec/components/table_component_spec.rb
git commit -m "feat: add TableComponent with TDD"
```

---

## Task 6: SlideOverComponent

**Files:**
- Create: `app/components/slide_over_component.rb`
- Create: `app/components/slide_over_component.html.erb`
- Create: `spec/components/slide_over_component_spec.rb`

### Step 1: Write the failing test

Create `spec/components/slide_over_component_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlideOverComponent, type: :component do
  it "renders with title" do
    render_inline(SlideOverComponent.new(title: "Run Details")) do |panel|
      panel.with_tab(name: "Summary", active: true) { "Summary content" }
    end

    expect(page).to have_css("h2", text: "Run Details")
  end

  it "renders backdrop and panel" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Info", active: true) { "Content" }
    end

    expect(page).to have_css("[data-slide-over-target='backdrop']")
    expect(page).to have_css("[data-slide-over-target='panel']")
  end

  it "renders header badge slot" do
    render_inline(SlideOverComponent.new(title: "Run #123")) do |panel|
      panel.with_header_badge { '<span class="badge">Success</span>'.html_safe }
      panel.with_tab(name: "Summary", active: true) { "Content" }
    end

    expect(page).to have_css("span.badge", text: "Success")
  end

  it "renders close button" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Info", active: true) { "Content" }
    end

    expect(page).to have_css("[data-slide-over-target='closeButton']")
    expect(page).to have_css("button[data-action='click->slide-over#close']")
  end

  describe "tabs" do
    it "renders multiple tabs" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary content" }
        panel.with_tab(name: "Metrics") { "Metrics content" }
        panel.with_tab(name: "Logs") { "Logs content" }
      end

      expect(page).to have_css("button[role='tab']", count: 3)
      expect(page).to have_css("button", text: "Summary")
      expect(page).to have_css("button", text: "Metrics")
      expect(page).to have_css("button", text: "Logs")
    end

    it "marks active tab with correct styling" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary" }
        panel.with_tab(name: "Other") { "Other" }
      end

      expect(page).to have_css("button[aria-selected='true']", text: "Summary")
      expect(page).to have_css("button[aria-selected='false']", text: "Other")
    end

    it "renders tab panels with visibility" do
      render_inline(SlideOverComponent.new(title: "Details")) do |panel|
        panel.with_tab(name: "Summary", active: true) { "Summary content" }
        panel.with_tab(name: "Other") { "Other content" }
      end

      expect(page).to have_css("[role='tabpanel'][aria-hidden='false']", text: "Summary content")
      expect(page).to have_css("[role='tabpanel'][aria-hidden='true'].hidden", text: "Other content")
    end
  end

  it "uses tabs stimulus controller" do
    render_inline(SlideOverComponent.new(title: "Details")) do |panel|
      panel.with_tab(name: "Tab", active: true) { "Content" }
    end

    expect(page).to have_css("[data-controller='tabs']")
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/components/slide_over_component_spec.rb`
Expected: FAIL with "uninitialized constant SlideOverComponent"

### Step 3: Write the component Ruby class

Create `app/components/slide_over_component.rb`:

```ruby
# frozen_string_literal: true

class SlideOverComponent < ViewComponent::Base
  renders_one :header_badge
  renders_many :tabs, ->(name:, active: false, &block) {
    SlideOverTabComponent.new(name: name, active: active, content: block)
  }

  def initialize(title:)
    @title = title
  end

  private

  attr_reader :title

  class SlideOverTabComponent < ViewComponent::Base
    attr_reader :name, :active, :content

    def initialize(name:, active:, content:)
      @name = name
      @active = active
      @content = content
    end

    def tab_id
      "tab-#{name.parameterize}"
    end

    def panel_id
      "tab-panel-#{name.parameterize}"
    end

    def active_tab_classes
      if active
        "border-b-2 border-primary-6 px-4 py-3 text-sm font-bold uppercase text-primary-6 focus:outline-none transition-colors"
      else
        "border-b-2 border-transparent px-4 py-3 text-sm font-bold uppercase text-neutral-45 hover:text-neutral-85 hover:border-neutral-15 focus:outline-none transition-colors"
      end
    end

    def panel_classes
      active ? "" : "hidden"
    end

    def call
      content.call
    end
  end
end
```

### Step 4: Write the component template

Create `app/components/slide_over_component.html.erb`:

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
     class="hidden fixed inset-0 z-50 flex items-center justify-center p-4 opacity-0 scale-95 transition-all duration-300 ease-in-out">

  <div data-slide-over-target="modalContent" class="w-full max-w-2xl max-h-[90vh] bg-white shadow-2xl ring-1 ring-neutral-8 rounded-lg overflow-hidden">
    <%# Header %>
    <div class="flex items-center justify-between border-b border-neutral-8 px-6 py-4">
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
              class="rounded-lg p-2 text-neutral-35 hover:bg-neutral-4 hover:text-neutral-45 focus:outline-none focus:ring-2 focus:ring-primary-5 transition-colors">
        <span class="sr-only">Close panel</span>
        <%= lucide_icon("x", class: "h-5 w-5") %>
      </button>
    </div>

    <%# Tabs %>
    <div data-controller="tabs">
      <%# Tab Navigation %>
      <div class="border-b border-neutral-8 bg-white">
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
      <div class="p-6 max-h-[60vh] overflow-y-auto">
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

### Step 5: Run test to verify it passes

Run: `bin/rspec spec/components/slide_over_component_spec.rb`
Expected: All tests PASS

### Step 6: Commit

```bash
git add app/components/slide_over_component.rb app/components/slide_over_component.html.erb spec/components/slide_over_component_spec.rb
git commit -m "feat: add SlideOverComponent with TDD"
```

---

## Task 7: Migrate First View (StatusBadgeComponent)

**Files:**
- Modify: `app/views/benchmark_runs/_run_row.html.erb:13`

### Step 1: Verify existing tests pass

Run: `bin/rspec spec/requests/benchmark_runs_spec.rb`
Expected: All tests PASS

### Step 2: Replace helper call with component

In `app/views/benchmark_runs/_run_row.html.erb`, find line 13:

```erb
<span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium <%= status_badge_class(run.status) %>">
```

Replace the entire span with:

```erb
<%= render StatusBadgeComponent.new(status: run.status) %>
```

### Step 3: Run tests to verify migration works

Run: `bin/rspec spec/requests/benchmark_runs_spec.rb`
Expected: All tests PASS

### Step 4: Commit

```bash
git add app/views/benchmark_runs/_run_row.html.erb
git commit -m "refactor: use StatusBadgeComponent in benchmark runs row"
```

---

## Task 8: Migrate Additional StatusBadge Usages

**Files to modify:**
- `app/views/dashboard/_filtered_runs.html.erb:49`
- `app/views/nodes/benchmark_runs/index.html.erb:40`
- `app/views/nodes/_benchmark_run_row.html.erb:10`
- `app/views/nodes/_latest_benchmark.html.erb:6`
- `app/views/nodes/_node.html.erb:24` (role_badge_class → needs RoleBadgeComponent or StatusBadge variant)

### Step 1: Update each file

For each file, replace the status badge span with the component call.

Example for `dashboard/_filtered_runs.html.erb:49`:
```erb
<%# Before %>
<span class="inline-flex items-center rounded px-1.5 py-0.5 text-[9px] font-black uppercase border <%= status_badge_class(run.status) %>">

<%# After %>
<%= render StatusBadgeComponent.new(status: run.status, size: :small) %>
```

### Step 2: Run full test suite

Run: `bin/rspec`
Expected: All tests PASS

### Step 3: Commit

```bash
git add app/views/dashboard/_filtered_runs.html.erb app/views/nodes/benchmark_runs/index.html.erb app/views/nodes/_benchmark_run_row.html.erb app/views/nodes/_latest_benchmark.html.erb
git commit -m "refactor: migrate remaining views to StatusBadgeComponent"
```

---

## Task 9: Migrate EmptyStateComponent

**Files to modify (pick 2-3 to start):**
- `app/views/nodes/_table.html.erb:70-94`
- `app/views/benchmark_recipes/index.html.erb` (empty state section)

### Step 1: Update nodes table empty state

In `app/views/nodes/_table.html.erb`, replace lines 70-94:

```erb
<%# Before - the entire empty state div %>

<%# After %>
<%= render EmptyStateComponent.new(
  icon: "server",
  title: "No nodes found",
  description: "Get started by creating a new node."
) do |empty| %>
  <% empty.with_action do %>
    <% if current_user.approver? %>
      <%= link_to new_node_path,
          class: "btn-primary",
          data: { turbo_frame: "node_modal" } do %>
        <%= lucide_icon("plus", class: "h-4 w-4") %>
        Add Node
      <% end %>
    <% end %>
    <%= link_to new_node_import_path,
        class: "btn-secondary",
        data: { turbo_frame: "import_modal" } do %>
      <%= lucide_icon("upload", class: "h-4 w-4") %>
      Import CSV
    <% end %>
  <% end %>
<% end %>
```

### Step 2: Run tests

Run: `bin/rspec spec/requests/nodes_spec.rb`
Expected: All tests PASS

### Step 3: Commit

```bash
git add app/views/nodes/_table.html.erb
git commit -m "refactor: use EmptyStateComponent in nodes table"
```

---

## Summary

**Total Tasks:** 9 (6 component builds + 3 migration tasks)

**Execution Order:**
1. StatusBadgeComponent (build + test)
2. EmptyStateComponent (build + test)
3. CardComponent (build + test)
4. FormFieldComponent (build + test)
5. TableComponent (build + test)
6. SlideOverComponent (build + test)
7. Migrate StatusBadge to first view
8. Migrate StatusBadge to remaining views
9. Migrate EmptyState to first views

**After completing all tasks:**
- Run `bin/rspec` to verify full suite passes
- Run `bin/rubocop -a` to fix any style issues
- Create PR for review
