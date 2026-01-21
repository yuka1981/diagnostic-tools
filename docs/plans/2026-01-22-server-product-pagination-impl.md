# Server Product Page Number Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add clickable page numbers with hybrid pagination (window + first/last + ellipsis) to server products list.

**Architecture:** Create custom Kaminari view templates that render page numbers as buttons matching the existing NetBox-inspired design. Replace manual Previous/Next logic with Kaminari's `paginate` helper.

**Tech Stack:** Rails 7, Kaminari, Tailwind CSS, RSpec

---

### Task 1: Create Kaminari Paginator Container

**Files:**
- Create: `app/views/kaminari/_paginator.html.erb`

**Step 1: Create the paginator template**

```erb
<%# app/views/kaminari/_paginator.html.erb %>
<%= paginator.render do %>
  <nav class="flex items-center justify-center gap-1" aria-label="Pagination">
    <%= prev_page_tag %>
    <%= first_page_tag %>
    <% each_page do |page| %>
      <% if page.left_outer? || page.right_outer? || page.inside_window? %>
        <%= page_tag page %>
      <% elsif !page.was_truncated? %>
        <%= gap_tag %>
      <% end %>
    <% end %>
    <%= last_page_tag %>
    <%= next_page_tag %>
  </nav>
<% end %>
```

**Step 2: Commit**

```bash
git add app/views/kaminari/_paginator.html.erb
git commit -m "feat(pagination): add kaminari paginator container"
```

---

### Task 2: Create Page Number Templates

**Files:**
- Create: `app/views/kaminari/_page.html.erb`
- Create: `app/views/kaminari/_current_page.html.erb`

**Step 1: Create the page link template**

```erb
<%# app/views/kaminari/_page.html.erb %>
<%= link_to page, url, class: "btn-secondary text-sm px-3 py-1.5", rel: page.rel %>
```

**Step 2: Create the current page template**

```erb
<%# app/views/kaminari/_current_page.html.erb %>
<span class="btn-primary text-sm px-3 py-1.5" aria-current="page"><%= page %></span>
```

**Step 3: Commit**

```bash
git add app/views/kaminari/_page.html.erb app/views/kaminari/_current_page.html.erb
git commit -m "feat(pagination): add page number templates"
```

---

### Task 3: Create First/Last Page Templates

**Files:**
- Create: `app/views/kaminari/_first_page.html.erb`
- Create: `app/views/kaminari/_last_page.html.erb`

**Step 1: Create the first page template**

```erb
<%# app/views/kaminari/_first_page.html.erb %>
<%= link_to page, url, class: "btn-secondary text-sm px-3 py-1.5" %>
```

**Step 2: Create the last page template**

```erb
<%# app/views/kaminari/_last_page.html.erb %>
<%= link_to page, url, class: "btn-secondary text-sm px-3 py-1.5" %>
```

**Step 3: Commit**

```bash
git add app/views/kaminari/_first_page.html.erb app/views/kaminari/_last_page.html.erb
git commit -m "feat(pagination): add first/last page templates"
```

---

### Task 4: Create Gap (Ellipsis) Template

**Files:**
- Create: `app/views/kaminari/_gap.html.erb`

**Step 1: Create the gap template**

```erb
<%# app/views/kaminari/_gap.html.erb %>
<span class="px-2 py-1.5 text-slate-400 text-sm" aria-hidden="true">
  &hellip;
  <span class="sr-only">More pages</span>
</span>
```

**Step 2: Commit**

```bash
git add app/views/kaminari/_gap.html.erb
git commit -m "feat(pagination): add gap/ellipsis template"
```

---

### Task 5: Create Previous/Next Page Templates

**Files:**
- Create: `app/views/kaminari/_prev_page.html.erb`
- Create: `app/views/kaminari/_next_page.html.erb`

**Step 1: Create the previous page template**

```erb
<%# app/views/kaminari/_prev_page.html.erb %>
<% if current_page.first? %>
  <span class="btn-secondary text-sm px-3 py-1.5 opacity-50 cursor-not-allowed" aria-disabled="true">Previous</span>
<% else %>
  <%= link_to "Previous", url, class: "btn-secondary text-sm px-3 py-1.5", rel: "prev" %>
<% end %>
```

**Step 2: Create the next page template**

```erb
<%# app/views/kaminari/_next_page.html.erb %>
<% if current_page.last? %>
  <span class="btn-secondary text-sm px-3 py-1.5 opacity-50 cursor-not-allowed" aria-disabled="true">Next</span>
<% else %>
  <%= link_to "Next", url, class: "btn-secondary text-sm px-3 py-1.5", rel: "next" %>
<% end %>
```

**Step 3: Commit**

```bash
git add app/views/kaminari/_prev_page.html.erb app/views/kaminari/_next_page.html.erb
git commit -m "feat(pagination): add prev/next page templates"
```

---

### Task 6: Write Failing Tests for Page Number Links

**Files:**
- Modify: `spec/requests/settings/server_products_spec.rb:47-66`

**Step 1: Add tests for page number links**

Add inside the existing `describe "pagination"` block (after line 65):

```ruby
      it "renders page number links" do
        get settings_server_products_path
        doc = Nokogiri::HTML(response.body)
        page_links = doc.css('nav[aria-label="Pagination"] a, nav[aria-label="Pagination"] span[aria-current="page"]')
        expect(page_links.size).to be >= 2 # At least page 1 and 2
      end

      it "highlights current page" do
        get settings_server_products_path
        doc = Nokogiri::HTML(response.body)
        current_page = doc.at_css('span[aria-current="page"]')
        expect(current_page).to be_present
        expect(current_page.text.strip).to eq("1")
      end

      it "preserves filter params in pagination links" do
        create(:server_product, product_series: "QuantaGrid")
        get settings_server_products_path, params: { series: "QuantaGrid" }
        doc = Nokogiri::HTML(response.body)
        next_link = doc.at_css('a[rel="next"]')
        expect(next_link["href"]).to include("series=QuantaGrid") if next_link
      end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/requests/settings/server_products_spec.rb:47 --format documentation`

Expected: Tests fail because pagination nav doesn't exist yet

**Step 3: Commit failing tests**

```bash
git add spec/requests/settings/server_products_spec.rb
git commit -m "test(pagination): add specs for page number links (red)"
```

---

### Task 7: Update Index View to Use Kaminari Paginate Helper

**Files:**
- Modify: `app/views/settings/server_products/index.html.erb:87-115`

**Step 1: Replace manual pagination with Kaminari helper**

Replace lines 87-115 (the entire pagination section) with:

```erb
    <% if @server_products.total_pages > 1 %>
      <div class="border-t border-slate-200 bg-slate-50 px-6 py-4">
        <div class="flex items-center justify-between">
          <div class="text-sm text-slate-700">
            Showing
            <span class="font-medium"><%= @server_products.offset_value + 1 %></span>
            to
            <span class="font-medium"><%= [@server_products.offset_value + @server_products.size, @server_products.total_count].min %></span>
            of
            <span class="font-medium"><%= @server_products.total_count %></span>
            results
          </div>
          <%= paginate @server_products, params: params.permit(:series, :form_factor, :q), window: 2, outer_window: 1 %>
        </div>
      </div>
    <% end %>
```

**Step 2: Run tests to verify they pass**

Run: `bin/rspec spec/requests/settings/server_products_spec.rb:47 --format documentation`

Expected: All pagination tests pass

**Step 3: Commit**

```bash
git add app/views/settings/server_products/index.html.erb
git commit -m "feat(pagination): use kaminari paginate helper with page numbers"
```

---

### Task 8: Run Full Test Suite and Lint

**Step 1: Run RSpec**

Run: `bin/rspec spec/requests/settings/server_products_spec.rb --format documentation`

Expected: All tests pass

**Step 2: Run Rubocop**

Run: `bin/rubocop app/views/kaminari/ app/views/settings/server_products/index.html.erb`

Expected: No offenses

**Step 3: Manual verification**

Start dev server: `bin/dev`

Verify:
- Navigate to `/settings/server_products`
- Create 15+ products if needed
- Page numbers appear: `[Previous] [1] [2] [Next]`
- Click page 2 - current page highlights
- Filters preserved when paginating

---

### Task 9: Final Commit and Push

**Step 1: Push to remote**

```bash
git push origin feature/server-product-page-optimization
```

---

## Summary

| Task | Files | Description |
|------|-------|-------------|
| 1 | `_paginator.html.erb` | Container nav element |
| 2 | `_page.html.erb`, `_current_page.html.erb` | Page number buttons |
| 3 | `_first_page.html.erb`, `_last_page.html.erb` | First/last page links |
| 4 | `_gap.html.erb` | Ellipsis element |
| 5 | `_prev_page.html.erb`, `_next_page.html.erb` | Previous/Next buttons |
| 6 | `server_products_spec.rb` | Failing tests (TDD red) |
| 7 | `index.html.erb` | Replace manual pagination |
| 8 | - | Test suite + lint verification |
| 9 | - | Push to remote |
