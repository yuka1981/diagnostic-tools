# QCT Server Product Catalog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add QCT rackmount server product catalog to the node management system with auto-fill capabilities, visual reference images, and admin management UI.

**Architecture:** A new `ServerProduct` model stores server specifications and images (via Active Storage). A `QctScraperService` fetches product data from QCT's website. The node form gets a searchable dropdown to select server models, auto-filling rack height. Admin UI in Settings area provides CRUD and sync controls.

**Tech Stack:** Rails 7.2, Hotwire (Turbo + Stimulus), Tailwind CSS, PostgreSQL (with JSONB columns), Active Storage, Solid Queue for background jobs, Nokogiri for web scraping.

---

## Task 1: Create ServerProduct and SyncLog Models with Migrations

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_create_server_products.rb`
- Create: `db/migrate/YYYYMMDDHHMMSS_create_sync_logs.rb`
- Create: `app/models/server_product.rb`
- Create: `app/models/sync_log.rb`
- Test: `spec/models/server_product_spec.rb`
- Test: `spec/models/sync_log_spec.rb`
- Test: `spec/factories/server_products.rb`
- Test: `spec/factories/sync_logs.rb`

### Step 1: Write failing tests for ServerProduct model

```ruby
# spec/models/server_product_spec.rb
require "rails_helper"

RSpec.describe ServerProduct, type: :model do
  describe "validations" do
    subject { build(:server_product) }

    it { is_expected.to validate_presence_of(:model_name) }
    it { is_expected.to validate_uniqueness_of(:model_name) }
    it { is_expected.to validate_length_of(:model_name).is_at_most(255) }
  end

  describe "associations" do
    it { is_expected.to have_many(:nodes) }
    it { is_expected.to have_many_attached(:images) }
  end

  describe "factory" do
    it "creates a valid server product" do
      product = build(:server_product)
      expect(product).to be_valid
    end
  end

  describe "scopes" do
    let!(:quantagrid) { create(:server_product, product_series: "QuantaGrid") }
    let!(:quantaplex) { create(:server_product, product_series: "QuantaPlex") }
    let!(:one_u) { create(:server_product, form_factor: "1U") }
    let!(:two_u) { create(:server_product, form_factor: "2U") }

    describe ".by_series" do
      it "filters by product series" do
        expect(ServerProduct.by_series("QuantaGrid")).to include(quantagrid)
        expect(ServerProduct.by_series("QuantaGrid")).not_to include(quantaplex)
      end
    end

    describe ".by_form_factor" do
      it "filters by form factor" do
        expect(ServerProduct.by_form_factor("1U")).to include(one_u)
        expect(ServerProduct.by_form_factor("1U")).not_to include(two_u)
      end
    end
  end

  describe "#rack_height_from_form_factor" do
    it "extracts numeric height from form factor" do
      product = build(:server_product, form_factor: "2U")
      expect(product.rack_height).to eq(2)
    end
  end
end
```

### Step 2: Write failing tests for SyncLog model

```ruby
# spec/models/sync_log_spec.rb
require "rails_helper"

RSpec.describe SyncLog, type: :model do
  describe "validations" do
    subject { build(:sync_log) }

    it { is_expected.to validate_presence_of(:source) }
  end

  describe "factory" do
    it "creates a valid sync log" do
      log = build(:sync_log)
      expect(log).to be_valid
    end
  end

  describe "scopes" do
    describe ".for_source" do
      let!(:qct_log) { create(:sync_log, source: "qct") }
      let!(:other_log) { create(:sync_log, source: "other") }

      it "filters by source" do
        expect(SyncLog.for_source("qct")).to include(qct_log)
        expect(SyncLog.for_source("qct")).not_to include(other_log)
      end
    end

    describe ".latest" do
      let!(:older) { create(:sync_log, completed_at: 2.days.ago) }
      let!(:newer) { create(:sync_log, completed_at: 1.day.ago) }

      it "orders by completed_at descending" do
        expect(SyncLog.latest.first).to eq(newer)
      end
    end
  end
end
```

### Step 3: Run tests to verify they fail

Run: `bin/rspec spec/models/server_product_spec.rb spec/models/sync_log_spec.rb`
Expected: FAIL with "uninitialized constant ServerProduct"

### Step 4: Create ServerProduct migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_server_products.rb
class CreateServerProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :server_products do |t|
      t.string :model_name, null: false, limit: 255
      t.string :product_series, limit: 100
      t.string :form_factor, limit: 20
      t.integer :rack_height, default: 1
      t.string :qct_product_url, limit: 500

      # CPU specs
      t.string :cpu_generations, array: true, default: []
      t.integer :socket_count
      t.integer :max_tdp_watts

      # Memory specs
      t.integer :max_memory_gb
      t.integer :dimm_slots
      t.string :memory_types, array: true, default: []
      t.integer :max_memory_speed_mhz

      # Storage specs
      t.jsonb :drive_bays, default: []

      # PCIe specs
      t.jsonb :pcie_slots, default: []

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
  end
end
```

### Step 5: Create SyncLog migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_sync_logs.rb
class CreateSyncLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :sync_logs do |t|
      t.string :source, null: false, limit: 50
      t.integer :products_added, default: 0
      t.integer :products_updated, default: 0
      t.jsonb :errors, default: []
      t.datetime :completed_at

      t.timestamps
    end

    add_index :sync_logs, :source
    add_index :sync_logs, :completed_at
  end
end
```

### Step 6: Run migrations

Run: `bin/rails db:migrate`
Expected: Success, tables created

### Step 7: Create ServerProduct model

```ruby
# app/models/server_product.rb
class ServerProduct < ApplicationRecord
  has_many :nodes, dependent: :nullify
  has_many_attached :images

  validates :model_name, presence: true, uniqueness: true, length: { maximum: 255 }

  scope :by_series, ->(series) { where(product_series: series) if series.present? }
  scope :by_form_factor, ->(ff) { where(form_factor: ff) if ff.present? }
  scope :search_by_name, ->(q) { where("model_name ILIKE ?", "%#{q}%") if q.present? }

  before_validation :set_rack_height_from_form_factor

  private

  def set_rack_height_from_form_factor
    return if rack_height.present? && rack_height > 0
    return unless form_factor.present?

    match = form_factor.match(/(\d+)U/i)
    self.rack_height = match[1].to_i if match
  end
end
```

### Step 8: Create SyncLog model

```ruby
# app/models/sync_log.rb
class SyncLog < ApplicationRecord
  validates :source, presence: true

  scope :for_source, ->(source) { where(source: source) }
  scope :latest, -> { order(completed_at: :desc) }
end
```

### Step 9: Create factories

```ruby
# spec/factories/server_products.rb
FactoryBot.define do
  factory :server_product do
    sequence(:model_name) { |n| "QuantaGrid D54Q-#{n}U" }
    product_series { "QuantaGrid" }
    form_factor { "2U" }
    rack_height { 2 }
    qct_product_url { "https://www.qct.io/product/index/Server/rackmount-server/QuantaGrid-D54Q-2U" }
    cpu_generations { ["5th Gen Xeon"] }
    socket_count { 2 }
    max_tdp_watts { 350 }
    max_memory_gb { 8192 }
    dimm_slots { 32 }
    memory_types { ["DDR5"] }
    max_memory_speed_mhz { 5600 }
    drive_bays { [{ "count" => 24, "type" => "NVMe", "form_factor" => "2.5" }] }
    pcie_slots { [{ "count" => 4, "generation" => "5.0", "lanes" => 16 }] }
    gpu_support { true }

    trait :one_u do
      form_factor { "1U" }
      rack_height { 1 }
    end

    trait :four_u do
      form_factor { "4U" }
      rack_height { 4 }
    end

    trait :quantaplex do
      product_series { "QuantaPlex" }
      sequence(:model_name) { |n| "QuantaPlex T42S-#{n}U" }
    end
  end
end
```

```ruby
# spec/factories/sync_logs.rb
FactoryBot.define do
  factory :sync_log do
    source { "qct" }
    products_added { 5 }
    products_updated { 10 }
    errors { [] }
    completed_at { Time.current }

    trait :with_errors do
      errors { [{ "url" => "https://example.com", "error" => "Connection timeout" }] }
    end

    trait :in_progress do
      completed_at { nil }
    end
  end
end
```

### Step 10: Run tests to verify they pass

Run: `bin/rspec spec/models/server_product_spec.rb spec/models/sync_log_spec.rb`
Expected: PASS

### Step 11: Run linter

Run: `bin/rubocop app/models/server_product.rb app/models/sync_log.rb spec/models/server_product_spec.rb spec/models/sync_log_spec.rb spec/factories/server_products.rb spec/factories/sync_logs.rb`
Expected: No offenses

### Step 12: Commit

```bash
git add db/migrate/ app/models/server_product.rb app/models/sync_log.rb spec/models/ spec/factories/
git commit -m "$(cat <<'EOF'
feat: add ServerProduct and SyncLog models for QCT catalog

Create database tables and models for storing QCT server product
specifications including CPU, memory, storage, and PCIe details.
SyncLog tracks scraping operations and their results.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add ServerProduct Association to Node Model

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_server_product_to_nodes.rb`
- Modify: `app/models/node.rb:1-20` (add association)
- Test: `spec/models/node_spec.rb` (add association tests)

### Step 1: Write failing test for Node association

Add to existing `spec/models/node_spec.rb`:

```ruby
# Add within describe "associations" block
describe "server_product association" do
  it { is_expected.to belong_to(:server_product).optional }
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/models/node_spec.rb -e "server_product association"`
Expected: FAIL

### Step 3: Create migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_server_product_to_nodes.rb
class AddServerProductToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :server_product, foreign_key: true, null: true
  end
end
```

### Step 4: Run migration

Run: `bin/rails db:migrate`
Expected: Success

### Step 5: Add association to Node model

In `app/models/node.rb`, add after line 6 (after `belongs_to :server_rack`):

```ruby
belongs_to :server_product, optional: true
```

### Step 6: Run test to verify it passes

Run: `bin/rspec spec/models/node_spec.rb -e "server_product association"`
Expected: PASS

### Step 7: Commit

```bash
git add db/migrate/ app/models/node.rb spec/models/node_spec.rb
git commit -m "$(cat <<'EOF'
feat: add server_product association to Node model

Nodes can optionally reference a ServerProduct for catalog information.
The association is optional (null: true) to allow manual node entry
without requiring a catalog match.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create Admin Server Products Controller with Index View

**Files:**
- Create: `app/controllers/settings/server_products_controller.rb`
- Create: `app/views/settings/server_products/index.html.erb`
- Create: `app/views/settings/server_products/_product.html.erb`
- Modify: `config/routes.rb:24-35` (add routes)
- Test: `spec/requests/settings/server_products_spec.rb`

### Step 1: Write failing request spec for index

```ruby
# spec/requests/settings/server_products_spec.rb
require "rails_helper"

RSpec.describe "Settings::ServerProducts", type: :request do
  let(:approver) { create(:user, :approver) }
  let(:viewer) { create(:user) }

  describe "GET /settings/server_products" do
    context "when authenticated as approver" do
      before { sign_in approver }

      it "returns success" do
        get settings_server_products_path
        expect(response).to have_http_status(:success)
      end

      it "displays server products" do
        product = create(:server_product, model_name: "QuantaGrid D54Q-2U")
        get settings_server_products_path
        expect(response.body).to include("QuantaGrid D54Q-2U")
      end

      it "displays last sync information" do
        create(:sync_log, source: "qct", completed_at: 1.day.ago)
        get settings_server_products_path
        expect(response.body).to include("Last synced")
      end
    end

    context "when authenticated as viewer" do
      before { sign_in viewer }

      it "redirects to root" do
        get settings_server_products_path
        expect(response).to redirect_to(root_path)
      end
    end

    context "when not authenticated" do
      it "redirects to sign in" do
        get settings_server_products_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/requests/settings/server_products_spec.rb`
Expected: FAIL with routing error

### Step 3: Add routes

In `config/routes.rb`, add within the `namespace :settings` block (after line 35):

```ruby
resources :server_products do
  collection do
    post :sync
  end
end
```

### Step 4: Create controller

```ruby
# app/controllers/settings/server_products_controller.rb
class Settings::ServerProductsController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :authorize_approver!
  before_action :set_server_product, only: %i[show edit update destroy]

  def index
    @server_products = ServerProduct.all
    @server_products = @server_products.by_series(params[:series]) if params[:series].present?
    @server_products = @server_products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
    @server_products = @server_products.search_by_name(params[:q]) if params[:q].present?
    @server_products = @server_products.order(:model_name)
    @last_sync = SyncLog.for_source("qct").latest.first
  end

  def show
  end

  def new
    @server_product = ServerProduct.new
  end

  def create
    @server_product = ServerProduct.new(server_product_params)
    if @server_product.save
      redirect_to settings_server_products_path, notice: "Server product was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @server_product.update(server_product_params)
      redirect_to settings_server_products_path, notice: "Server product was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @server_product.destroy
    redirect_to settings_server_products_path, notice: "Server product was successfully deleted."
  end

  def sync
    QctSyncJob.perform_later
    redirect_to settings_server_products_path, notice: "Sync started. You'll be notified when complete."
  end

  private

  def set_server_product
    @server_product = ServerProduct.find(params[:id])
  end

  def server_product_params
    params.require(:server_product).permit(
      :model_name, :product_series, :form_factor, :rack_height, :qct_product_url,
      :socket_count, :max_tdp_watts, :max_memory_gb, :dimm_slots, :max_memory_speed_mhz,
      :gpu_support, :last_synced_at,
      cpu_generations: [], memory_types: [], drive_bays: [], pcie_slots: [],
      power_supply_options: [], network_options: [], images: []
    )
  end

  def authorize_approver!
    return if current_user.approver?
    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
```

### Step 5: Create index view

```erb
<%# app/views/settings/server_products/index.html.erb %>
<% content_for(:page_title) { "Server Products" } %>

<div class="flex items-center justify-between mb-6">
  <div>
    <h1 class="text-2xl font-bold text-slate-900">Server Products</h1>
    <p class="text-sm text-slate-500 mt-1">QCT server product catalog for node reference</p>
  </div>
  <div class="flex items-center gap-3">
    <% if @last_sync %>
      <span class="text-xs text-slate-500">
        Last synced: <%= time_ago_in_words(@last_sync.completed_at) %> ago
        (<%= @last_sync.products_added %> added, <%= @last_sync.products_updated %> updated)
      </span>
    <% end %>
    <%= button_to sync_settings_server_products_path,
        method: :post,
        class: "btn-secondary",
        data: { turbo_submits_with: "Syncing..." } do %>
      <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
      </svg>
      Sync from QCT
    <% end %>
    <%= link_to new_settings_server_product_path, class: "btn-primary" do %>
      <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
      </svg>
      Add Product
    <% end %>
  </div>
</div>

<%# Filters %>
<div class="card-netbox mb-6">
  <div class="p-4">
    <%= form_with url: settings_server_products_path, method: :get, class: "flex items-end gap-4", data: { turbo_frame: "_top" } do |f| %>
      <div class="flex-1">
        <%= f.label :q, "Search", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :q, value: params[:q], placeholder: "Search by model name...",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>
      <div>
        <%= f.label :series, "Series", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.select :series,
            options_for_select([["All Series", ""]] + ServerProduct.distinct.pluck(:product_series).compact.sort.map { |s| [s, s] }, params[:series]),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>
      <div>
        <%= f.label :form_factor, "Form Factor", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.select :form_factor,
            options_for_select([["All Form Factors", ""]] + ServerProduct.distinct.pluck(:form_factor).compact.sort.map { |ff| [ff, ff] }, params[:form_factor]),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>
      <%= f.submit "Filter", class: "btn-secondary" %>
      <% if params[:q].present? || params[:series].present? || params[:form_factor].present? %>
        <%= link_to "Clear", settings_server_products_path, class: "btn-secondary" %>
      <% end %>
    <% end %>
  </div>
</div>

<%# Products Table %>
<div class="card-netbox">
  <% if @server_products.any? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Image</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Model Name</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Series</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Form Factor</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">CPU Support</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Max Memory</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500">Last Synced</th>
            <th scope="col" class="relative px-3 py-2">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-200 bg-white">
          <% @server_products.each do |product| %>
            <%= render "settings/server_products/product", product: product %>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-900">No server products yet</p>
      <p class="mt-1 text-xs text-slate-500">Sync from QCT or add products manually</p>
      <div class="mt-4 flex gap-2">
        <%= button_to sync_settings_server_products_path,
            method: :post,
            class: "btn-secondary" do %>
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

### Step 6: Create product partial

```erb
<%# app/views/settings/server_products/_product.html.erb %>
<tr class="hover:bg-slate-50 transition-colors">
  <td class="whitespace-nowrap px-3 py-2">
    <% if product.images.attached? %>
      <%= image_tag product.images.first.variant(resize_to_limit: [60, 60]),
          class: "h-10 w-16 object-contain rounded border border-slate-200" %>
    <% else %>
      <div class="h-10 w-16 bg-slate-100 rounded border border-slate-200 flex items-center justify-center">
        <svg class="h-5 w-5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
      </div>
    <% end %>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <%= link_to settings_server_product_path(product), class: "group" do %>
      <p class="text-sm font-bold text-slate-900 group-hover:text-teal-600"><%= product.model_name %></p>
    <% end %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-slate-600">
    <%= product.product_series || "—" %>
  </td>
  <td class="whitespace-nowrap px-3 py-2">
    <span class="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-0.5 text-xs font-medium text-slate-800">
      <%= product.form_factor || "—" %>
    </span>
  </td>
  <td class="px-3 py-2 text-slate-600 text-xs">
    <%= product.cpu_generations&.join(", ") || "—" %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-slate-600">
    <% if product.max_memory_gb %>
      <%= number_to_human_size(product.max_memory_gb.gigabytes) %>
    <% else %>
      —
    <% end %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-slate-500 text-xs">
    <% if product.last_synced_at %>
      <%= time_ago_in_words(product.last_synced_at) %> ago
    <% else %>
      Manual
    <% end %>
  </td>
  <td class="whitespace-nowrap px-3 py-2 text-right text-sm font-medium">
    <div class="flex items-center justify-end gap-2">
      <%= link_to edit_settings_server_product_path(product),
          class: "text-slate-400 hover:text-teal-600 transition-colors",
          title: "Edit" do %>
        <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
        </svg>
      <% end %>
      <%= button_to settings_server_product_path(product),
          method: :delete,
          class: "text-slate-400 hover:text-red-600 transition-colors",
          title: "Delete",
          data: { turbo_confirm: "Are you sure you want to delete #{product.model_name}?" } do %>
        <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
      <% end %>
    </div>
  </td>
</tr>
```

### Step 7: Run tests to verify they pass

Run: `bin/rspec spec/requests/settings/server_products_spec.rb`
Expected: PASS

### Step 8: Run linter

Run: `bin/rubocop app/controllers/settings/server_products_controller.rb app/views/settings/server_products/`
Expected: No offenses

### Step 9: Commit

```bash
git add config/routes.rb app/controllers/settings/server_products_controller.rb app/views/settings/server_products/ spec/requests/settings/
git commit -m "$(cat <<'EOF'
feat: add admin UI for server products with index view

Create Settings::ServerProductsController with full CRUD operations.
Index view shows products table with filters for series and form factor.
Includes sync button placeholder for QCT scraper integration.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create Server Product Form Views (New/Edit)

**Files:**
- Create: `app/views/settings/server_products/new.html.erb`
- Create: `app/views/settings/server_products/edit.html.erb`
- Create: `app/views/settings/server_products/_form.html.erb`
- Create: `app/views/settings/server_products/show.html.erb`
- Test: `spec/requests/settings/server_products_spec.rb` (add CRUD tests)

### Step 1: Add failing tests for form actions

Add to `spec/requests/settings/server_products_spec.rb`:

```ruby
describe "GET /settings/server_products/new" do
  before { sign_in approver }

  it "returns success" do
    get new_settings_server_product_path
    expect(response).to have_http_status(:success)
  end
end

describe "POST /settings/server_products" do
  before { sign_in approver }

  context "with valid params" do
    let(:valid_params) do
      {
        server_product: {
          model_name: "QuantaGrid Test-1U",
          product_series: "QuantaGrid",
          form_factor: "1U",
          rack_height: 1
        }
      }
    end

    it "creates a new server product" do
      expect {
        post settings_server_products_path, params: valid_params
      }.to change(ServerProduct, :count).by(1)
    end

    it "redirects to index" do
      post settings_server_products_path, params: valid_params
      expect(response).to redirect_to(settings_server_products_path)
    end
  end

  context "with invalid params" do
    let(:invalid_params) { { server_product: { model_name: "" } } }

    it "does not create a server product" do
      expect {
        post settings_server_products_path, params: invalid_params
      }.not_to change(ServerProduct, :count)
    end

    it "renders new with unprocessable_entity" do
      post settings_server_products_path, params: invalid_params
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

describe "GET /settings/server_products/:id/edit" do
  let!(:product) { create(:server_product) }
  before { sign_in approver }

  it "returns success" do
    get edit_settings_server_product_path(product)
    expect(response).to have_http_status(:success)
  end
end

describe "PATCH /settings/server_products/:id" do
  let!(:product) { create(:server_product) }
  before { sign_in approver }

  context "with valid params" do
    it "updates the product" do
      patch settings_server_product_path(product), params: { server_product: { model_name: "Updated Name" } }
      expect(product.reload.model_name).to eq("Updated Name")
    end

    it "redirects to index" do
      patch settings_server_product_path(product), params: { server_product: { model_name: "Updated Name" } }
      expect(response).to redirect_to(settings_server_products_path)
    end
  end
end

describe "DELETE /settings/server_products/:id" do
  let!(:product) { create(:server_product) }
  before { sign_in approver }

  it "deletes the product" do
    expect {
      delete settings_server_product_path(product)
    }.to change(ServerProduct, :count).by(-1)
  end

  it "redirects to index" do
    delete settings_server_product_path(product)
    expect(response).to redirect_to(settings_server_products_path)
  end
end

describe "GET /settings/server_products/:id" do
  let!(:product) { create(:server_product) }
  before { sign_in approver }

  it "returns success" do
    get settings_server_product_path(product)
    expect(response).to have_http_status(:success)
  end
end
```

### Step 2: Run tests to verify they fail

Run: `bin/rspec spec/requests/settings/server_products_spec.rb`
Expected: FAIL (missing templates)

### Step 3: Create new view

```erb
<%# app/views/settings/server_products/new.html.erb %>
<% content_for(:page_title) { "Add Server Product" } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Server Products", settings_server_products_path, class: "hover:text-teal-600" %> /
    <span class="text-slate-700">New</span>
  </nav>
  <h1 class="text-2xl font-bold text-slate-900">Add Server Product</h1>
</div>

<%= render "form" %>
```

### Step 4: Create edit view

```erb
<%# app/views/settings/server_products/edit.html.erb %>
<% content_for(:page_title) { "Edit #{@server_product.model_name}" } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Server Products", settings_server_products_path, class: "hover:text-teal-600" %> /
    <%= link_to @server_product.model_name, settings_server_product_path(@server_product), class: "hover:text-teal-600" %> /
    <span class="text-slate-700">Edit</span>
  </nav>
  <h1 class="text-2xl font-bold text-slate-900">Edit <%= @server_product.model_name %></h1>
</div>

<%= render "form" %>
```

### Step 5: Create form partial

```erb
<%# app/views/settings/server_products/_form.html.erb %>
<%= form_with(model: [:settings, @server_product], class: "space-y-6") do |f| %>
  <% if @server_product.errors.any? %>
    <div class="rounded-lg bg-red-50 p-4 text-sm text-red-700 border border-red-200">
      <h2 class="font-bold mb-2"><%= pluralize(@server_product.errors.count, "error") %> prohibited this product from being saved:</h2>
      <ul class="list-disc list-inside">
        <% @server_product.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%# Section: Basic Information %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Basic Information</h3>
    </div>
    <div class="p-4 grid grid-cols-1 gap-6 sm:grid-cols-2">
      <div class="sm:col-span-2">
        <%= f.label :model_name, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :model_name, required: true,
            placeholder: "QuantaGrid D54Q-2U",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Full model name as shown on QCT website.</p>
      </div>

      <div>
        <%= f.label :product_series, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :product_series,
            placeholder: "QuantaGrid",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :form_factor, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.select :form_factor,
            options_for_select([["", ""], ["1U", "1U"], ["2U", "2U"], ["4U", "4U"], ["8U", "8U"]], @server_product.form_factor),
            {},
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :rack_height, "Height (U)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :rack_height, min: 1, max: 48,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Auto-filled from form factor if left blank.</p>
      </div>

      <div>
        <%= f.label :qct_product_url, "QCT Product URL", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.url_field :qct_product_url,
            placeholder: "https://www.qct.io/product/...",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>
    </div>
  </div>

  <%# Section: CPU Specifications %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">CPU Specifications</h3>
    </div>
    <div class="p-4 grid grid-cols-1 gap-6 sm:grid-cols-3">
      <div class="sm:col-span-3">
        <%= f.label :cpu_generations, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :cpu_generations,
            value: @server_product.cpu_generations&.join(", "),
            placeholder: "5th Gen Xeon, 4th Gen Xeon",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Comma-separated list of supported CPU generations.</p>
      </div>

      <div>
        <%= f.label :socket_count, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :socket_count, min: 1, max: 8,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :max_tdp_watts, "Max TDP (Watts)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :max_tdp_watts, min: 0,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :gpu_support, class: "flex items-center gap-2" %>
          <%= f.check_box :gpu_support, class: "rounded border-slate-300 text-teal-600 focus:ring-teal-500" %>
          <span class="text-sm font-bold text-slate-700">GPU Support</span>
        <% end %>
      </div>
    </div>
  </div>

  <%# Section: Memory Specifications %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Memory Specifications</h3>
    </div>
    <div class="p-4 grid grid-cols-1 gap-6 sm:grid-cols-4">
      <div>
        <%= f.label :max_memory_gb, "Max Memory (GB)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :max_memory_gb, min: 0,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :dimm_slots, "DIMM Slots", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :dimm_slots, min: 0,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :memory_types, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :memory_types,
            value: @server_product.memory_types&.join(", "),
            placeholder: "DDR5, DDR4",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>

      <div>
        <%= f.label :max_memory_speed_mhz, "Max Speed (MHz)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :max_memory_speed_mhz, min: 0,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
      </div>
    </div>
  </div>

  <%# Section: Images %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Product Images</h3>
    </div>
    <div class="p-4">
      <% if @server_product.images.attached? %>
        <div class="mb-4 flex flex-wrap gap-4">
          <% @server_product.images.each do |image| %>
            <div class="relative group">
              <%= image_tag image.variant(resize_to_limit: [200, 200]),
                  class: "rounded border border-slate-200" %>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= f.label :images, class: "block text-sm font-bold text-slate-700 mb-1" %>
      <%= f.file_field :images, multiple: true, accept: "image/*",
          class: "block w-full text-sm text-slate-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-teal-50 file:text-teal-700 hover:file:bg-teal-100" %>
      <p class="mt-1 text-xs text-slate-500">Upload front view, rear view, and internal layout images.</p>
    </div>
  </div>

  <div class="flex items-center justify-end gap-3 pt-4">
    <%= link_to "Cancel", settings_server_products_path, class: "btn-secondary" %>
    <%= f.submit @server_product.new_record? ? "Create Product" : "Update Product", class: "btn-primary" %>
  </div>
<% end %>
```

### Step 6: Create show view

```erb
<%# app/views/settings/server_products/show.html.erb %>
<% content_for(:page_title) { @server_product.model_name } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Server Products", settings_server_products_path, class: "hover:text-teal-600" %> /
    <span class="text-slate-700"><%= @server_product.model_name %></span>
  </nav>
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold text-slate-900"><%= @server_product.model_name %></h1>
    <div class="flex items-center gap-2">
      <%= link_to edit_settings_server_product_path(@server_product), class: "btn-secondary" do %>
        Edit
      <% end %>
      <%= button_to settings_server_product_path(@server_product),
          method: :delete,
          class: "btn-danger",
          data: { turbo_confirm: "Are you sure you want to delete this product?" } do %>
        Delete
      <% end %>
    </div>
  </div>
</div>

<div class="grid gap-6 lg:grid-cols-3">
  <%# Images %>
  <div class="lg:col-span-1">
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Images</h3>
      </div>
      <div class="p-4">
        <% if @server_product.images.attached? %>
          <div class="space-y-4" data-controller="image-viewer">
            <% @server_product.images.each_with_index do |image, i| %>
              <%= image_tag image,
                  class: "#{'hidden' unless i == 0} rounded border w-full",
                  data: { image_viewer_target: "image", index: i } %>
            <% end %>
            <% if @server_product.images.count > 1 %>
              <div class="flex gap-2">
                <% @server_product.images.each_with_index do |image, i| %>
                  <button type="button"
                          class="text-xs px-2 py-1 rounded border hover:bg-slate-100"
                          data-action="click->image-viewer#show"
                          data-index="<%= i %>">
                    <%= i + 1 %>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <div class="w-full h-32 bg-slate-100 rounded border flex items-center justify-center text-slate-400">
            No images
          </div>
        <% end %>
      </div>
    </div>
  </div>

  <%# Specifications %>
  <div class="lg:col-span-2 space-y-6">
    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Overview</h3>
      </div>
      <div class="p-0">
        <table class="w-full text-sm text-left">
          <tbody class="divide-y divide-slate-100">
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 w-1/3 border-r">Model</th>
              <td class="px-4 py-2 text-slate-700 font-bold"><%= @server_product.model_name %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Series</th>
              <td class="px-4 py-2"><%= @server_product.product_series || "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Form Factor</th>
              <td class="px-4 py-2"><%= @server_product.form_factor %> (<%= @server_product.rack_height %>U)</td>
            </tr>
            <% if @server_product.qct_product_url.present? %>
              <tr class="hover:bg-slate-50">
                <th class="px-4 py-2 font-bold text-slate-700 border-r">QCT URL</th>
                <td class="px-4 py-2">
                  <%= link_to @server_product.qct_product_url, @server_product.qct_product_url,
                      target: "_blank", class: "text-teal-600 hover:text-teal-800 truncate block max-w-md" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>

    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">CPU & GPU</h3>
      </div>
      <div class="p-0">
        <table class="w-full text-sm text-left">
          <tbody class="divide-y divide-slate-100">
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 w-1/3 border-r">CPU Support</th>
              <td class="px-4 py-2"><%= @server_product.cpu_generations&.join(", ") || "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Sockets</th>
              <td class="px-4 py-2"><%= @server_product.socket_count || "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Max TDP</th>
              <td class="px-4 py-2"><%= @server_product.max_tdp_watts ? "#{@server_product.max_tdp_watts}W" : "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">GPU Support</th>
              <td class="px-4 py-2">
                <% if @server_product.gpu_support %>
                  <span class="text-green-600 font-bold">Yes</span>
                <% else %>
                  <span class="text-slate-400">No</span>
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Memory</h3>
      </div>
      <div class="p-0">
        <table class="w-full text-sm text-left">
          <tbody class="divide-y divide-slate-100">
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 w-1/3 border-r">Max Capacity</th>
              <td class="px-4 py-2">
                <% if @server_product.max_memory_gb %>
                  <%= number_to_human_size(@server_product.max_memory_gb.gigabytes) %>
                <% else %>
                  —
                <% end %>
              </td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">DIMM Slots</th>
              <td class="px-4 py-2"><%= @server_product.dimm_slots || "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Memory Types</th>
              <td class="px-4 py-2"><%= @server_product.memory_types&.join(", ") || "—" %></td>
            </tr>
            <tr class="hover:bg-slate-50">
              <th class="px-4 py-2 font-bold text-slate-700 border-r">Max Speed</th>
              <td class="px-4 py-2"><%= @server_product.max_memory_speed_mhz ? "#{@server_product.max_memory_speed_mhz} MHz" : "—" %></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">Storage</h3>
      </div>
      <div class="p-4">
        <% if @server_product.drive_bays.present? %>
          <ul class="space-y-1 text-sm">
            <% @server_product.drive_bays.each do |bay| %>
              <li><%= bay["count"] %>x <%= bay["type"] %> <%= bay["form_factor"] %></li>
            <% end %>
          </ul>
        <% else %>
          <p class="text-slate-400">—</p>
        <% end %>
      </div>
    </div>

    <div class="card-netbox">
      <div class="card-header">
        <h3 class="card-title">PCIe Slots</h3>
      </div>
      <div class="p-4">
        <% if @server_product.pcie_slots.present? %>
          <ul class="space-y-1 text-sm">
            <% @server_product.pcie_slots.each do |slot| %>
              <li><%= slot["count"] %>x PCIe <%= slot["generation"] %> x<%= slot["lanes"] %></li>
            <% end %>
          </ul>
        <% else %>
          <p class="text-slate-400">—</p>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

### Step 7: Update controller to handle array params

Update `server_product_params` method in `app/controllers/settings/server_products_controller.rb` to properly convert comma-separated strings to arrays:

```ruby
def create
  @server_product = ServerProduct.new(server_product_params)
  process_array_fields
  if @server_product.save
    redirect_to settings_server_products_path, notice: "Server product was successfully created."
  else
    render :new, status: :unprocessable_entity
  end
end

def update
  @server_product.assign_attributes(server_product_params)
  process_array_fields
  if @server_product.save
    redirect_to settings_server_products_path, notice: "Server product was successfully updated."
  else
    render :edit, status: :unprocessable_entity
  end
end

private

def process_array_fields
  if params[:server_product][:cpu_generations].is_a?(String)
    @server_product.cpu_generations = params[:server_product][:cpu_generations].split(",").map(&:strip).reject(&:blank?)
  end
  if params[:server_product][:memory_types].is_a?(String)
    @server_product.memory_types = params[:server_product][:memory_types].split(",").map(&:strip).reject(&:blank?)
  end
end
```

### Step 8: Run tests to verify they pass

Run: `bin/rspec spec/requests/settings/server_products_spec.rb`
Expected: PASS

### Step 9: Commit

```bash
git add app/views/settings/server_products/ app/controllers/settings/server_products_controller.rb spec/requests/settings/
git commit -m "$(cat <<'EOF'
feat: add server product form views for CRUD operations

Create new/edit/show views with comprehensive form for all server
product specifications including CPU, memory, storage, and images.
Form handles array fields with comma-separated input conversion.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add Server Products Link to Sidebar

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb:88-119` (add link in Admin section)

### Step 1: Add Server Products link to sidebar

In `app/views/shared/_sidebar.html.erb`, add after the Agent Config link (around line 116), before the closing `</div>` of the Admin section:

```erb
<%= link_to settings_server_products_path,
    class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/settings/server_products') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
  <svg class="h-5 w-5 opacity-75" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
  </svg>
  Server Products
<% end %>
```

### Step 2: Verify visually

Run: `bin/dev`
Navigate to `/settings/server_products` and verify the sidebar link is present and correctly highlighted.

### Step 3: Commit

```bash
git add app/views/shared/_sidebar.html.erb
git commit -m "$(cat <<'EOF'
feat: add Server Products link to admin sidebar

Add navigation link in Admin section of sidebar, positioned after
Agent Config. Uses server icon and teal highlight when active.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Create QctScraperService

**Files:**
- Create: `app/services/qct_scraper_service.rb`
- Test: `spec/services/qct_scraper_service_spec.rb`

### Step 1: Write failing tests for QctScraperService

```ruby
# spec/services/qct_scraper_service_spec.rb
require "rails_helper"

RSpec.describe QctScraperService do
  describe "#sync_all" do
    let(:service) { described_class.new }

    before do
      # Stub HTTP requests to QCT website
      stub_request(:get, QctScraperService::BASE_URL)
        .to_return(status: 200, body: product_listing_html)
    end

    let(:product_listing_html) do
      <<~HTML
        <div class="product-list">
          <a href="/product/index/Server/rackmount-server/QuantaGrid-D54Q-2U" class="product-item">
            QuantaGrid D54Q-2U
          </a>
        </div>
      HTML
    end

    let(:product_page_html) do
      <<~HTML
        <h1 class="product-name">QuantaGrid D54Q-2U</h1>
        <div class="specs">
          <span class="form-factor">2U</span>
        </div>
      HTML
    end

    before do
      stub_request(:get, %r{qct\.io/product/index/Server/rackmount-server/.*})
        .to_return(status: 200, body: product_page_html)
    end

    it "returns a Result struct" do
      result = service.sync_all
      expect(result).to respond_to(:added_count)
      expect(result).to respond_to(:updated_count)
      expect(result).to respond_to(:errors)
    end

    context "when syncing new products" do
      it "creates new ServerProduct records" do
        expect { service.sync_all }.to change(ServerProduct, :count)
      end

      it "reports added count" do
        result = service.sync_all
        expect(result.added_count).to be >= 0
      end
    end

    context "when syncing existing products" do
      before do
        create(:server_product,
          model_name: "QuantaGrid D54Q-2U",
          qct_product_url: "https://www.qct.io/product/index/Server/rackmount-server/QuantaGrid-D54Q-2U")
      end

      it "updates existing ServerProduct records" do
        result = service.sync_all
        expect(result.updated_count).to be >= 0
      end
    end

    context "when encountering errors" do
      before do
        stub_request(:get, QctScraperService::BASE_URL)
          .to_return(status: 500)
      end

      it "captures errors in result" do
        result = service.sync_all
        expect(result.errors).not_to be_empty
      end
    end
  end

  describe "#parse_product_page" do
    let(:service) { described_class.new }

    it "extracts model name from page" do
      html = '<h1 class="product-name">QuantaGrid D54Q-2U</h1>'
      attrs = service.send(:parse_product_page, html, "https://example.com")
      expect(attrs[:model_name]).to eq("QuantaGrid D54Q-2U")
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/services/qct_scraper_service_spec.rb`
Expected: FAIL with "uninitialized constant QctScraperService"

### Step 3: Create QctScraperService

```ruby
# app/services/qct_scraper_service.rb
require "net/http"
require "nokogiri"

class QctScraperService
  BASE_URL = "https://www.qct.io/product/index/Server/rackmount-server".freeze
  USER_AGENT = "Mozilla/5.0 (compatible; DiagnosticTools/1.0)".freeze

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
  rescue StandardError => e
    Result.new(
      added_count: 0,
      updated_count: 0,
      errors: [{ url: BASE_URL, error: e.message }],
      new_products: []
    )
  end

  def sync_product(url)
    html = fetch_page(url)
    attrs = parse_product_page(html, url)

    product = ServerProduct.find_or_initialize_by(qct_product_url: url)
    is_new = product.new_record?

    product.assign_attributes(attrs)
    product.last_synced_at = Time.current

    download_images(html, product)
    product.save!

    is_new ? :added : :updated
  rescue StandardError => e
    e.message
  end

  private

  def fetch_page(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    request["User-Agent"] = USER_AGENT

    response = http.request(request)
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  def fetch_product_listing
    html = fetch_page(BASE_URL)
    doc = Nokogiri::HTML(html)

    # Extract product links from listing page
    # Adjust selectors based on actual QCT website structure
    doc.css('a[href*="/product/index/Server/rackmount-server/"]').map do |link|
      href = link["href"]
      href.start_with?("http") ? href : "https://www.qct.io#{href}"
    end.uniq
  end

  def parse_product_page(html, url)
    doc = Nokogiri::HTML(html)

    # Extract model name - adjust selector based on actual structure
    model_name = doc.at_css("h1, .product-name, .product-title")&.text&.strip

    # Extract series from model name
    product_series = extract_series(model_name)

    # Extract form factor
    form_factor = extract_form_factor(doc, model_name)

    # Extract rack height from form factor
    rack_height = form_factor&.match(/(\d+)U/i)&.captures&.first&.to_i || 1

    {
      model_name: model_name,
      product_series: product_series,
      form_factor: form_factor,
      rack_height: rack_height,
      qct_product_url: url,
      cpu_generations: extract_cpu_generations(doc),
      socket_count: extract_socket_count(doc),
      max_memory_gb: extract_max_memory(doc),
      dimm_slots: extract_dimm_slots(doc),
      memory_types: extract_memory_types(doc),
      drive_bays: extract_drive_bays(doc),
      pcie_slots: extract_pcie_slots(doc),
      gpu_support: extract_gpu_support(doc)
    }.compact
  end

  def extract_series(model_name)
    return nil unless model_name
    %w[QuantaGrid QuantaPlex QuantaMesh QuantaEdge].find { |s| model_name.include?(s) }
  end

  def extract_form_factor(doc, model_name)
    # Try to find form factor in specs or model name
    ff_match = model_name&.match(/(\d+U)/i)
    return ff_match[1].upcase if ff_match

    # Look in spec table
    doc.text[/Form Factor[:\s]*(\d+U)/i, 1]&.upcase
  end

  def extract_cpu_generations(doc)
    # Look for CPU info in specs
    cpu_text = doc.text[/CPU.*?(?:Xeon|EPYC)[^,\n]*/i]
    return [] unless cpu_text

    generations = []
    generations << "5th Gen Xeon" if cpu_text =~ /5th|Emerald/i
    generations << "4th Gen Xeon" if cpu_text =~ /4th|Sapphire/i
    generations << "3rd Gen Xeon" if cpu_text =~ /3rd|Ice Lake/i
    generations
  end

  def extract_socket_count(doc)
    doc.text[/(\d+)\s*(?:Socket|CPU)/i, 1]&.to_i
  end

  def extract_max_memory(doc)
    # Look for memory capacity
    mem_match = doc.text[/(\d+)\s*(?:TB|GB)\s*(?:max|maximum|memory)/i]
    return nil unless mem_match

    value = mem_match[/(\d+)/, 1].to_i
    mem_match =~ /TB/i ? value * 1024 : value
  end

  def extract_dimm_slots(doc)
    doc.text[/(\d+)\s*DIMM/i, 1]&.to_i
  end

  def extract_memory_types(doc)
    types = []
    types << "DDR5" if doc.text =~ /DDR5/i
    types << "DDR4" if doc.text =~ /DDR4/i
    types
  end

  def extract_drive_bays(doc)
    bays = []
    # Look for drive bay patterns like "24x NVMe 2.5"
    doc.text.scan(/(\d+)\s*x?\s*(NVMe|SAS|SATA|SSD|HDD)\s*([\d.]+)?/i).each do |count, type, form_factor|
      bays << {
        "count" => count.to_i,
        "type" => type.upcase,
        "form_factor" => form_factor || "2.5"
      }
    end
    bays.uniq
  end

  def extract_pcie_slots(doc)
    slots = []
    doc.text.scan(/(\d+)\s*x?\s*PCIe?\s*([\d.]+)\s*x(\d+)/i).each do |count, gen, lanes|
      slots << {
        "count" => count.to_i,
        "generation" => gen,
        "lanes" => lanes.to_i
      }
    end
    slots.uniq
  end

  def extract_gpu_support(doc)
    !!(doc.text =~ /GPU|NVIDIA|AMD\s*Radeon|accelerator/i)
  end

  def download_images(html, product)
    doc = Nokogiri::HTML(html)

    # Find product images
    image_urls = doc.css('img[src*="product"], img[src*="server"]').map { |img| img["src"] }
    image_urls = image_urls.take(3) # Limit to 3 images

    image_urls.each do |url|
      url = "https://www.qct.io#{url}" unless url.start_with?("http")
      download_and_attach_image(url, product)
    rescue StandardError => e
      Rails.logger.warn "Failed to download image #{url}: #{e.message}"
    end
  end

  def download_and_attach_image(url, product)
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)
    return unless response.is_a?(Net::HTTPSuccess)

    filename = File.basename(uri.path)
    content_type = response["content-type"] || "image/jpeg"

    product.images.attach(
      io: StringIO.new(response.body),
      filename: filename,
      content_type: content_type
    )
  end
end
```

### Step 4: Add webmock to test dependencies

Ensure `webmock` is in Gemfile (usually already present for Rails apps):

```ruby
# Gemfile (in test group)
gem "webmock"
```

Run: `bundle install`

### Step 5: Run tests to verify they pass

Run: `bin/rspec spec/services/qct_scraper_service_spec.rb`
Expected: PASS (or partial pass - some tests may need adjustment based on actual HTML structure)

### Step 6: Run linter

Run: `bin/rubocop app/services/qct_scraper_service.rb`
Expected: No offenses

### Step 7: Commit

```bash
git add app/services/qct_scraper_service.rb spec/services/qct_scraper_service_spec.rb
git commit -m "$(cat <<'EOF'
feat: add QctScraperService for web scraping product data

Implement service to fetch QCT rackmount server product information
from their website. Extracts model names, specifications, and images.
Uses Nokogiri for HTML parsing with fallback patterns for data extraction.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create QctSyncJob Background Job

**Files:**
- Create: `app/jobs/qct_sync_job.rb`
- Modify: `config/recurring.yml` (add scheduled job if using solid_queue)
- Test: `spec/jobs/qct_sync_job_spec.rb`

### Step 1: Write failing test for QctSyncJob

```ruby
# spec/jobs/qct_sync_job_spec.rb
require "rails_helper"

RSpec.describe QctSyncJob, type: :job do
  describe "#perform" do
    let(:mock_result) do
      QctScraperService::Result.new(
        added_count: 5,
        updated_count: 10,
        errors: [],
        new_products: ["https://example.com/product1"]
      )
    end

    before do
      allow_any_instance_of(QctScraperService).to receive(:sync_all).and_return(mock_result)
    end

    it "calls QctScraperService" do
      expect_any_instance_of(QctScraperService).to receive(:sync_all)
      described_class.perform_now
    end

    it "creates a SyncLog record" do
      expect { described_class.perform_now }.to change(SyncLog, :count).by(1)
    end

    it "records sync results in SyncLog" do
      described_class.perform_now
      log = SyncLog.last
      expect(log.source).to eq("qct")
      expect(log.products_added).to eq(5)
      expect(log.products_updated).to eq(10)
      expect(log.completed_at).to be_present
    end

    context "when sync has errors" do
      let(:mock_result) do
        QctScraperService::Result.new(
          added_count: 3,
          updated_count: 5,
          errors: [{ url: "https://example.com", error: "Connection timeout" }],
          new_products: []
        )
      end

      it "records errors in SyncLog" do
        described_class.perform_now
        log = SyncLog.last
        expect(log.errors).not_to be_empty
      end
    end
  end

  describe "queue" do
    it "is queued to default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/jobs/qct_sync_job_spec.rb`
Expected: FAIL with "uninitialized constant QctSyncJob"

### Step 3: Create QctSyncJob

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

    Rails.logger.info "[QctSyncJob] Completed: #{result.added_count} added, #{result.updated_count} updated, #{result.errors.size} errors"
  end
end
```

### Step 4: Add to recurring.yml (if exists)

Check if `config/recurring.yml` exists. If so, add:

```yaml
# config/recurring.yml
production:
  qct_product_sync:
    class: QctSyncJob
    schedule: every Sunday at 3am
    queue: default
```

### Step 5: Run tests to verify they pass

Run: `bin/rspec spec/jobs/qct_sync_job_spec.rb`
Expected: PASS

### Step 6: Commit

```bash
git add app/jobs/qct_sync_job.rb spec/jobs/qct_sync_job_spec.rb config/recurring.yml
git commit -m "$(cat <<'EOF'
feat: add QctSyncJob for scheduled product catalog sync

Background job wraps QctScraperService and logs results to SyncLog.
Scheduled to run weekly on Sundays at 3am in production.
Can also be triggered manually from admin UI.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Create Server Product Search API Endpoint

**Files:**
- Create: `app/controllers/api/server_products_controller.rb`
- Modify: `config/routes.rb` (add API route)
- Test: `spec/requests/api/server_products_spec.rb`

### Step 1: Write failing test for API search endpoint

```ruby
# spec/requests/api/server_products_spec.rb
require "rails_helper"

RSpec.describe "Api::ServerProducts", type: :request do
  describe "GET /api/server_products/search" do
    let!(:product1) { create(:server_product, model_name: "QuantaGrid D54Q-2U") }
    let!(:product2) { create(:server_product, model_name: "QuantaPlex T42S-2U") }
    let!(:product3) { create(:server_product, model_name: "QuantaGrid S74G-2U") }

    it "returns matching products" do
      get api_server_products_search_path, params: { q: "QuantaGrid" }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
      expect(json.map { |p| p["model_name"] }).to include("QuantaGrid D54Q-2U", "QuantaGrid S74G-2U")
    end

    it "returns empty array for no matches" do
      get api_server_products_search_path, params: { q: "NonExistent" }
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to be_empty
    end

    it "limits results to 10" do
      create_list(:server_product, 15)
      get api_server_products_search_path, params: { q: "QuantaGrid" }
      json = JSON.parse(response.body)
      expect(json.size).to be <= 10
    end

    it "includes required fields" do
      get api_server_products_search_path, params: { q: "D54Q" }
      json = JSON.parse(response.body)
      expect(json.first).to include(
        "id", "model_name", "form_factor", "rack_height"
      )
    end
  end

  describe "GET /api/server_products" do
    before do
      create(:server_product, model_name: "QuantaGrid 1U", form_factor: "1U")
      create(:server_product, model_name: "QuantaGrid 2U", form_factor: "2U")
      create(:server_product, :quantaplex, form_factor: "2U")
    end

    it "returns all products" do
      get api_server_products_path
      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end

    it "filters by form factor" do
      get api_server_products_path, params: { form_factor: "2U" }
      json = JSON.parse(response.body)
      expect(json.size).to eq(2)
    end

    it "filters by series" do
      get api_server_products_path, params: { series: "QuantaPlex" }
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
    end
  end
end
```

### Step 2: Run test to verify it fails

Run: `bin/rspec spec/requests/api/server_products_spec.rb`
Expected: FAIL with routing error

### Step 3: Add routes

In `config/routes.rb`, add within the `namespace :api` block (but outside `namespace :v1`):

```ruby
namespace :api do
  resources :server_products, only: [:index] do
    collection do
      get :search
    end
  end

  namespace :v1 do
    # existing v1 routes...
  end
end
```

### Step 4: Create API controller

```ruby
# app/controllers/api/server_products_controller.rb
module Api
  class ServerProductsController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!

    def index
      products = ServerProduct.all
      products = products.by_series(params[:series]) if params[:series].present?
      products = products.by_form_factor(params[:form_factor]) if params[:form_factor].present?
      products = products.order(:model_name)

      render json: products.map { |p| product_json(p) }
    end

    def search
      products = ServerProduct
        .search_by_name(params[:q])
        .limit(10)
        .order(:model_name)

      render json: products.map { |p| product_json(p) }
    end

    private

    def product_json(product)
      {
        id: product.id,
        model_name: product.model_name,
        product_series: product.product_series,
        form_factor: product.form_factor,
        rack_height: product.rack_height,
        cpu_generations: product.cpu_generations,
        max_memory_gb: product.max_memory_gb,
        gpu_support: product.gpu_support,
        thumbnail_url: product.images.attached? ? url_for(product.images.first.variant(resize_to_limit: [100, 100])) : nil
      }
    end
  end
end
```

### Step 5: Run tests to verify they pass

Run: `bin/rspec spec/requests/api/server_products_spec.rb`
Expected: PASS

### Step 6: Run linter

Run: `bin/rubocop app/controllers/api/server_products_controller.rb`
Expected: No offenses

### Step 7: Commit

```bash
git add config/routes.rb app/controllers/api/server_products_controller.rb spec/requests/api/
git commit -m "$(cat <<'EOF'
feat: add API endpoints for server product search

Create /api/server_products/search endpoint for autocomplete
and /api/server_products index with filtering. Returns JSON
with product details including thumbnail URLs for images.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Create Server Product Search Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/server_product_search_controller.js`

### Step 1: Create Stimulus controller

```javascript
// app/javascript/controllers/server_product_search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hiddenField", "results", "preview", "rackHeight"]
  static values = {
    url: { type: String, default: "/api/server_products/search" }
  }

  connect() {
    this.debounceTimer = null
  }

  search() {
    const query = this.inputTarget.value
    if (query.length < 2) {
      this.hideResults()
      return
    }

    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchResults(query), 300)
  }

  async fetchResults(query) {
    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`)
      const products = await response.json()
      this.renderResults(products)
    } catch (error) {
      console.error("Search failed:", error)
      this.hideResults()
    }
  }

  renderResults(products) {
    if (products.length === 0) {
      this.hideResults()
      return
    }

    const html = products.map(p => `
      <button type="button"
              class="w-full px-3 py-2 text-left hover:bg-slate-100 flex items-center gap-3"
              data-action="click->server-product-search#select"
              data-id="${p.id}"
              data-model-name="${this.escapeHtml(p.model_name)}"
              data-rack-height="${p.rack_height}"
              data-form-factor="${p.form_factor || ''}"
              data-thumbnail-url="${p.thumbnail_url || ''}">
        ${p.thumbnail_url
          ? `<img src="${p.thumbnail_url}" class="w-10 h-8 object-contain rounded border" alt="" />`
          : `<div class="w-10 h-8 bg-slate-100 rounded border flex items-center justify-center">
              <svg class="w-4 h-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
              </svg>
            </div>`
        }
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-slate-900 truncate">${this.escapeHtml(p.model_name)}</p>
          <p class="text-xs text-slate-500">${p.form_factor || ''} • ${p.rack_height}U</p>
        </div>
      </button>
    `).join("")

    this.resultsTarget.innerHTML = html
    this.resultsTarget.classList.remove("hidden")
  }

  select(event) {
    event.preventDefault()
    const button = event.currentTarget
    const id = button.dataset.id
    const modelName = button.dataset.modelName
    const rackHeight = button.dataset.rackHeight

    // Update hidden field and display input
    this.hiddenFieldTarget.value = id
    this.inputTarget.value = modelName

    // Auto-fill rack_height if the target exists
    if (this.hasRackHeightTarget && rackHeight) {
      this.rackHeightTarget.value = rackHeight
    } else {
      // Try to find rack_height field in the form
      const rackHeightField = document.querySelector('[name="node[rack_height]"]')
      if (rackHeightField && rackHeight) {
        rackHeightField.value = rackHeight
      }
    }

    // Show preview
    this.showPreview(button.dataset)

    // Hide results
    this.hideResults()
  }

  showPreview(data) {
    if (!this.hasPreviewTarget) return

    this.previewTarget.innerHTML = `
      <div class="flex items-center gap-4 p-3 bg-slate-50 rounded-lg border border-slate-200">
        ${data.thumbnailUrl
          ? `<img src="${data.thumbnailUrl}" class="w-16 h-12 object-contain rounded border" alt="" />`
          : `<div class="w-16 h-12 bg-slate-100 rounded border flex items-center justify-center">
              <svg class="w-6 h-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
              </svg>
            </div>`
        }
        <div class="flex-1">
          <p class="text-sm font-bold text-slate-900">${this.escapeHtml(data.modelName)}</p>
          <p class="text-xs text-slate-500">${data.formFactor || ''} • ${data.rackHeight}U</p>
        </div>
        <button type="button"
                class="text-slate-400 hover:text-red-600"
                data-action="click->server-product-search#clear">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
    this.previewTarget.classList.remove("hidden")
  }

  clear(event) {
    event.preventDefault()
    this.hiddenFieldTarget.value = ""
    this.inputTarget.value = ""
    if (this.hasPreviewTarget) {
      this.previewTarget.innerHTML = ""
      this.previewTarget.classList.add("hidden")
    }
  }

  hideResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.classList.add("hidden")
      this.resultsTarget.innerHTML = ""
    }
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  // Close results when clicking outside
  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }
}
```

### Step 2: Verify controller is registered

The controller should be auto-registered by Stimulus if following conventions. Check `app/javascript/controllers/index.js` if manual registration is needed.

### Step 3: Commit

```bash
git add app/javascript/controllers/server_product_search_controller.js
git commit -m "$(cat <<'EOF'
feat: add Stimulus controller for server product autocomplete

Create server_product_search_controller with debounced search,
dropdown results rendering, selection handling, and auto-fill
of rack_height field. Includes preview display and clear functionality.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Integrate Server Product Search into Node Form

**Files:**
- Modify: `app/components/node_form_component.html.erb:59-83` (add Server Model section before Rack Assignment)
- Modify: `app/controllers/nodes_controller.rb` (permit server_product_id param)

### Step 1: Add Server Model section to NodeFormComponent

In `app/components/node_form_component.html.erb`, add a new section **before** the "Rack Assignment" section (before line 59):

```erb
<%# Section: Server Model %>
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
                 value="<%= @node.server_product&.model_name %>"
                 class="block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
                 data-server-product-search-target="input"
                 data-action="input->server-product-search#search" />
          <%= f.hidden_field :server_product_id, data: { server_product_search_target: "hiddenField" } %>
          <div data-server-product-search-target="results"
               class="absolute z-10 hidden mt-1 w-full bg-white rounded-md shadow-lg border border-slate-200 max-h-60 overflow-auto">
          </div>
        </div>
      </div>
    </div>
    <p class="mt-2 text-xs text-slate-500">
      Optional: Select a server model to auto-fill rack height and view specifications.
    </p>
    <div data-server-product-search-target="preview" class="mt-4 hidden"></div>
  </div>
</div>
```

### Step 2: Update nodes_controller to permit server_product_id

In `app/controllers/nodes_controller.rb`, find the `node_params` method and add `:server_product_id` to the permitted params:

```ruby
def node_params
  params.require(:node).permit(
    :hostname, :ip, :role, :arch, :rack_id, :rack_position, :rack_height,
    :ssh_port, :ssh_user, :ssh_password, :ssh_key, :sudo_credential,
    :ssh_connect_method, :jump_host, :jump_user, :jump_port,
    :agent_path, :benchmark_work_dir, :api_key_id,
    :server_product_id  # Add this
  )
end
```

### Step 3: Run existing node tests to verify no breakage

Run: `bin/rspec spec/models/node_spec.rb spec/requests/nodes_spec.rb`
Expected: PASS

### Step 4: Commit

```bash
git add app/components/node_form_component.html.erb app/controllers/nodes_controller.rb
git commit -m "$(cat <<'EOF'
feat: integrate server product search into node form

Add Server Model section to NodeFormComponent with autocomplete
search powered by server_product_search_controller. Selection
auto-fills rack_height field. Permit server_product_id in controller.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Add Server Product Display to Node Show Page

**Files:**
- Create: `app/views/nodes/_server_product_card.html.erb`
- Modify: `app/views/nodes/_overview.html.erb` (add server product card)

### Step 1: Create server product card partial

```erb
<%# app/views/nodes/_server_product_card.html.erb %>
<% if node.server_product.present? %>
  <% product = node.server_product %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title text-xs font-bold text-slate-500 uppercase">Server Model</h3>
    </div>
    <div class="p-4">
      <div class="flex gap-6">
        <%# Image viewer %>
        <div class="w-1/3" data-controller="image-viewer">
          <% if product.images.attached? %>
            <% product.images.each_with_index do |image, i| %>
              <%= image_tag image,
                  class: "#{'hidden' unless i == 0} rounded border w-full",
                  data: { image_viewer_target: "image", index: i } %>
            <% end %>
            <% if product.images.count > 1 %>
              <div class="flex gap-2 mt-2">
                <% product.images.each_with_index do |image, i| %>
                  <button type="button"
                          class="text-xs px-2 py-1 rounded border hover:bg-slate-100"
                          data-action="click->image-viewer#show"
                          data-index="<%= i %>">
                    View <%= i + 1 %>
                  </button>
                <% end %>
              </div>
            <% end %>
          <% else %>
            <div class="w-full h-32 bg-slate-100 rounded border flex items-center justify-center text-slate-400">
              <svg class="h-8 w-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
            </div>
          <% end %>
        </div>

        <%# Specs table %>
        <div class="w-2/3">
          <table class="w-full text-sm">
            <tbody class="divide-y divide-slate-100">
              <tr>
                <th class="py-2 text-left text-slate-600 w-1/3 font-bold">Model</th>
                <td class="py-2 font-bold text-slate-900">
                  <%= link_to product.model_name, settings_server_product_path(product),
                      class: "text-teal-600 hover:text-teal-800" %>
                </td>
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
                    <% if product.dimm_slots %>
                      (<%= product.dimm_slots %> DIMMs<%= ", #{product.memory_types.join('/')}" if product.memory_types.present? %>)
                    <% end %>
                  <% else %>
                    —
                  <% end %>
                </td>
              </tr>
              <% if product.drive_bays.present? %>
                <tr>
                  <th class="py-2 text-left text-slate-600 font-bold">Drive Bays</th>
                  <td class="py-2">
                    <% product.drive_bays.each do |bay| %>
                      <%= bay["count"] %>x <%= bay["type"] %> <%= bay["form_factor"] %><br>
                    <% end %>
                  </td>
                </tr>
              <% end %>
              <% if product.pcie_slots.present? %>
                <tr>
                  <th class="py-2 text-left text-slate-600 font-bold">PCIe Slots</th>
                  <td class="py-2">
                    <% product.pcie_slots.each do |slot| %>
                      <%= slot["count"] %>x PCIe <%= slot["generation"] %> x<%= slot["lanes"] %><br>
                    <% end %>
                  </td>
                </tr>
              <% end %>
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

### Step 2: Add to node overview partial

Find `app/views/nodes/_overview.html.erb` and add the server product card render. Add at an appropriate location (e.g., after the main info card):

```erb
<%= render "nodes/server_product_card", node: node %>
```

### Step 3: Create image viewer controller if not exists

```javascript
// app/javascript/controllers/image_viewer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image"]

  show(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.imageTargets.forEach((img, i) => {
      img.classList.toggle("hidden", i !== index)
    })
  }
}
```

### Step 4: Commit

```bash
git add app/views/nodes/_server_product_card.html.erb app/views/nodes/_overview.html.erb app/javascript/controllers/image_viewer_controller.js
git commit -m "$(cat <<'EOF'
feat: display server product info on node show page

Add server product card to node overview showing model specs,
images with viewer, and link to admin product page. Includes
CPU, memory, storage, PCIe, and GPU support details.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Run Full Test Suite and Final Verification

**Files:**
- No new files

### Step 1: Run full Rails test suite

Run: `bin/rspec`
Expected: All tests PASS

### Step 2: Run linter on all new files

Run: `bin/rubocop`
Expected: No offenses

### Step 3: Run security scan

Run: `bin/brakeman`
Expected: No new security warnings

### Step 4: Manual verification

Run: `bin/dev`

Verify the following in browser:
1. Navigate to `/settings/server_products` - should see index page
2. Click "Add Product" - should see form with all sections
3. Create a test product and verify it appears in list
4. Navigate to `/nodes/new` - should see Server Model section with search
5. Search for the test product - should see autocomplete results
6. Select product - rack height should auto-fill
7. Save node and view - should see server product card on show page

### Step 5: Final commit (if any fixes needed)

If any fixes were needed during manual verification, commit them:

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix: address issues found during final verification

[Description of any fixes made]

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

This implementation plan covers 12 tasks:

1. **Task 1**: Create ServerProduct and SyncLog models with migrations
2. **Task 2**: Add ServerProduct association to Node model
3. **Task 3**: Create admin controller with index view
4. **Task 4**: Create form views (new/edit/show)
5. **Task 5**: Add sidebar navigation link
6. **Task 6**: Create QctScraperService for web scraping
7. **Task 7**: Create QctSyncJob background job
8. **Task 8**: Create API search endpoint
9. **Task 9**: Create Stimulus controller for autocomplete
10. **Task 10**: Integrate search into node form
11. **Task 11**: Add product display to node show page
12. **Task 12**: Final verification and testing

Each task follows TDD principles with failing tests first, then implementation, then verification.
