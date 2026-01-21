# QCT Server Product Catalog Design

## Overview

Add support for QCT rackmount server products to the node management system. When adding a new node, users can select/search from QCT model names. Node information can display front view, rear view, case layout images, and related specifications (CPU generation support, max memory, PCIe versions, drive bay types, etc.).

## Goals

1. **Pre-population** - Selecting a model auto-fills expected specs (rack height) when adding nodes
2. **Capacity planning** - Browse catalog to find servers meeting requirements
3. **Visual reference** - Show front/rear view images to help identify physical components

## Current Architecture Context

The system has a location hierarchy for physical placement:

```
Site → Room → ServerRack → Node
```

**ServerProduct is independent of this hierarchy** - it represents a product catalog of server models that can be optionally associated with nodes. When a user selects a server model for a node, it provides:
- Reference information (specs, images)
- Auto-fill for `rack_height` field

The node form currently has a "Rack Assignment" section with:
- Site/Room/Rack cascading dropdown (uses `cascading_select_controller.js`)
- Position (RU) field
- Height (U) field

The Server Model selection will integrate alongside this existing section.

## Data Source

- **Primary**: Web scraping from QCT website (https://www.qct.io/product/index/Server/rackmount-server)
- **Secondary**: Manual admin UI for additions/corrections
- **Updates**: Scheduled weekly sync + manual trigger button

## Data Model

### ServerProduct

```ruby
create_table :server_products do |t|
  t.string :model_name, null: false        # "QuantaGrid D54Q-2U"
  t.string :product_series                  # "QuantaGrid", "QuantaPlex", etc.
  t.string :form_factor                     # "1U", "2U", "4U"
  t.integer :rack_height, default: 1        # Height in U
  t.string :qct_product_url                 # Source URL for scraping updates

  # CPU specs
  t.string :cpu_generations, array: true    # ["4th Gen Xeon", "5th Gen Xeon"]
  t.integer :socket_count
  t.integer :max_tdp_watts

  # Memory specs
  t.integer :max_memory_gb
  t.integer :dimm_slots
  t.string :memory_types, array: true       # ["DDR5"]
  t.integer :max_memory_speed_mhz

  # Storage specs
  t.jsonb :drive_bays, default: []          # [{count: 24, type: "NVMe", form_factor: "2.5"}]

  # PCIe specs
  t.jsonb :pcie_slots, default: []          # [{count: 4, generation: "5.0", lanes: 16}]

  # Other specs
  t.jsonb :power_supply_options, default: []
  t.boolean :gpu_support, default: false
  t.jsonb :network_options, default: []

  t.datetime :last_synced_at
  t.timestamps
end

add_index :server_products, :model_name, unique: true
add_index :server_products, :product_series
add_index :server_products, :form_factor
```

### SyncLog

```ruby
create_table :sync_logs do |t|
  t.string :source, null: false             # "qct"
  t.integer :products_added, default: 0
  t.integer :products_updated, default: 0
  t.jsonb :errors, default: []
  t.datetime :completed_at
  t.timestamps
end
```

### Node Association

```ruby
# Add to nodes table
add_reference :nodes, :server_product, foreign_key: true, null: true
```

### Active Storage

```ruby
# app/models/server_product.rb
class ServerProduct < ApplicationRecord
  has_many_attached :images  # front view, rear view, internal layout
end
```

## Web Scraper

### QctScraperService

```ruby
# app/services/qct_scraper_service.rb
class QctScraperService
  BASE_URL = "https://www.qct.io/product/index/Server/rackmount-server"

  Result = Struct.new(:added_count, :updated_count, :errors, :new_products, keyword_init: true)

  def sync_all
    product_urls = fetch_product_listing
    added = []
    updated = []
    errors = []

    product_urls.each do |url|
      result = sync_product(url)
      case result
      when :added then added << url
      when :updated then updated << url
      else errors << { url: url, error: result }
      end
    rescue StandardError => e
      errors << { url: url, error: e.message }
    end

    Result.new(
      added_count: added.size,
      updated_count: updated.size,
      errors: errors,
      new_products: added
    )
  end

  def sync_product(url)
    html = fetch_page(url)
    attrs = parse_product_page(html)

    product = ServerProduct.find_or_initialize_by(qct_product_url: url)
    is_new = product.new_record?

    product.assign_attributes(attrs)
    product.last_synced_at = Time.current

    download_images(html, product)
    product.save!

    is_new ? :added : :updated
  end

  private

  def fetch_page(url)
    # HTTP GET with appropriate headers and timeout
  end

  def fetch_product_listing
    # Scrape main listing page for all product URLs
  end

  def parse_product_page(html)
    # Extract using Nokogiri:
    # - model_name, product_series, form_factor
    # - CPU specs, memory specs, storage specs
    # - PCIe slots, power options, GPU support
  end

  def download_images(html, product)
    # Parse image URLs from page
    # Download and attach via Active Storage
    # Label images (front, rear, internal) based on alt text or position
  end
end
```

### Background Job

```ruby
# app/jobs/qct_sync_job.rb
class QctSyncJob < ApplicationJob
  queue_as :default

  def perform
    result = QctScraperService.new.sync_all

    SyncLog.create!(
      source: "qct",
      products_added: result.added_count,
      products_updated: result.updated_count,
      errors: result.errors,
      completed_at: Time.current
    )

    if result.added_count > 0
      AdminMailer.new_products_found(result.new_products).deliver_later
    end
  end
end
```

### Scheduled Execution

```yaml
# config/recurring.yml
production:
  qct_product_sync:
    class: QctSyncJob
    schedule: every week at 3am on Sunday
    queue: default
```

## Admin UI

### Location

Settings area in sidebar Admin section - add "Server Products" link alongside:
- API Keys
- SSH Settings
- Agent Config

### Routes

```ruby
# config/routes.rb
namespace :settings do
  resources :server_products do
    collection do
      post :sync
    end
  end
end
```

### Sidebar Update

Add to `app/views/shared/_sidebar.html.erb` in the Admin section:

```erb
<%= link_to settings_server_products_path,
    class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/settings/server_products') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
  <svg class="h-5 w-5 opacity-75" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
  </svg>
  Server Products
<% end %>
```

### Index Page

- Table with columns: Thumbnail, Model Name, Series, Form Factor, Last Synced
- Search/filter bar (by series, form factor)
- "Sync from QCT" button with Turbo Stream progress
- "Add Product" button for manual entry
- Show "Last synced: X days ago" badge

### Form Page

Sections:
1. **Basic Info**: Model name, series, form factor, rack height, QCT URL
2. **CPU**: Generations (tag input), socket count, max TDP
3. **Memory**: Max capacity, DIMM slots, memory types, max speed
4. **Storage**: Dynamic list - drive bay entries (count, type, form factor)
5. **PCIe**: Dynamic list - slot entries (count, generation, lanes)
6. **Other**: GPU support checkbox, power supply options, network options
7. **Images**: Multi-upload with labels (front, rear, internal)

### Controller

```ruby
# app/controllers/settings/server_products_controller.rb
class Settings::ServerProductsController < ApplicationController
  before_action :require_approver!

  def index
    @server_products = ServerProduct.all
    @server_products = @server_products.where(product_series: params[:series]) if params[:series].present?
    @server_products = @server_products.where(form_factor: params[:form_factor]) if params[:form_factor].present?
    @server_products = @server_products.order(:model_name)
    @last_sync = SyncLog.where(source: "qct").order(completed_at: :desc).first
  end

  def sync
    QctSyncJob.perform_later
    redirect_to settings_server_products_path, notice: "Sync started. You'll be notified when complete."
  end

  # Standard CRUD actions...
end
```

## Node Form Integration

### Placement in NodeFormComponent

Add a new "Server Model" section in `app/components/node_form_component.html.erb`, positioned **before** the existing "Rack Assignment" section. This allows the selected server model to auto-fill the `rack_height` field.

```erb
<%# Section: Server Model (NEW) %>
<div class="card-netbox">
  <div class="card-header">
    <h3 class="card-title">Server Model</h3>
  </div>
  <div class="p-4" data-controller="server-product-search">
    <div class="flex gap-4 items-end">
      <div class="flex-1">
        <%= f.label :server_product_id, "Model", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <div class="relative">
          <input type="text"
                 placeholder="Search by model name (e.g., QuantaGrid D54Q)"
                 class="block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                 data-server-product-search-target="input"
                 data-action="input->server-product-search#search" />
          <%= f.hidden_field :server_product_id, data: { server_product_search_target: "hiddenField" } %>
          <!-- Dropdown results rendered here -->
          <div data-server-product-search-target="results" class="absolute z-10 hidden ..."></div>
        </div>
      </div>
      <button type="button"
              class="btn-secondary"
              data-action="click->server-product-browser#open">
        Browse Catalog
      </button>
    </div>
    <p class="mt-2 text-xs text-slate-500">
      Optional: Select a server model to auto-fill rack height and view specifications.
    </p>
    <!-- Selected product preview -->
    <div data-server-product-search-target="preview" class="mt-4 hidden">
      <!-- Shows thumbnail and key specs when a product is selected -->
    </div>
  </div>
</div>

<%# Section: Rack Assignment (EXISTING - rack_height auto-filled from above) %>
```

### Searchable Autocomplete Controller

```javascript
// app/javascript/controllers/server_product_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hiddenField", "results", "preview"]

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) {
      this.resultsTarget.classList.add("hidden")
      return
    }

    // Debounced fetch to /api/server_products/search?q=...
    // Render dropdown with results
    // On selection: update hiddenField, auto-fill rack_height, show preview
  }

  select(event) {
    const product = event.currentTarget.dataset
    this.hiddenFieldTarget.value = product.id
    this.inputTarget.value = product.modelName

    // Auto-fill rack_height in the Rack Assignment section
    const rackHeightField = document.querySelector('[name="node[rack_height]"]')
    if (rackHeightField && product.rackHeight) {
      rackHeightField.value = product.rackHeight
    }

    this.resultsTarget.classList.add("hidden")
    this.showPreview(product)
  }
}
```

### Visual Catalog Browser

"Browse Catalog" button opens modal with:
- Filter sidebar: Form factor, CPU generation, memory capacity
- Card grid: Thumbnail, model name, key specs
- Click to select and close modal

```javascript
// app/javascript/controllers/server_product_browser_controller.js
// - Modal open/close
// - Filter state management
// - Fetch and render product cards from /api/server_products
// - Handle selection (dispatch event to search controller)
```

### Search API Endpoint

```ruby
# app/controllers/api/server_products_controller.rb
module Api
  class ServerProductsController < ApplicationController
    def search
      products = ServerProduct
        .where("model_name ILIKE ?", "%#{params[:q]}%")
        .limit(10)

      render json: products.map { |p|
        {
          id: p.id,
          model_name: p.model_name,
          form_factor: p.form_factor,
          rack_height: p.rack_height,
          thumbnail_url: p.images.first&.then { |i| url_for(i.variant(resize_to_limit: [100, 100])) }
        }
      }
    end

    def index
      products = ServerProduct.all
      products = products.where(form_factor: params[:form_factor]) if params[:form_factor].present?
      products = products.where("? = ANY(cpu_generations)", params[:cpu_generation]) if params[:cpu_generation].present?

      render json: products
    end
  end
end
```

## Node Detail Page Display

When a node has an associated server product, show a "Server Model" card on the node show page. Add to `app/views/nodes/show.html.erb` or as a new partial:

```erb
<%# app/views/nodes/_server_product.html.erb %>
<% if node.server_product.present? %>
  <% product = node.server_product %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Server Model</h3>
    </div>
    <div class="p-4">
      <div class="flex gap-6">
        <!-- Image viewer with front/rear tabs -->
        <div class="w-1/3" data-controller="image-viewer">
          <% if product.images.attached? %>
            <img data-image-viewer-target="main"
                 src="<%= url_for(product.images.first) %>"
                 class="rounded border w-full" />
            <div class="flex gap-2 mt-2">
              <% product.images.each_with_index do |image, i| %>
                <button data-action="click->image-viewer#show"
                        data-index="<%= i %>"
                        class="text-xs px-2 py-1 rounded border hover:bg-slate-100">
                  <%= image.filename.to_s.split('.').first.humanize %>
                </button>
              <% end %>
            </div>
          <% else %>
            <div class="w-full h-32 bg-slate-100 rounded border flex items-center justify-center text-slate-400">
              No images
            </div>
          <% end %>
        </div>

        <!-- Specs table -->
        <div class="w-2/3">
          <table class="w-full text-sm">
            <tbody class="divide-y divide-slate-100">
              <tr>
                <th class="py-2 text-left text-slate-600 w-1/3 font-bold">Model</th>
                <td class="py-2 font-bold text-slate-900"><%= product.model_name %></td>
              </tr>
              <tr>
                <th class="py-2 text-left text-slate-600 font-bold">Form Factor</th>
                <td class="py-2"><%= product.form_factor %> (<%= product.rack_height %>U)</td>
              </tr>
              <tr>
                <th class="py-2 text-left text-slate-600 font-bold">CPU Support</th>
                <td class="py-2">
                  <%= product.cpu_generations&.join(", ") || "—" %>
                  <% if product.socket_count %>
                    (<%= pluralize(product.socket_count, "Socket") %>)
                  <% end %>
                </td>
              </tr>
              <tr>
                <th class="py-2 text-left text-slate-600 font-bold">Max Memory</th>
                <td class="py-2">
                  <% if product.max_memory_gb %>
                    <%= number_to_human_size(product.max_memory_gb.gigabytes) %>
                    (<%= product.dimm_slots %> DIMMs, <%= product.memory_types&.join("/") %>)
                  <% else %>
                    —
                  <% end %>
                </td>
              </tr>
              <tr>
                <th class="py-2 text-left text-slate-600 font-bold">Drive Bays</th>
                <td class="py-2">
                  <% if product.drive_bays.present? %>
                    <% product.drive_bays.each do |bay| %>
                      <%= bay["count"] %>x <%= bay["type"] %> <%= bay["form_factor"] %><br>
                    <% end %>
                  <% else %>
                    —
                  <% end %>
                </td>
              </tr>
              <tr>
                <th class="py-2 text-left text-slate-600 font-bold">PCIe Slots</th>
                <td class="py-2">
                  <% if product.pcie_slots.present? %>
                    <% product.pcie_slots.each do |slot| %>
                      <%= slot["count"] %>x PCIe <%= slot["generation"] %> x<%= slot["lanes"] %><br>
                    <% end %>
                  <% else %>
                    —
                  <% end %>
                </td>
              </tr>
              <% if product.gpu_support %>
                <tr>
                  <th class="py-2 text-left text-slate-600 font-bold">GPU Support</th>
                  <td class="py-2 text-green-600 font-bold">Yes</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

## File Structure

```
app/
├── models/
│   ├── server_product.rb
│   └── sync_log.rb
├── services/
│   └── qct_scraper_service.rb
├── jobs/
│   └── qct_sync_job.rb
├── controllers/
│   ├── settings/
│   │   └── server_products_controller.rb
│   └── api/
│       └── server_products_controller.rb
├── views/
│   ├── settings/server_products/
│   │   ├── index.html.erb
│   │   ├── new.html.erb
│   │   ├── edit.html.erb
│   │   ├── _form.html.erb
│   │   └── _product.html.erb
│   ├── nodes/
│   │   └── _server_product.html.erb
│   └── shared/
│       └── _sidebar.html.erb (update Admin section)
├── components/
│   └── node_form_component.html.erb (add Server Model section)
├── javascript/controllers/
│   ├── server_product_search_controller.js
│   ├── server_product_browser_controller.js
│   └── image_viewer_controller.js
└── mailers/
    └── admin_mailer.rb (add new_products_found method)

db/migrate/
├── xxx_create_server_products.rb
├── xxx_create_sync_logs.rb
└── xxx_add_server_product_to_nodes.rb

config/
└── recurring.yml (add qct_product_sync schedule)
```

## Implementation Order

1. **Database migrations & models** - ServerProduct, SyncLog, Node association
2. **Admin CRUD UI** - Settings area with index, new, edit, form; update sidebar
3. **QCT scraper service** - Implement and test manually
4. **Background job & scheduling** - QctSyncJob with recurring schedule
5. **Node form integration** - Autocomplete and browser modal in NodeFormComponent
6. **Node detail page display** - Server product card with images and specs

## Design Decisions

- **QCT only**: Focused on QCT rackmount servers for simplicity. Schema can be extended for multi-vendor later.
- **Loose association**: Node's server_product_id is optional reference only, no validation against collected DMI data.
- **Local image storage**: Images downloaded and stored via Active Storage, not linked externally.
- **Settings location**: Catalog management in admin/settings area (alongside API Keys, SSH Settings, Agent Config), not primary navigation.
- **Hybrid data entry**: Automated scraping plus manual UI for full control.
- **Independent of location hierarchy**: ServerProduct is a product catalog, separate from the Site → Room → Rack → Node physical placement hierarchy. It provides reference specs and auto-fills rack_height but does not affect location assignment.
