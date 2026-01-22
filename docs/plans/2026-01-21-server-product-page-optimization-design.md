# Server Product Page Optimization Design

**Date:** 2026-01-21
**Status:** Draft
**Problem:** Server Product page images load slowly, degrading UX

## Overview

The Server Product index page currently loads all products without pagination, generates image variants on-demand, and runs filter queries on every page load. This design implements a full optimization suite to dramatically improve perceived and actual load times.

## Current State

- 46 server products with attached images
- No pagination - all products loaded at once
- Image variants (48x48 thumbnails) generated on first request
- Filter dropdowns query database on every page load
- No lazy loading - all images requested simultaneously

## Solution Components

### 1. Pre-generated Image Variants

Generate thumbnails during seed/sync instead of on-demand.

**Model additions** (`app/models/server_product.rb`):
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

**Seeder update** (`app/services/seeds/server_products_seeder.rb`):
- Call `.processed` on variant after attaching image

**Rake task** (`lib/tasks/server_products.rake`):
```ruby
task preprocess_variants: :environment do
  ServerProduct.find_each(&:preprocess_image_variants!)
end
```

### 2. Lazy Loading Images

Load images only when entering viewport.

**View changes** (`_product.html.erb`):
```erb
<%= image_tag product.thumbnail_variant,
      loading: "lazy",
      decoding: "async",
      class: "product-image" %>
```

**CSS** for loading states:
```css
.product-image {
  background: #e2e8f0;
  transition: opacity 0.3s ease;
}
```

**Optional enhancement:** Add lazysizes gem for better control and older browser support.

### 3. Skeleton UI

Show placeholder content immediately while data loads.

**New partial** (`app/views/settings/server_products/_skeleton_row.html.erb`):
```erb
<tr class="animate-pulse">
  <td><div class="h-12 w-12 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-32 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-24 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-20 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-28 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-20 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-24 bg-slate-200 rounded"></div></td>
  <td><div class="h-4 w-16 bg-slate-200 rounded"></div></td>
</tr>
```

**Turbo Frame wrapper** (`index.html.erb`):
```erb
<turbo-frame id="products-table" src="<%= settings_server_products_path(format: :turbo_stream) %>" loading="lazy">
  <% 6.times do %>
    <%= render "skeleton_row" %>
  <% end %>
</turbo-frame>
```

### 4. Pagination with Pagy

Limit products per page for faster loads.

**Gemfile:**
```ruby
gem "pagy", "~> 9.0"
```

**Configuration** (`config/initializers/pagy.rb`):
```ruby
Pagy::DEFAULT[:limit] = 10
Pagy::DEFAULT[:size] = 7
```

**Controller** (`settings/server_products_controller.rb`):
```ruby
include Pagy::Backend

def index
  @server_products = ServerProduct.all
  @server_products = @server_products.by_series(params[:series]) if params[:series].present?
  @server_products = @server_products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
  @server_products = @server_products.search_by_name(params[:q]) if params[:q].present?
  @server_products = @server_products.with_attached_images.order(:name)
  @pagy, @server_products = pagy(@server_products)
  @last_sync = SyncLog.for_source("qct").latest.first
end
```

**View pagination nav:**
```erb
<%== pagy_nav(@pagy) %>
```

### 5. Cached Filter Dropdowns

Cache dropdown options to eliminate per-request queries.

**Model methods** (`app/models/server_product.rb`):
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

private

def invalidate_filter_caches
  Rails.cache.delete("server_product_series_options")
  Rails.cache.delete("server_product_form_factor_options")
end
```

**View update:**
```erb
<%= f.select :series,
      options_for_select(
        ServerProduct.series_options.map { |s| [s, s] },
        params[:series]
      ), ... %>
```

### 6. HTTP Caching Headers

Enable browser caching for images.

**Initializer** (`config/initializers/active_storage.rb`):
```ruby
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

**Storage config** (`config/storage.yml`) - optional for development:
```yaml
local:
  service: Disk
  root: <%= Rails.root.join("storage") %>
  public: true
```

## Files Summary

### Files to Create
| File | Purpose |
|------|---------|
| `config/initializers/pagy.rb` | Pagy configuration |
| `config/initializers/active_storage.rb` | HTTP cache headers |
| `app/views/settings/server_products/_skeleton_row.html.erb` | Skeleton placeholder |
| `app/views/settings/server_products/index.turbo_stream.erb` | Turbo stream response |

### Files to Modify
| File | Changes |
|------|---------|
| `Gemfile` | Add `pagy` gem |
| `app/models/server_product.rb` | Variant helpers, cache methods, callbacks |
| `app/controllers/settings/server_products_controller.rb` | Pagy, eager loading, respond_to |
| `app/views/settings/server_products/index.html.erb` | Turbo frame, skeleton, pagination, lazy images |
| `app/views/settings/server_products/_product.html.erb` | Lazy loading attributes |
| `app/services/seeds/server_products_seeder.rb` | Pre-generate variants |
| `lib/tasks/server_products.rake` | Add preprocess_variants task |

## Implementation Order

1. Add Pagy gem and configure
2. Update model with helpers and caching
3. Update controller with pagination and eager loading
4. Update views with lazy loading, skeletons, pagination
5. Update seeder for pre-generated variants
6. Add rake task for existing data
7. Configure HTTP caching

## Expected Results

| Metric | Before | After |
|--------|--------|-------|
| Initial image requests | 46 | 10 (per page) |
| Filter dropdown queries | 2 per request | Cached |
| First-load variant generation | Yes | No (pre-generated) |
| Repeat visit image loads | From server | From browser cache |
| Perceived load time | Slow (blank wait) | Fast (skeleton immediate) |
