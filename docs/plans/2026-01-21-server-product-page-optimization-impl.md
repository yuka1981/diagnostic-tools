# Server Product Page Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Optimize Server Product page load times through pre-generated image variants, lazy loading, skeleton UI, pagination, cached filter options, and HTTP caching.

**Architecture:** Six-layer optimization: (1) pre-generate image variants at seed time, (2) lazy load images in browser, (3) show skeleton UI while loading, (4) paginate to 10 items per page, (5) cache filter dropdown values, (6) enable HTTP caching for images.

**Tech Stack:** Rails 7.2, Kaminari (existing), ActiveStorage, Turbo Frames, Stimulus, Tailwind CSS

---

## Task 1: Add Image Variant Helper Methods to Model

**Files:**
- Modify: `app/models/server_product.rb`
- Test: `spec/models/server_product_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/models/server_product_spec.rb`:

```ruby
describe "#thumbnail_variant" do
  let(:product) { create(:server_product) }

  context "with attached image" do
    before do
      product.images.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/test_server.png")),
        filename: "test_server.png",
        content_type: "image/png"
      )
    end

    it "returns a variant with resize_to_fill transformation" do
      variant = product.thumbnail_variant
      expect(variant).to be_a(ActiveStorage::VariantWithRecord)
      expect(variant.variation.transformations).to include(resize_to_fill: [48, 48])
    end
  end

  context "without attached image" do
    it "returns nil" do
      expect(product.thumbnail_variant).to be_nil
    end
  end
end

describe "#preprocess_image_variants!" do
  let(:product) { create(:server_product) }

  before do
    product.images.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/test_server.png")),
      filename: "test_server.png",
      content_type: "image/png"
    )
  end

  it "processes all image variants" do
    expect { product.preprocess_image_variants! }.not_to raise_error
    # Verify variant was processed by checking blob exists
    variant = product.images.first.variant(resize_to_fill: [48, 48])
    expect(variant.processed?).to be true
  end
end
```

**Step 2: Create test fixture image**

Run:
```bash
mkdir -p spec/fixtures/files
convert -size 100x100 xc:gray spec/fixtures/files/test_server.png 2>/dev/null || \
  dd if=/dev/urandom bs=1 count=100 2>/dev/null | base64 | head -c 100 > spec/fixtures/files/test_server.png
```

If ImageMagick not available, create a minimal PNG manually or copy an existing image.

**Step 3: Run tests to verify they fail**

Run: `bin/rspec spec/models/server_product_spec.rb:53 -v`
Expected: FAIL with "undefined method `thumbnail_variant'"

**Step 4: Write minimal implementation**

Add to `app/models/server_product.rb` before the `private` keyword:

```ruby
def thumbnail_variant
  images.first&.variant(resize_to_fill: [48, 48])
end

def preprocess_image_variants!
  images.each do |image|
    image.variant(resize_to_fill: [48, 48]).processed
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rspec spec/models/server_product_spec.rb -v`
Expected: All PASS

**Step 6: Run rubocop**

Run: `bin/rubocop app/models/server_product.rb`
Expected: No offenses

**Step 7: Commit**

```bash
git add app/models/server_product.rb spec/models/server_product_spec.rb spec/fixtures/files/
git commit -m "feat(server_product): add thumbnail_variant and preprocess methods"
```

---

## Task 2: Add Cached Filter Options to Model

**Files:**
- Modify: `app/models/server_product.rb`
- Test: `spec/models/server_product_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/models/server_product_spec.rb`:

```ruby
describe ".series_options" do
  before do
    create(:server_product, product_series: "QuantaGrid")
    create(:server_product, product_series: "QuantaPlex")
    create(:server_product, product_series: nil)
    Rails.cache.clear
  end

  it "returns sorted unique series values" do
    expect(ServerProduct.series_options).to eq(["QuantaGrid", "QuantaPlex"])
  end

  it "caches the result" do
    ServerProduct.series_options
    expect(Rails.cache.exist?("server_product_series_options")).to be true
  end
end

describe ".form_factor_options" do
  before do
    create(:server_product, form_factor: "2U")
    create(:server_product, form_factor: "1U")
    create(:server_product, form_factor: nil)
    Rails.cache.clear
  end

  it "returns sorted unique form factor values" do
    expect(ServerProduct.form_factor_options).to eq(["1U", "2U"])
  end

  it "caches the result" do
    ServerProduct.form_factor_options
    expect(Rails.cache.exist?("server_product_form_factor_options")).to be true
  end
end

describe "cache invalidation" do
  before { Rails.cache.clear }

  it "clears series cache when product is saved" do
    Rails.cache.write("server_product_series_options", ["old"])
    create(:server_product)
    expect(Rails.cache.exist?("server_product_series_options")).to be false
  end

  it "clears form_factor cache when product is saved" do
    Rails.cache.write("server_product_form_factor_options", ["old"])
    create(:server_product)
    expect(Rails.cache.exist?("server_product_form_factor_options")).to be false
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/models/server_product_spec.rb -e "series_options" -v`
Expected: FAIL with "undefined method `series_options'"

**Step 3: Write minimal implementation**

Add to `app/models/server_product.rb` after the scopes, before `before_validation`:

```ruby
def self.series_options
  Rails.cache.fetch("server_product_series_options", expires_in: 1.hour) do
    distinct.pluck(:product_series).compact.sort
  end
end

def self.form_factor_options
  Rails.cache.fetch("server_product_form_factor_options", expires_in: 1.hour) do
    distinct.pluck(:form_factor).compact.sort
  end
end

after_commit :invalidate_filter_caches
```

Add to private section:

```ruby
def invalidate_filter_caches
  Rails.cache.delete("server_product_series_options")
  Rails.cache.delete("server_product_form_factor_options")
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rspec spec/models/server_product_spec.rb -v`
Expected: All PASS

**Step 5: Run rubocop**

Run: `bin/rubocop app/models/server_product.rb`
Expected: No offenses

**Step 6: Commit**

```bash
git add app/models/server_product.rb spec/models/server_product_spec.rb
git commit -m "feat(server_product): add cached series_options and form_factor_options"
```

---

## Task 3: Update Controller with Pagination and Eager Loading

**Files:**
- Modify: `app/controllers/settings/server_products_controller.rb`
- Test: `spec/requests/settings/server_products_spec.rb`

**Step 1: Write the failing tests**

Add to `spec/requests/settings/server_products_spec.rb` (find the index action tests):

```ruby
describe "pagination" do
  before do
    create_list(:server_product, 15)
  end

  it "paginates results to 10 per page" do
    get settings_server_products_path
    expect(assigns(:server_products).size).to eq(10)
  end

  it "shows second page when requested" do
    get settings_server_products_path, params: { page: 2 }
    expect(assigns(:server_products).size).to eq(5)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rspec spec/requests/settings/server_products_spec.rb -e "pagination" -v`
Expected: FAIL (pagination not implemented, returns all 15)

**Step 3: Write minimal implementation**

Update `app/controllers/settings/server_products_controller.rb` index action:

```ruby
def index
  @server_products = ServerProduct.all
  @server_products = @server_products.by_series(params[:series]) if params[:series].present?
  @server_products = @server_products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
  @server_products = @server_products.search_by_name(params[:q]) if params[:q].present?
  @server_products = @server_products.with_attached_images.order(:name).page(params[:page]).per(10)
  @last_sync = SyncLog.for_source("qct").latest.first
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rspec spec/requests/settings/server_products_spec.rb -v`
Expected: All PASS

**Step 5: Run rubocop**

Run: `bin/rubocop app/controllers/settings/server_products_controller.rb`
Expected: No offenses

**Step 6: Commit**

```bash
git add app/controllers/settings/server_products_controller.rb spec/requests/settings/server_products_spec.rb
git commit -m "feat(server_products): add pagination (10/page) and eager load images"
```

---

## Task 4: Update View to Use Cached Filter Options

**Files:**
- Modify: `app/views/settings/server_products/index.html.erb`

**Step 1: Update the filter dropdowns**

Replace lines 39-54 in `app/views/settings/server_products/index.html.erb`:

```erb
<div class="w-48">
  <%= f.select :series,
        options_for_select(
          ServerProduct.series_options.map { |s| [s, s] },
          params[:series]
        ),
        { include_blank: "All Series" },
        class: "form-select w-full" %>
</div>
<div class="w-48">
  <%= f.select :form_factor,
        options_for_select(
          ServerProduct.form_factor_options.map { |ff| [ff, ff] },
          params[:form_factor]
        ),
        { include_blank: "All Form Factors" },
        class: "form-select w-full" %>
</div>
```

**Step 2: Verify manually**

Run: `bin/dev` and visit `/settings/server_products`
Expected: Filter dropdowns still work, but now use cached values

**Step 3: Commit**

```bash
git add app/views/settings/server_products/index.html.erb
git commit -m "refactor(server_products): use cached filter options in dropdowns"
```

---

## Task 5: Add Pagination UI to View

**Files:**
- Modify: `app/views/settings/server_products/index.html.erb`

**Step 1: Add pagination controls after the table**

Add after the closing `</table>` tag (before `</div>` that closes overflow-x-auto), around line 87:

```erb
      </table>
    </div>

    <% if @server_products.total_pages > 1 %>
      <div class="border-t border-slate-200 bg-slate-50 px-6 py-4">
        <nav class="flex items-center justify-between" aria-label="Pagination">
          <div class="hidden sm:block">
            <p class="text-sm text-slate-700">
              Showing
              <span class="font-medium"><%= @server_products.offset_value + 1 %></span>
              to
              <span class="font-medium"><%= [@server_products.offset_value + @server_products.size, @server_products.total_count].min %></span>
              of
              <span class="font-medium"><%= @server_products.total_count %></span>
              results
            </p>
          </div>
          <div class="flex flex-1 justify-between sm:justify-end gap-2">
            <% if @server_products.prev_page %>
              <%= link_to "Previous",
                  settings_server_products_path(series: params[:series], form_factor: params[:form_factor], q: params[:q], page: @server_products.prev_page),
                  class: "btn-secondary" %>
            <% end %>
            <% if @server_products.next_page %>
              <%= link_to "Next",
                  settings_server_products_path(series: params[:series], form_factor: params[:form_factor], q: params[:q], page: @server_products.next_page),
                  class: "btn-secondary" %>
            <% end %>
          </div>
        </nav>
      </div>
    <% end %>
```

**Step 2: Verify manually**

Run: `bin/dev` and visit `/settings/server_products`
Expected: Pagination controls appear when more than 10 products exist

**Step 3: Commit**

```bash
git add app/views/settings/server_products/index.html.erb
git commit -m "feat(server_products): add pagination controls to index view"
```

---

## Task 6: Add Lazy Loading to Product Images

**Files:**
- Modify: `app/views/settings/server_products/_product.html.erb`

**Step 1: Update image tag with lazy loading**

Replace lines 3-4 in `app/views/settings/server_products/_product.html.erb`:

```erb
<% if product.images.attached? %>
  <%= image_tag product.thumbnail_variant,
        loading: "lazy",
        decoding: "async",
        class: "h-10 w-10 object-contain rounded bg-slate-100" %>
<% else %>
```

**Step 2: Verify manually**

Run: `bin/dev` and visit `/settings/server_products`
Expected: Images load lazily (check Network tab - images load as you scroll)

**Step 3: Commit**

```bash
git add app/views/settings/server_products/_product.html.erb
git commit -m "feat(server_products): add lazy loading to product images"
```

---

## Task 7: Create Skeleton Row Partial

**Files:**
- Create: `app/views/settings/server_products/_skeleton_row.html.erb`

**Step 1: Create the skeleton partial**

Create `app/views/settings/server_products/_skeleton_row.html.erb`:

```erb
<tr class="animate-pulse">
  <td class="whitespace-nowrap px-3 py-2">
    <div class="h-10 w-10 bg-slate-200 rounded"></div>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <div class="h-4 w-32 bg-slate-200 rounded"></div>
  </td>
  <td class="px-3 py-2">
    <div class="h-4 w-24 bg-slate-200 rounded"></div>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <div class="h-5 w-12 bg-slate-200 rounded"></div>
  </td>
  <td class="px-3 py-2">
    <div class="h-4 w-28 bg-slate-200 rounded"></div>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <div class="h-4 w-16 bg-slate-200 rounded"></div>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <div class="h-4 w-20 bg-slate-200 rounded"></div>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-right">
    <div class="h-4 w-32 bg-slate-200 rounded ml-auto"></div>
  </td>
</tr>
```

**Step 2: Commit**

```bash
git add app/views/settings/server_products/_skeleton_row.html.erb
git commit -m "feat(server_products): add skeleton row partial for loading state"
```

---

## Task 8: Add Turbo Frame with Skeleton Loading

**Files:**
- Modify: `app/views/settings/server_products/index.html.erb`
- Create: `app/views/settings/server_products/_products_table.html.erb`
- Modify: `app/controllers/settings/server_products_controller.rb`

**Step 1: Extract table body to partial**

Create `app/views/settings/server_products/_products_table.html.erb`:

```erb
<tbody class="divide-y divide-slate-200 bg-white" id="products-tbody">
  <% @server_products.each do |product| %>
    <%= render partial: "product", locals: { product: product } %>
  <% end %>
</tbody>
```

**Step 2: Update index view to use Turbo Frame**

Replace the table section (lines 63-108) in `index.html.erb` with:

```erb
<div class="card-netbox">
  <% if @server_products.any? || params[:page].present? || params[:series].present? || params[:form_factor].present? || params[:q].present? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b w-16">Image</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Model Name</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Series</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Form Factor</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">CPU Support</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Max Memory</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Last Synced</th>
            <th scope="col" class="relative px-3 py-2 border-b">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <turbo-frame id="products-table-body">
          <%= render "products_table" %>
        </turbo-frame>
      </table>
    </div>

    <% if @server_products.total_pages > 1 %>
      <div class="border-t border-slate-200 bg-slate-50 px-6 py-4">
        <nav class="flex items-center justify-between" aria-label="Pagination">
          <div class="hidden sm:block">
            <p class="text-sm text-slate-700">
              Showing
              <span class="font-medium"><%= @server_products.offset_value + 1 %></span>
              to
              <span class="font-medium"><%= [@server_products.offset_value + @server_products.size, @server_products.total_count].min %></span>
              of
              <span class="font-medium"><%= @server_products.total_count %></span>
              results
            </p>
          </div>
          <div class="flex flex-1 justify-between sm:justify-end gap-2">
            <% if @server_products.prev_page %>
              <%= link_to "Previous",
                  settings_server_products_path(series: params[:series], form_factor: params[:form_factor], q: params[:q], page: @server_products.prev_page),
                  class: "btn-secondary" %>
            <% end %>
            <% if @server_products.next_page %>
              <%= link_to "Next",
                  settings_server_products_path(series: params[:series], form_factor: params[:form_factor], q: params[:q], page: @server_products.next_page),
                  class: "btn-secondary" %>
            <% end %>
          </div>
        </nav>
      </div>
    <% end %>
  <% else %>
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-900">No server products yet</p>
      <p class="mt-1 text-xs text-slate-500">Add a product manually or sync from QCT</p>
      <div class="mt-4 flex gap-2">
        <%= button_to sync_settings_server_products_path, method: :post, class: "btn-secondary" do %>
          Sync from QCT
        <% end %>
        <%= link_to new_settings_server_product_path, class: "btn-primary" do %>
          Add Product
        <% end %>
      </div>
    </div>
  <% end %>
</div>
```

**Step 3: Verify manually**

Run: `bin/dev` and visit `/settings/server_products`
Expected: Table renders correctly with Turbo Frame wrapper

**Step 4: Commit**

```bash
git add app/views/settings/server_products/
git commit -m "refactor(server_products): extract table body to partial with Turbo Frame"
```

---

## Task 9: Update Seeder to Pre-generate Variants

**Files:**
- Modify: `app/services/seeds/server_products_seeder.rb`
- Test: `spec/services/seeds/server_products_seeder_spec.rb`

**Step 1: Write the failing test**

Add to `spec/services/seeds/server_products_seeder_spec.rb` (create if doesn't exist):

```ruby
require "rails_helper"

RSpec.describe Seeds::ServerProductsSeeder do
  describe "#call" do
    # ... existing tests ...

    context "with image attachment" do
      let(:json_path) { Rails.root.join("spec/fixtures/seeds/server_products.json") }
      let(:images_dir) { Rails.root.join("spec/fixtures/seeds/images") }
      let(:seeder) { described_class.new(json_path: json_path, images_dir: images_dir) }

      before do
        FileUtils.mkdir_p(images_dir)
        File.write(json_path, { products: [{ name: "Test Server", image_filename: "test.png" }] }.to_json)
        FileUtils.cp(Rails.root.join("spec/fixtures/files/test_server.png"), images_dir.join("test.png"))
      end

      after do
        FileUtils.rm_rf(Rails.root.join("spec/fixtures/seeds"))
      end

      it "pre-generates image variants" do
        seeder.call
        product = ServerProduct.find_by(name: "Test Server")
        variant = product.images.first.variant(resize_to_fill: [48, 48])
        expect(variant.processed?).to be true
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/seeds/server_products_seeder_spec.rb -e "pre-generates" -v`
Expected: FAIL (variant not processed)

**Step 3: Write minimal implementation**

Update `app/services/seeds/server_products_seeder.rb`, add after `attach_image` call:

```ruby
attach_image(product, image_filename) if image_filename.present?
product.preprocess_image_variants! if product.images.attached?
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/seeds/server_products_seeder_spec.rb -v`
Expected: All PASS

**Step 5: Run rubocop**

Run: `bin/rubocop app/services/seeds/server_products_seeder.rb`
Expected: No offenses

**Step 6: Commit**

```bash
git add app/services/seeds/server_products_seeder.rb spec/services/seeds/server_products_seeder_spec.rb
git commit -m "feat(seeder): pre-generate image variants during seed"
```

---

## Task 10: Add Rake Task for Preprocessing Existing Variants

**Files:**
- Modify: `lib/tasks/server_products.rake`
- Test: Manual verification

**Step 1: Add the rake task**

Add to `lib/tasks/server_products.rake` before the final `end`:

```ruby
desc "Pre-process image variants for all server products"
task preprocess_variants: :environment do
  count = 0
  ServerProduct.includes(images_attachments: :blob).find_each do |product|
    next unless product.images.attached?

    print "Processing #{product.name}..."
    product.preprocess_image_variants!
    puts " done"
    count += 1
  end
  puts "Processed #{count} products with images."
end
```

**Step 2: Verify manually**

Run: `bin/rails server_products:preprocess_variants`
Expected: Processes all products with images, outputs progress

**Step 3: Commit**

```bash
git add lib/tasks/server_products.rake
git commit -m "feat(rake): add server_products:preprocess_variants task"
```

---

## Task 11: Add HTTP Cache Headers for ActiveStorage

**Files:**
- Create: `config/initializers/active_storage_caching.rb`

**Step 1: Create the initializer**

Create `config/initializers/active_storage_caching.rb`:

```ruby
# frozen_string_literal: true

# Enable HTTP caching for ActiveStorage image variants
# Browsers will cache images locally for 1 year
Rails.application.config.after_initialize do
  ActiveStorage::Representations::ProxyController.class_eval do
    before_action :set_cache_headers

    private

    def set_cache_headers
      expires_in 1.year, public: true
    end
  end
end
```

**Step 2: Verify manually**

Run: `bin/dev`
Visit `/settings/server_products`
Open DevTools Network tab, check Response Headers for image requests
Expected: `Cache-Control: max-age=31536000, public`

**Step 3: Run rubocop**

Run: `bin/rubocop config/initializers/active_storage_caching.rb`
Expected: No offenses

**Step 4: Commit**

```bash
git add config/initializers/active_storage_caching.rb
git commit -m "feat(caching): add HTTP cache headers for ActiveStorage variants"
```

---

## Task 12: Run Full Test Suite and Fix Issues

**Files:**
- Various (depending on failures)

**Step 1: Run full test suite**

Run: `bin/rspec spec/models spec/services`
Expected: All PASS

**Step 2: Run rubocop**

Run: `bin/rubocop`
Expected: No offenses (or fix any that appear)

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "fix: address test and lint issues from optimization work"
```

---

## Task 13: Re-seed Database to Pre-generate Variants

**Step 1: Purge and re-seed**

Run:
```bash
bin/rails server_products:purge
bin/rails db:seed
```

**Step 2: Verify variants are pre-generated**

Run: `bin/rails runner "puts ServerProduct.first.images.first.variant(resize_to_fill: [48, 48]).processed?"`
Expected: `true`

---

## Summary of Changes

| Component | Change |
|-----------|--------|
| `ServerProduct` model | Added `thumbnail_variant`, `preprocess_image_variants!`, cached `series_options`/`form_factor_options`, cache invalidation callback |
| Controller | Added pagination (10/page), eager loading with `with_attached_images` |
| Index view | Using cached filter options, pagination controls, Turbo Frame wrapper |
| Product partial | Added `loading="lazy"` and `decoding="async"` to images |
| Skeleton partial | New loading placeholder |
| Seeder | Pre-generates variants after image attachment |
| Rake task | New `preprocess_variants` task |
| Initializer | HTTP cache headers for ActiveStorage variants |

## Verification Checklist

- [ ] Page loads with skeleton briefly visible
- [ ] Images lazy load as user scrolls
- [ ] Pagination shows 10 items per page
- [ ] Filter dropdowns still work
- [ ] Image loads are fast (pre-generated variants)
- [ ] Repeat visits are instant (HTTP caching)
- [ ] All model tests pass
- [ ] Rubocop passes
