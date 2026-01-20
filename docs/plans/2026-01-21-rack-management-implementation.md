# Rack Management Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add rack management to track physical node locations with interactive visual diagrams.

**Architecture:** Site (room) → Rack hierarchy. Nodes optionally belong to racks with position/height. Interactive Fabric.js canvas for drag-and-drop layout editing.

**Tech Stack:** Rails 7.2, Hotwire (Turbo + Stimulus), Fabric.js, PostgreSQL, RSpec, FactoryBot

---

## Task 1: Site Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_sites.rb`
- Create: `app/models/site.rb`
- Create: `spec/models/site_spec.rb`
- Create: `spec/factories/sites.rb`

**Step 1: Write the failing test**

Create `spec/models/site_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Site, type: :model do
  describe "validations" do
    subject { build(:site) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
  end

  describe "associations" do
    it { is_expected.to have_many(:racks).dependent(:destroy) }
  end

  describe "factory" do
    it "creates a valid site" do
      site = build(:site)
      expect(site).to be_valid
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/site_spec.rb`
Expected: FAIL with "uninitialized constant Site"

**Step 3: Create the migration**

Run: `bin/rails generate migration CreateSites name:string:uniq description:text`

Edit the generated migration to match:

```ruby
# frozen_string_literal: true

class CreateSites < ActiveRecord::Migration[7.2]
  def change
    create_table :sites do |t|
      t.string :name, null: false, limit: 255
      t.text :description

      t.timestamps
    end

    add_index :sites, :name, unique: true
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Create the model**

Create `app/models/site.rb`:

```ruby
# frozen_string_literal: true

class Site < ApplicationRecord
  has_many :racks, dependent: :destroy

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
end
```

**Step 6: Create the factory**

Create `spec/factories/sites.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :site do
    sequence(:name) { |n| "Site #{n}" }
    description { "A test site" }
  end
end
```

**Step 7: Run test to verify it passes**

Run: `bin/rspec spec/models/site_spec.rb`
Expected: PASS (5 examples, 0 failures)

**Step 8: Commit**

```bash
git add -A && git commit -m "feat(sites): add Site model with validations and factory"
```

---

## Task 2: Rack Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_racks.rb`
- Create: `app/models/rack.rb`
- Create: `spec/models/rack_spec.rb`
- Create: `spec/factories/racks.rb`
- Modify: `app/models/site.rb` (already has has_many, verify)

**Step 1: Write the failing test**

Create `spec/models/rack_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rack, type: :model do
  describe "validations" do
    subject { build(:rack) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:site_id) }
    it { is_expected.to validate_uniqueness_of(:facility_id).scoped_to(:site_id).allow_nil }

    it { is_expected.to validate_numericality_of(:u_height).only_integer.is_greater_than(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:width_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:depth_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_weight_kg).only_integer.is_greater_than(0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:site) }
    it { is_expected.to have_many(:nodes) }
  end

  describe "enums" do
    it "defines status enum" do
      expect(Rack.statuses).to eq({ "active" => 0, "planned" => 1, "decommissioned" => 2 })
    end

    it "defaults to active status" do
      rack = Rack.new
      expect(rack.status).to eq("active")
    end
  end

  describe "defaults" do
    it "defaults u_height to 42" do
      rack = Rack.new
      expect(rack.u_height).to eq(42)
    end

    it "defaults desc_units to false" do
      rack = Rack.new
      expect(rack.desc_units).to be false
    end
  end

  describe "factory" do
    it "creates a valid rack" do
      rack = build(:rack)
      expect(rack).to be_valid
    end

    it "creates a valid rack with planned trait" do
      rack = build(:rack, :planned)
      expect(rack).to be_valid
      expect(rack).to be_planned
    end

    it "creates a valid rack with decommissioned trait" do
      rack = build(:rack, :decommissioned)
      expect(rack).to be_valid
      expect(rack).to be_decommissioned
    end
  end

  describe "#utilization" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site, u_height: 42) }

    context "with no nodes" do
      it "returns 0" do
        expect(rack.utilization).to eq(0)
      end
    end

    context "with nodes" do
      before do
        create(:node, rack: rack, rack_position: 1, rack_height: 2)
        create(:node, rack: rack, rack_position: 5, rack_height: 4)
      end

      it "returns total RUs used" do
        expect(rack.utilization).to eq(6)
      end
    end
  end

  describe "#utilization_percentage" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site, u_height: 10) }

    context "with no nodes" do
      it "returns 0.0" do
        expect(rack.utilization_percentage).to eq(0.0)
      end
    end

    context "with nodes using half the rack" do
      before do
        create(:node, rack: rack, rack_position: 1, rack_height: 5)
      end

      it "returns 50.0" do
        expect(rack.utilization_percentage).to eq(50.0)
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/rack_spec.rb`
Expected: FAIL with "uninitialized constant Rack"

**Step 3: Create the migration**

Run: `bin/rails generate migration CreateRacks`

Edit the generated migration:

```ruby
# frozen_string_literal: true

class CreateRacks < ActiveRecord::Migration[7.2]
  def change
    create_table :racks do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false, limit: 255
      t.string :facility_id, limit: 255
      t.string :asset_tag, limit: 255
      t.integer :u_height, null: false, default: 42
      t.integer :width_mm
      t.integer :depth_mm
      t.integer :max_weight_kg
      t.integer :status, null: false, default: 0
      t.boolean :desc_units, null: false, default: false

      t.timestamps
    end

    add_index :racks, [:site_id, :name], unique: true
    add_index :racks, [:site_id, :facility_id], unique: true, where: "facility_id IS NOT NULL"
    add_index :racks, :status
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Create the model**

Create `app/models/rack.rb`:

```ruby
# frozen_string_literal: true

class Rack < ApplicationRecord
  belongs_to :site
  has_many :nodes

  enum :status, { active: 0, planned: 1, decommissioned: 2 }, default: :active

  validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :site_id }
  validates :facility_id, uniqueness: { scope: :site_id }, allow_nil: true
  validates :u_height, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :width_mm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :depth_mm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_weight_kg, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def utilization
    nodes.sum(:rack_height)
  end

  def utilization_percentage
    return 0.0 if u_height.zero?

    (utilization.to_f / u_height * 100).round(1)
  end
end
```

**Step 6: Create the factory**

Create `spec/factories/racks.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :rack do
    site
    sequence(:name) { |n| "Rack #{n}" }
    u_height { 42 }
    status { :active }

    trait :planned do
      status { :planned }
    end

    trait :decommissioned do
      status { :decommissioned }
    end

    trait :with_facility_id do
      sequence(:facility_id) { |n| "FAC-#{n.to_s.rjust(4, '0')}" }
    end
  end
end
```

**Step 7: Run test to verify it passes**

Run: `bin/rspec spec/models/rack_spec.rb`
Expected: Most pass, utilization tests will fail (Node doesn't have rack fields yet)

**Step 8: Commit partial progress**

```bash
git add -A && git commit -m "feat(racks): add Rack model with validations and factory

Utilization methods will work after Node rack fields are added."
```

---

## Task 3: Add Rack Fields to Node

**Files:**
- Create: `db/migrate/TIMESTAMP_add_rack_fields_to_nodes.rb`
- Modify: `app/models/node.rb`
- Modify: `spec/models/node_spec.rb`
- Modify: `spec/factories/nodes.rb`

**Step 1: Write the failing test**

Add to `spec/models/node_spec.rb` (inside the main describe block):

```ruby
describe "rack associations and validations" do
  it { is_expected.to belong_to(:rack).optional }

  describe "rack_position validation" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site, u_height: 42) }

    context "when rack_id is present" do
      it "requires rack_position" do
        node = build(:node, rack: rack, rack_position: nil)
        expect(node).not_to be_valid
        expect(node.errors[:rack_position]).to include("can't be blank when rack is assigned")
      end
    end

    context "when rack_id is nil" do
      it "allows nil rack_position" do
        node = build(:node, rack: nil, rack_position: nil)
        expect(node).to be_valid
      end
    end

    context "position bounds" do
      it "rejects position less than 1" do
        node = build(:node, rack: rack, rack_position: 0, rack_height: 1)
        expect(node).not_to be_valid
        expect(node.errors[:rack_position]).to include("must be greater than or equal to 1")
      end

      it "rejects position exceeding rack height" do
        node = build(:node, rack: rack, rack_position: 43, rack_height: 1)
        expect(node).not_to be_valid
        expect(node.errors[:rack_position]).to include("must be less than or equal to 42")
      end

      it "rejects when node extends beyond rack height" do
        node = build(:node, rack: rack, rack_position: 41, rack_height: 3)
        expect(node).not_to be_valid
        expect(node.errors[:base]).to include("Node extends beyond rack height (position 41 + height 3 - 1 = 43, rack height is 42)")
      end

      it "accepts valid position" do
        node = build(:node, rack: rack, rack_position: 40, rack_height: 3)
        expect(node).to be_valid
      end
    end
  end

  describe "rack_height validation" do
    it { is_expected.to validate_numericality_of(:rack_height).only_integer.is_greater_than(0).allow_nil }

    it "defaults to 1" do
      node = Node.new
      expect(node.rack_height).to eq(1)
    end
  end

  describe "overlap validation" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site, u_height: 42) }
    let!(:existing_node) { create(:node, rack: rack, rack_position: 10, rack_height: 2) }

    it "rejects overlapping positions" do
      node = build(:node, rack: rack, rack_position: 11, rack_height: 1)
      expect(node).not_to be_valid
      expect(node.errors[:base]).to include(/overlaps with existing node/)
    end

    it "allows adjacent positions" do
      node = build(:node, rack: rack, rack_position: 12, rack_height: 1)
      expect(node).to be_valid
    end

    it "allows position below existing node" do
      node = build(:node, rack: rack, rack_position: 8, rack_height: 2)
      expect(node).to be_valid
    end

    it "ignores self when updating" do
      existing_node.rack_position = 10
      expect(existing_node).to be_valid
    end
  end
end

describe "scopes" do
  describe ".unracked" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site) }
    let!(:racked_node) { create(:node, rack: rack, rack_position: 1, rack_height: 1) }
    let!(:unracked_node) { create(:node, rack: nil) }

    it "returns only nodes without rack assignment" do
      expect(Node.unracked).to eq([unracked_node])
    end
  end

  describe ".racked" do
    let(:site) { create(:site) }
    let(:rack) { create(:rack, site: site) }
    let!(:racked_node) { create(:node, rack: rack, rack_position: 1, rack_height: 1) }
    let!(:unracked_node) { create(:node, rack: nil) }

    it "returns only nodes with rack assignment" do
      expect(Node.racked).to eq([racked_node])
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/models/node_spec.rb`
Expected: FAIL - unknown attribute 'rack_id'

**Step 3: Create the migration**

Run: `bin/rails generate migration AddRackFieldsToNodes`

Edit the generated migration:

```ruby
# frozen_string_literal: true

class AddRackFieldsToNodes < ActiveRecord::Migration[7.2]
  def change
    add_reference :nodes, :rack, foreign_key: true, null: true
    add_column :nodes, :rack_position, :integer
    add_column :nodes, :rack_height, :integer, default: 1

    add_index :nodes, [:rack_id, :rack_position]
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Update the Node model**

Add to `app/models/node.rb` after the existing associations:

```ruby
belongs_to :rack, optional: true
```

Add to validations section:

```ruby
validates :rack_height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
validate :rack_position_required_when_racked
validate :rack_position_within_bounds
validate :no_overlapping_nodes
```

Add scopes:

```ruby
scope :unracked, -> { where(rack_id: nil) }
scope :racked, -> { where.not(rack_id: nil) }
```

Add private methods:

```ruby
def rack_position_required_when_racked
  return unless rack_id.present? && rack_position.blank?

  errors.add(:rack_position, "can't be blank when rack is assigned")
end

def rack_position_within_bounds
  return unless rack.present? && rack_position.present?

  if rack_position < 1
    errors.add(:rack_position, "must be greater than or equal to 1")
  elsif rack_position > rack.u_height
    errors.add(:rack_position, "must be less than or equal to #{rack.u_height}")
  elsif (rack_position + (rack_height || 1) - 1) > rack.u_height
    errors.add(:base, "Node extends beyond rack height (position #{rack_position} + height #{rack_height} - 1 = #{rack_position + rack_height - 1}, rack height is #{rack.u_height})")
  end
end

def no_overlapping_nodes
  return unless rack.present? && rack_position.present?

  node_top = rack_position + (rack_height || 1) - 1
  overlapping = rack.nodes.where.not(id: id).find do |other|
    other_top = other.rack_position + (other.rack_height || 1) - 1
    ranges_overlap?(rack_position, node_top, other.rack_position, other_top)
  end

  if overlapping
    errors.add(:base, "Position overlaps with existing node #{overlapping.hostname}")
  end
end

def ranges_overlap?(a_start, a_end, b_start, b_end)
  a_start <= b_end && b_start <= a_end
end
```

**Step 6: Update the factory**

Add to `spec/factories/nodes.rb`:

```ruby
trait :racked do
  rack
  rack_position { 1 }
  rack_height { 1 }
end

trait :two_u do
  rack_height { 2 }
end

trait :four_u do
  rack_height { 4 }
end
```

**Step 7: Run tests to verify they pass**

Run: `bin/rspec spec/models/node_spec.rb spec/models/rack_spec.rb`
Expected: PASS

**Step 8: Commit**

```bash
git add -A && git commit -m "feat(nodes): add rack assignment fields with overlap validation"
```

---

## Task 4: Sites Controller and Views

**Files:**
- Create: `app/controllers/sites_controller.rb`
- Create: `spec/requests/sites_spec.rb`
- Create: `app/views/sites/index.html.erb`
- Create: `app/views/sites/show.html.erb`
- Create: `app/views/sites/new.html.erb`
- Create: `app/views/sites/edit.html.erb`
- Create: `app/views/sites/_form.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Write the failing test**

Create `spec/requests/sites_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sites", type: :request do
  let(:user) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }

  before { sign_in user }

  describe "GET /sites" do
    it "returns http success" do
      get sites_path
      expect(response).to have_http_status(:success)
    end

    it "displays sites" do
      site = create(:site, name: "Data Center A")
      get sites_path
      expect(response.body).to include("Data Center A")
    end
  end

  describe "GET /sites/:id" do
    let(:site) { create(:site) }

    it "returns http success" do
      get site_path(site)
      expect(response).to have_http_status(:success)
    end

    it "displays site details" do
      get site_path(site)
      expect(response.body).to include(site.name)
    end
  end

  describe "GET /sites/new" do
    it "returns http success for approvers" do
      get new_site_path
      expect(response).to have_http_status(:success)
    end

    it "redirects viewers" do
      sign_in viewer
      get new_site_path
      expect(response).to redirect_to(sites_path)
    end
  end

  describe "POST /sites" do
    context "with valid params" do
      it "creates a site" do
        expect {
          post sites_path, params: { site: { name: "New Site", description: "Test" } }
        }.to change(Site, :count).by(1)
      end

      it "redirects to sites index" do
        post sites_path, params: { site: { name: "New Site" } }
        expect(response).to redirect_to(sites_path)
      end
    end

    context "with invalid params" do
      it "does not create a site" do
        expect {
          post sites_path, params: { site: { name: "" } }
        }.not_to change(Site, :count)
      end

      it "renders new" do
        post sites_path, params: { site: { name: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /sites/:id/edit" do
    let(:site) { create(:site) }

    it "returns http success for approvers" do
      get edit_site_path(site)
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /sites/:id" do
    let(:site) { create(:site, name: "Old Name") }

    context "with valid params" do
      it "updates the site" do
        patch site_path(site), params: { site: { name: "New Name" } }
        expect(site.reload.name).to eq("New Name")
      end

      it "redirects to site" do
        patch site_path(site), params: { site: { name: "New Name" } }
        expect(response).to redirect_to(site_path(site))
      end
    end
  end

  describe "DELETE /sites/:id" do
    let!(:site) { create(:site) }

    it "destroys the site" do
      expect {
        delete site_path(site)
      }.to change(Site, :count).by(-1)
    end

    it "redirects to sites index" do
      delete site_path(site)
      expect(response).to redirect_to(sites_path)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/sites_spec.rb`
Expected: FAIL - No route matches

**Step 3: Add routes**

Edit `config/routes.rb`, add inside the main block:

```ruby
resources :sites
```

**Step 4: Create the controller**

Create `app/controllers/sites_controller.rb`:

```ruby
# frozen_string_literal: true

class SitesController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_site, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @sites = Site.includes(:racks).order(:name)
  end

  def show
    @racks = @site.racks.includes(:nodes).order(:name)
  end

  def new
    @site = Site.new
  end

  def create
    @site = Site.new(site_params)

    if @site.save
      redirect_to sites_path, notice: "Site was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @site.update(site_params)
      redirect_to site_path(@site), notice: "Site was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @site.destroy
    redirect_to sites_path, notice: "Site was successfully deleted."
  end

  private

  def set_site
    @site = Site.find(params[:id])
  end

  def site_params
    params.require(:site).permit(:name, :description)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to sites_path, alert: "You are not authorized to manage sites."
  end
end
```

**Step 5: Create views**

Create `app/views/sites/index.html.erb`:

```erb
<div class="space-y-6">
  <%# Header %>
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-slate-900">Sites</h1>
      <p class="text-sm text-slate-600">Manage physical locations for rack organization</p>
    </div>
    <% if current_user.approver? %>
      <%= link_to new_site_path, class: "inline-flex items-center gap-2 px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 transition-colors" do %>
        <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        Add Site
      <% end %>
    <% end %>
  </div>

  <%# Sites Table %>
  <div class="bg-white rounded-lg border border-slate-200 overflow-hidden">
    <table class="min-w-full divide-y divide-slate-200">
      <thead class="bg-slate-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Name</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Description</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Racks</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Nodes</th>
          <th class="px-6 py-3 text-right text-xs font-semibold text-slate-600 uppercase tracking-wider">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-200">
        <% @sites.each do |site| %>
          <tr class="hover:bg-slate-50">
            <td class="px-6 py-4">
              <%= link_to site.name, site_path(site), class: "text-teal-600 hover:text-teal-800 font-medium" %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-600">
              <%= truncate(site.description, length: 50) %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-900">
              <%= site.racks.count %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-900">
              <%= site.racks.sum { |r| r.nodes.count } %>
            </td>
            <td class="px-6 py-4 text-right">
              <% if current_user.approver? %>
                <%= link_to "Edit", edit_site_path(site), class: "text-sm text-slate-600 hover:text-slate-900 mr-3" %>
                <%= link_to "Delete", site_path(site), data: { turbo_method: :delete, turbo_confirm: "Are you sure you want to delete this site?" }, class: "text-sm text-red-600 hover:text-red-800" %>
              <% end %>
            </td>
          </tr>
        <% end %>
        <% if @sites.empty? %>
          <tr>
            <td colspan="5" class="px-6 py-12 text-center text-slate-500">
              No sites found. <% if current_user.approver? %><%= link_to "Create one", new_site_path, class: "text-teal-600 hover:text-teal-800" %>.<% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

Create `app/views/sites/show.html.erb`:

```erb
<div class="space-y-6">
  <%# Header %>
  <div class="flex items-center justify-between">
    <div>
      <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
        <%= link_to "Sites", sites_path, class: "hover:text-teal-600" %> /
      </div>
      <h1 class="text-2xl font-bold text-slate-900"><%= @site.name %></h1>
      <% if @site.description.present? %>
        <p class="text-sm text-slate-600 mt-1"><%= @site.description %></p>
      <% end %>
    </div>
    <% if current_user.approver? %>
      <div class="flex gap-2">
        <%= link_to edit_site_path(@site), class: "inline-flex items-center gap-2 px-4 py-2 bg-slate-100 text-slate-700 text-sm font-medium rounded-lg hover:bg-slate-200 transition-colors" do %>
          Edit
        <% end %>
      </div>
    <% end %>
  </div>

  <%# Racks in this site %>
  <div class="bg-white rounded-lg border border-slate-200 overflow-hidden">
    <div class="px-6 py-4 border-b border-slate-200 flex items-center justify-between">
      <h2 class="text-lg font-semibold text-slate-900">Racks</h2>
      <% if current_user.approver? %>
        <%= link_to new_rack_path(site_id: @site.id), class: "text-sm text-teal-600 hover:text-teal-800" do %>
          + Add Rack
        <% end %>
      <% end %>
    </div>
    <table class="min-w-full divide-y divide-slate-200">
      <thead class="bg-slate-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Name</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Height</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Utilization</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Status</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-200">
        <% @racks.each do |rack| %>
          <tr class="hover:bg-slate-50">
            <td class="px-6 py-4">
              <%= link_to rack.name, rack_path(rack), class: "text-teal-600 hover:text-teal-800 font-medium" %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-600">
              <%= rack.u_height %>U
            </td>
            <td class="px-6 py-4 text-sm text-slate-600">
              <%= rack.utilization %>/<%= rack.u_height %> RU (<%= rack.utilization_percentage %>%)
            </td>
            <td class="px-6 py-4">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium <%= rack.active? ? 'bg-green-100 text-green-800' : rack.planned? ? 'bg-yellow-100 text-yellow-800' : 'bg-slate-100 text-slate-800' %>">
                <%= rack.status.humanize %>
              </span>
            </td>
          </tr>
        <% end %>
        <% if @racks.empty? %>
          <tr>
            <td colspan="4" class="px-6 py-12 text-center text-slate-500">
              No racks in this site. <% if current_user.approver? %><%= link_to "Add one", new_rack_path(site_id: @site.id), class: "text-teal-600 hover:text-teal-800" %>.<% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

Create `app/views/sites/_form.html.erb`:

```erb
<%= form_with model: site, class: "space-y-6" do |f| %>
  <% if site.errors.any? %>
    <div class="bg-red-50 border border-red-200 rounded-lg p-4">
      <h3 class="text-sm font-medium text-red-800"><%= pluralize(site.errors.count, "error") %> prohibited this site from being saved:</h3>
      <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
        <% site.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= f.label :name, class: "block text-sm font-medium text-slate-700 mb-1" %>
    <%= f.text_field :name, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "e.g., Server Room A" %>
  </div>

  <div>
    <%= f.label :description, class: "block text-sm font-medium text-slate-700 mb-1" %>
    <%= f.text_area :description, rows: 3, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "Optional description" %>
  </div>

  <div class="flex gap-3">
    <%= f.submit site.persisted? ? "Update Site" : "Create Site", class: "px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 transition-colors cursor-pointer" %>
    <%= link_to "Cancel", site.persisted? ? site_path(site) : sites_path, class: "px-4 py-2 bg-slate-100 text-slate-700 text-sm font-medium rounded-lg hover:bg-slate-200 transition-colors" %>
  </div>
<% end %>
```

Create `app/views/sites/new.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
      <%= link_to "Sites", sites_path, class: "hover:text-teal-600" %> /
    </div>
    <h1 class="text-2xl font-bold text-slate-900">New Site</h1>
  </div>

  <div class="bg-white rounded-lg border border-slate-200 p-6">
    <%= render "form", site: @site %>
  </div>
</div>
```

Create `app/views/sites/edit.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
      <%= link_to "Sites", sites_path, class: "hover:text-teal-600" %> /
      <%= link_to @site.name, site_path(@site), class: "hover:text-teal-600" %> /
    </div>
    <h1 class="text-2xl font-bold text-slate-900">Edit Site</h1>
  </div>

  <div class="bg-white rounded-lg border border-slate-200 p-6">
    <%= render "form", site: @site %>
  </div>
</div>
```

**Step 6: Update sidebar**

Edit `app/views/shared/_sidebar.html.erb`, add Sites link after Dashboard in the Organization section:

```erb
<%= link_to sites_path,
    class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/sites') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
  <svg class="h-5 w-5 opacity-75" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
  </svg>
  Sites
<% end %>
```

**Step 7: Run tests to verify they pass**

Run: `bin/rspec spec/requests/sites_spec.rb`
Expected: PASS

**Step 8: Commit**

```bash
git add -A && git commit -m "feat(sites): add Sites controller with CRUD views"
```

---

## Task 5: Racks Controller and Views

**Files:**
- Create: `app/controllers/racks_controller.rb`
- Create: `spec/requests/racks_spec.rb`
- Create: `app/views/racks/index.html.erb`
- Create: `app/views/racks/show.html.erb`
- Create: `app/views/racks/new.html.erb`
- Create: `app/views/racks/edit.html.erb`
- Create: `app/views/racks/_form.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/shared/_sidebar.html.erb`

**Step 1: Write the failing test**

Create `spec/requests/racks_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Racks", type: :request do
  let(:user) { create(:user, :approver) }
  let(:viewer) { create(:user, :viewer) }
  let(:site) { create(:site) }

  before { sign_in user }

  describe "GET /racks" do
    it "returns http success" do
      get racks_path
      expect(response).to have_http_status(:success)
    end

    it "displays racks" do
      rack = create(:rack, site: site, name: "Rack A1")
      get racks_path
      expect(response.body).to include("Rack A1")
    end

    it "filters by site" do
      rack1 = create(:rack, site: site, name: "Rack A1")
      other_site = create(:site)
      rack2 = create(:rack, site: other_site, name: "Rack B1")

      get racks_path(site_id: site.id)
      expect(response.body).to include("Rack A1")
      expect(response.body).not_to include("Rack B1")
    end
  end

  describe "GET /racks/:id" do
    let(:rack) { create(:rack, site: site) }

    it "returns http success" do
      get rack_path(rack)
      expect(response).to have_http_status(:success)
    end

    it "displays rack details" do
      get rack_path(rack)
      expect(response.body).to include(rack.name)
    end
  end

  describe "GET /racks/new" do
    it "returns http success for approvers" do
      get new_rack_path
      expect(response).to have_http_status(:success)
    end

    it "redirects viewers" do
      sign_in viewer
      get new_rack_path
      expect(response).to redirect_to(racks_path)
    end

    it "preselects site from params" do
      get new_rack_path(site_id: site.id)
      expect(response.body).to include("selected")
    end
  end

  describe "POST /racks" do
    context "with valid params" do
      it "creates a rack" do
        expect {
          post racks_path, params: { rack: { site_id: site.id, name: "New Rack", u_height: 42 } }
        }.to change(Rack, :count).by(1)
      end

      it "redirects to rack" do
        post racks_path, params: { rack: { site_id: site.id, name: "New Rack", u_height: 42 } }
        expect(response).to redirect_to(rack_path(Rack.last))
      end
    end

    context "with invalid params" do
      it "does not create a rack" do
        expect {
          post racks_path, params: { rack: { site_id: site.id, name: "" } }
        }.not_to change(Rack, :count)
      end
    end
  end

  describe "PATCH /racks/:id" do
    let(:rack) { create(:rack, site: site, name: "Old Name") }

    it "updates the rack" do
      patch rack_path(rack), params: { rack: { name: "New Name" } }
      expect(rack.reload.name).to eq("New Name")
    end
  end

  describe "DELETE /racks/:id" do
    let!(:rack) { create(:rack, site: site) }

    it "destroys the rack" do
      expect {
        delete rack_path(rack)
      }.to change(Rack, :count).by(-1)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/requests/racks_spec.rb`
Expected: FAIL - No route matches

**Step 3: Add routes**

Edit `config/routes.rb`:

```ruby
resources :racks do
  member do
    patch :update_layout
  end
end
```

**Step 4: Create the controller**

Create `app/controllers/racks_controller.rb`:

```ruby
# frozen_string_literal: true

class RacksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_rack, only: %i[show edit update destroy update_layout]
  before_action :authorize_approver!, only: %i[new create edit update destroy update_layout]

  def index
    @racks = Rack.includes(:site, :nodes).order(:name)
    @racks = @racks.where(site_id: params[:site_id]) if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def show
    @nodes = @rack.nodes.order(:rack_position)
    @unracked_nodes = Node.unracked.order(:hostname).limit(20)
  end

  def new
    @rack = Rack.new(site_id: params[:site_id])
    @sites = Site.order(:name)
  end

  def create
    @rack = Rack.new(rack_params)

    if @rack.save
      redirect_to rack_path(@rack), notice: "Rack was successfully created."
    else
      @sites = Site.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sites = Site.order(:name)
  end

  def update
    if @rack.update(rack_params)
      redirect_to rack_path(@rack), notice: "Rack was successfully updated."
    else
      @sites = Site.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    site = @rack.site
    @rack.destroy
    redirect_to site_path(site), notice: "Rack was successfully deleted."
  end

  def update_layout
    service = Racks::UpdateLayoutService.new(@rack, layout_params[:positions])
    result = service.call

    if result.success?
      render json: { success: true }
    else
      render json: { success: false, errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_rack
    @rack = Rack.find(params[:id])
  end

  def rack_params
    params.require(:rack).permit(:site_id, :name, :facility_id, :asset_tag, :u_height, :width_mm, :depth_mm, :max_weight_kg, :status, :desc_units)
  end

  def layout_params
    params.permit(positions: [:node_id, :rack_position, :rack_height])
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to racks_path, alert: "You are not authorized to manage racks."
  end
end
```

**Step 5: Create views**

Create `app/views/racks/index.html.erb`:

```erb
<div class="space-y-6">
  <%# Header %>
  <div class="flex items-center justify-between">
    <div>
      <h1 class="text-2xl font-bold text-slate-900">Racks</h1>
      <p class="text-sm text-slate-600">Manage physical rack infrastructure</p>
    </div>
    <% if current_user.approver? %>
      <%= link_to new_rack_path, class: "inline-flex items-center gap-2 px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 transition-colors" do %>
        <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
        </svg>
        Add Rack
      <% end %>
    <% end %>
  </div>

  <%# Filter %>
  <div class="flex gap-4">
    <%= form_with url: racks_path, method: :get, class: "flex gap-2", data: { turbo_frame: "_top" } do |f| %>
      <%= f.select :site_id, options_from_collection_for_select(@sites, :id, :name, params[:site_id]), { include_blank: "All Sites" }, class: "px-3 py-2 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-teal-500" %>
      <%= f.submit "Filter", class: "px-4 py-2 bg-slate-100 text-slate-700 text-sm font-medium rounded-lg hover:bg-slate-200 cursor-pointer" %>
      <% if params[:site_id].present? %>
        <%= link_to "Clear", racks_path, class: "px-4 py-2 text-slate-600 text-sm hover:text-slate-900" %>
      <% end %>
    <% end %>
  </div>

  <%# Racks Table %>
  <div class="bg-white rounded-lg border border-slate-200 overflow-hidden">
    <table class="min-w-full divide-y divide-slate-200">
      <thead class="bg-slate-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Name</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Site</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Height</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Utilization</th>
          <th class="px-6 py-3 text-left text-xs font-semibold text-slate-600 uppercase tracking-wider">Status</th>
          <th class="px-6 py-3 text-right text-xs font-semibold text-slate-600 uppercase tracking-wider">Actions</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-200">
        <% @racks.each do |rack| %>
          <tr class="hover:bg-slate-50">
            <td class="px-6 py-4">
              <%= link_to rack.name, rack_path(rack), class: "text-teal-600 hover:text-teal-800 font-medium" %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-600">
              <%= link_to rack.site.name, site_path(rack.site), class: "hover:text-teal-600" %>
            </td>
            <td class="px-6 py-4 text-sm text-slate-900">
              <%= rack.u_height %>U
            </td>
            <td class="px-6 py-4">
              <div class="flex items-center gap-2">
                <div class="w-24 h-2 bg-slate-200 rounded-full overflow-hidden">
                  <div class="h-full bg-teal-500 rounded-full" style="width: <%= rack.utilization_percentage %>%"></div>
                </div>
                <span class="text-sm text-slate-600"><%= rack.utilization %>/<%= rack.u_height %></span>
              </div>
            </td>
            <td class="px-6 py-4">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium <%= rack.active? ? 'bg-green-100 text-green-800' : rack.planned? ? 'bg-yellow-100 text-yellow-800' : 'bg-slate-100 text-slate-800' %>">
                <%= rack.status.humanize %>
              </span>
            </td>
            <td class="px-6 py-4 text-right">
              <% if current_user.approver? %>
                <%= link_to "Edit", edit_rack_path(rack), class: "text-sm text-slate-600 hover:text-slate-900 mr-3" %>
                <%= link_to "Delete", rack_path(rack), data: { turbo_method: :delete, turbo_confirm: "Are you sure?" }, class: "text-sm text-red-600 hover:text-red-800" %>
              <% end %>
            </td>
          </tr>
        <% end %>
        <% if @racks.empty? %>
          <tr>
            <td colspan="6" class="px-6 py-12 text-center text-slate-500">
              No racks found. <% if current_user.approver? %><%= link_to "Create one", new_rack_path, class: "text-teal-600 hover:text-teal-800" %>.<% end %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
</div>
```

Create `app/views/racks/show.html.erb`:

```erb
<div class="space-y-6">
  <%# Header %>
  <div class="flex items-center justify-between">
    <div>
      <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
        <%= link_to "Racks", racks_path, class: "hover:text-teal-600" %> /
        <%= link_to @rack.site.name, site_path(@rack.site), class: "hover:text-teal-600" %> /
      </div>
      <div class="flex items-center gap-3">
        <h1 class="text-2xl font-bold text-slate-900"><%= @rack.name %></h1>
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium <%= @rack.active? ? 'bg-green-100 text-green-800' : @rack.planned? ? 'bg-yellow-100 text-yellow-800' : 'bg-slate-100 text-slate-800' %>">
          <%= @rack.status.humanize %>
        </span>
      </div>
      <p class="text-sm text-slate-600 mt-1">
        <%= @rack.utilization %>/<%= @rack.u_height %> RU used (<%= @rack.utilization_percentage %>%)
      </p>
    </div>
    <% if current_user.approver? %>
      <div class="flex gap-2">
        <%= link_to edit_rack_path(@rack), class: "inline-flex items-center gap-2 px-4 py-2 bg-slate-100 text-slate-700 text-sm font-medium rounded-lg hover:bg-slate-200 transition-colors" do %>
          Edit
        <% end %>
      </div>
    <% end %>
  </div>

  <%# Main content - Rack diagram will go here %>
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
    <%# Rack Diagram Placeholder %>
    <div class="lg:col-span-2 bg-white rounded-lg border border-slate-200 p-6">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-slate-900">Rack Elevation</h2>
        <% if current_user.approver? %>
          <button type="button" id="save-layout-btn" class="hidden px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 transition-colors">
            Save Layout
          </button>
        <% end %>
      </div>
      <div id="rack-diagram-container"
           data-controller="rack-diagram"
           data-rack-diagram-rack-id-value="<%= @rack.id %>"
           data-rack-diagram-rack-height-value="<%= @rack.u_height %>"
           data-rack-diagram-desc-units-value="<%= @rack.desc_units %>"
           data-rack-diagram-nodes-value="<%= @nodes.map { |n| { id: n.id, hostname: n.hostname, position: n.rack_position, height: n.rack_height, status: n.status } }.to_json %>"
           data-rack-diagram-readonly-value="<%= !current_user.approver? %>">
        <canvas data-rack-diagram-target="canvas" class="w-full"></canvas>
      </div>
    </div>

    <%# Details Panel %>
    <div class="bg-white rounded-lg border border-slate-200 p-6">
      <h2 class="text-lg font-semibold text-slate-900 mb-4">Details</h2>
      <div data-rack-diagram-target="details">
        <%# Default: rack details %>
        <dl class="space-y-3">
          <div>
            <dt class="text-sm text-slate-500">Site</dt>
            <dd class="text-sm font-medium text-slate-900"><%= link_to @rack.site.name, site_path(@rack.site), class: "text-teal-600 hover:text-teal-800" %></dd>
          </div>
          <div>
            <dt class="text-sm text-slate-500">Height</dt>
            <dd class="text-sm font-medium text-slate-900"><%= @rack.u_height %>U</dd>
          </div>
          <% if @rack.facility_id.present? %>
            <div>
              <dt class="text-sm text-slate-500">Facility ID</dt>
              <dd class="text-sm font-medium text-slate-900"><%= @rack.facility_id %></dd>
            </div>
          <% end %>
          <% if @rack.asset_tag.present? %>
            <div>
              <dt class="text-sm text-slate-500">Asset Tag</dt>
              <dd class="text-sm font-medium text-slate-900"><%= @rack.asset_tag %></dd>
            </div>
          <% end %>
          <div>
            <dt class="text-sm text-slate-500">Nodes</dt>
            <dd class="text-sm font-medium text-slate-900"><%= @nodes.count %></dd>
          </div>
        </dl>
      </div>

      <%# Unracked nodes %>
      <% if current_user.approver? && @unracked_nodes.any? %>
        <div class="mt-6 pt-6 border-t border-slate-200">
          <h3 class="text-sm font-semibold text-slate-900 mb-3">Unracked Nodes</h3>
          <div class="space-y-2 max-h-64 overflow-y-auto">
            <% @unracked_nodes.each do |node| %>
              <div class="p-2 bg-slate-50 rounded text-sm cursor-grab"
                   draggable="true"
                   data-node-id="<%= node.id %>"
                   data-hostname="<%= node.hostname %>">
                <%= node.hostname %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

Create `app/views/racks/_form.html.erb`:

```erb
<%= form_with model: rack, class: "space-y-6" do |f| %>
  <% if rack.errors.any? %>
    <div class="bg-red-50 border border-red-200 rounded-lg p-4">
      <h3 class="text-sm font-medium text-red-800"><%= pluralize(rack.errors.count, "error") %> prohibited this rack from being saved:</h3>
      <ul class="mt-2 text-sm text-red-700 list-disc list-inside">
        <% rack.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="grid grid-cols-2 gap-4">
    <div>
      <%= f.label :site_id, "Site", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.collection_select :site_id, @sites, :id, :name, { prompt: "Select a site" }, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500" %>
    </div>

    <div>
      <%= f.label :name, class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.text_field :name, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "e.g., Rack A1" %>
    </div>
  </div>

  <div class="grid grid-cols-3 gap-4">
    <div>
      <%= f.label :u_height, "Height (U)", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.number_field :u_height, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", min: 1, max: 100 %>
    </div>

    <div>
      <%= f.label :facility_id, class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.text_field :facility_id, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "Optional" %>
    </div>

    <div>
      <%= f.label :asset_tag, class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.text_field :asset_tag, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "Optional" %>
    </div>
  </div>

  <div class="grid grid-cols-3 gap-4">
    <div>
      <%= f.label :status, class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.select :status, Rack.statuses.keys.map { |s| [s.humanize, s] }, {}, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500" %>
    </div>

    <div>
      <%= f.label :width_mm, "Width (mm)", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.number_field :width_mm, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "Optional" %>
    </div>

    <div>
      <%= f.label :depth_mm, "Depth (mm)", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.number_field :depth_mm, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", placeholder: "Optional" %>
    </div>
  </div>

  <div class="flex items-center gap-2">
    <%= f.check_box :desc_units, class: "h-4 w-4 rounded border-slate-300 text-teal-600 focus:ring-teal-500" %>
    <%= f.label :desc_units, "Number units top-to-bottom (descending)", class: "text-sm text-slate-700" %>
  </div>

  <div class="flex gap-3">
    <%= f.submit rack.persisted? ? "Update Rack" : "Create Rack", class: "px-4 py-2 bg-teal-600 text-white text-sm font-medium rounded-lg hover:bg-teal-700 transition-colors cursor-pointer" %>
    <%= link_to "Cancel", rack.persisted? ? rack_path(rack) : racks_path, class: "px-4 py-2 bg-slate-100 text-slate-700 text-sm font-medium rounded-lg hover:bg-slate-200 transition-colors" %>
  </div>
<% end %>
```

Create `app/views/racks/new.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
      <%= link_to "Racks", racks_path, class: "hover:text-teal-600" %> /
    </div>
    <h1 class="text-2xl font-bold text-slate-900">New Rack</h1>
  </div>

  <div class="bg-white rounded-lg border border-slate-200 p-6">
    <%= render "form", rack: @rack %>
  </div>
</div>
```

Create `app/views/racks/edit.html.erb`:

```erb
<div class="max-w-2xl">
  <div class="mb-6">
    <div class="flex items-center gap-2 text-sm text-slate-500 mb-1">
      <%= link_to "Racks", racks_path, class: "hover:text-teal-600" %> /
      <%= link_to @rack.name, rack_path(@rack), class: "hover:text-teal-600" %> /
    </div>
    <h1 class="text-2xl font-bold text-slate-900">Edit Rack</h1>
  </div>

  <div class="bg-white rounded-lg border border-slate-200 p-6">
    <%= render "form", rack: @rack %>
  </div>
</div>
```

**Step 6: Update sidebar**

Add Racks link after Sites in sidebar:

```erb
<%= link_to racks_path,
    class: "flex items-center gap-3 px-3 py-2 text-sm font-bold rounded transition-colors #{request.path.start_with?('/racks') ? 'bg-slate-800 text-teal-400' : 'hover:bg-slate-800 hover:text-teal-400'}" do %>
  <svg class="h-5 w-5 opacity-75" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16" />
  </svg>
  Racks
<% end %>
```

**Step 7: Run tests (will partially fail - UpdateLayoutService doesn't exist yet)**

Run: `bin/rspec spec/requests/racks_spec.rb`
Expected: Most pass, update_layout might fail

**Step 8: Commit**

```bash
git add -A && git commit -m "feat(racks): add Racks controller with CRUD views"
```

---

## Task 6: Racks Layout Services

**Files:**
- Create: `app/services/racks/validate_layout_service.rb`
- Create: `app/services/racks/update_layout_service.rb`
- Create: `spec/services/racks/validate_layout_service_spec.rb`
- Create: `spec/services/racks/update_layout_service_spec.rb`

**Step 1: Write the failing test for ValidateLayoutService**

Create `spec/services/racks/validate_layout_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Racks::ValidateLayoutService do
  let(:site) { create(:site) }
  let(:rack) { create(:rack, site: site, u_height: 10) }

  describe "#call" do
    context "with valid positions" do
      let(:node1) { create(:node) }
      let(:node2) { create(:node) }
      let(:positions) do
        [
          { "node_id" => node1.id, "rack_position" => 1, "rack_height" => 2 },
          { "node_id" => node2.id, "rack_position" => 5, "rack_height" => 1 }
        ]
      end

      it "returns success" do
        result = described_class.new(rack, positions).call
        expect(result).to be_success
      end
    end

    context "with overlapping positions" do
      let(:node1) { create(:node) }
      let(:node2) { create(:node) }
      let(:positions) do
        [
          { "node_id" => node1.id, "rack_position" => 1, "rack_height" => 3 },
          { "node_id" => node2.id, "rack_position" => 2, "rack_height" => 1 }
        ]
      end

      it "returns failure" do
        result = described_class.new(rack, positions).call
        expect(result).not_to be_success
      end

      it "includes overlap error" do
        result = described_class.new(rack, positions).call
        expect(result.errors).to include(/overlaps/)
      end
    end

    context "with position out of bounds" do
      let(:node) { create(:node) }
      let(:positions) do
        [{ "node_id" => node.id, "rack_position" => 11, "rack_height" => 1 }]
      end

      it "returns failure" do
        result = described_class.new(rack, positions).call
        expect(result).not_to be_success
      end
    end

    context "with node extending beyond rack height" do
      let(:node) { create(:node) }
      let(:positions) do
        [{ "node_id" => node.id, "rack_position" => 9, "rack_height" => 3 }]
      end

      it "returns failure" do
        result = described_class.new(rack, positions).call
        expect(result).not_to be_success
      end
    end

    context "with null position (unracking)" do
      let(:node) { create(:node, rack: rack, rack_position: 1, rack_height: 1) }
      let(:positions) do
        [{ "node_id" => node.id, "rack_position" => nil }]
      end

      it "returns success" do
        result = described_class.new(rack, positions).call
        expect(result).to be_success
      end
    end

    context "with non-existent node" do
      let(:positions) do
        [{ "node_id" => 99999, "rack_position" => 1, "rack_height" => 1 }]
      end

      it "returns failure" do
        result = described_class.new(rack, positions).call
        expect(result).not_to be_success
      end
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rspec spec/services/racks/validate_layout_service_spec.rb`
Expected: FAIL - uninitialized constant

**Step 3: Create the service**

Create `app/services/racks/validate_layout_service.rb`:

```ruby
# frozen_string_literal: true

module Racks
  class ValidateLayoutService
    Result = Struct.new(:success?, :errors, keyword_init: true)

    def initialize(rack, positions)
      @rack = rack
      @positions = positions || []
      @errors = []
    end

    def call
      validate_positions
      Result.new(success?: @errors.empty?, errors: @errors)
    end

    private

    def validate_positions
      planned_placements = []

      @positions.each do |pos|
        node_id = pos["node_id"]
        rack_position = pos["rack_position"]
        rack_height = pos["rack_height"] || 1

        # Skip unracking operations
        next if rack_position.nil?

        # Validate node exists
        node = Node.find_by(id: node_id)
        unless node
          @errors << "Node #{node_id} not found"
          next
        end

        # Validate position bounds
        if rack_position < 1
          @errors << "#{node.hostname}: position must be at least 1"
          next
        end

        if rack_position > @rack.u_height
          @errors << "#{node.hostname}: position #{rack_position} exceeds rack height #{@rack.u_height}"
          next
        end

        node_top = rack_position + rack_height - 1
        if node_top > @rack.u_height
          @errors << "#{node.hostname}: extends beyond rack height (position #{rack_position} + height #{rack_height} = #{node_top + 1})"
          next
        end

        # Check for overlaps with other planned placements
        planned_placements.each do |other|
          if ranges_overlap?(rack_position, node_top, other[:position], other[:top])
            @errors << "#{node.hostname} overlaps with #{other[:hostname]}"
          end
        end

        planned_placements << {
          node_id: node_id,
          hostname: node.hostname,
          position: rack_position,
          top: node_top
        }
      end
    end

    def ranges_overlap?(a_start, a_end, b_start, b_end)
      a_start <= b_end && b_start <= a_end
    end
  end
end
```

**Step 4: Run test to verify it passes**

Run: `bin/rspec spec/services/racks/validate_layout_service_spec.rb`
Expected: PASS

**Step 5: Write the failing test for UpdateLayoutService**

Create `spec/services/racks/update_layout_service_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Racks::UpdateLayoutService do
  let(:site) { create(:site) }
  let(:rack) { create(:rack, site: site, u_height: 10) }

  describe "#call" do
    context "with valid positions" do
      let(:node1) { create(:node) }
      let(:node2) { create(:node) }
      let(:positions) do
        [
          { "node_id" => node1.id, "rack_position" => 1, "rack_height" => 2 },
          { "node_id" => node2.id, "rack_position" => 5, "rack_height" => 1 }
        ]
      end

      it "returns success" do
        result = described_class.new(rack, positions).call
        expect(result).to be_success
      end

      it "updates node positions" do
        described_class.new(rack, positions).call
        expect(node1.reload.rack_position).to eq(1)
        expect(node1.rack_height).to eq(2)
        expect(node1.rack_id).to eq(rack.id)
      end
    end

    context "with invalid positions" do
      let(:node) { create(:node) }
      let(:positions) do
        [{ "node_id" => node.id, "rack_position" => 20, "rack_height" => 1 }]
      end

      it "returns failure" do
        result = described_class.new(rack, positions).call
        expect(result).not_to be_success
      end

      it "does not update nodes" do
        original_position = node.rack_position
        described_class.new(rack, positions).call
        expect(node.reload.rack_position).to eq(original_position)
      end
    end

    context "unracking a node" do
      let(:node) { create(:node, rack: rack, rack_position: 1, rack_height: 1) }
      let(:positions) do
        [{ "node_id" => node.id, "rack_position" => nil }]
      end

      it "removes rack assignment" do
        described_class.new(rack, positions).call
        expect(node.reload.rack_id).to be_nil
        expect(node.rack_position).to be_nil
      end
    end
  end
end
```

**Step 6: Create the service**

Create `app/services/racks/update_layout_service.rb`:

```ruby
# frozen_string_literal: true

module Racks
  class UpdateLayoutService
    Result = Struct.new(:success?, :errors, keyword_init: true)

    def initialize(rack, positions)
      @rack = rack
      @positions = positions || []
    end

    def call
      validation = ValidateLayoutService.new(@rack, @positions).call
      return Result.new(success?: false, errors: validation.errors) unless validation.success?

      ActiveRecord::Base.transaction do
        @positions.each do |pos|
          node = Node.find(pos["node_id"])

          if pos["rack_position"].nil?
            # Unrack
            node.update!(rack_id: nil, rack_position: nil)
          else
            # Assign/move
            node.update!(
              rack_id: @rack.id,
              rack_position: pos["rack_position"],
              rack_height: pos["rack_height"] || node.rack_height || 1
            )
          end
        end
      end

      Result.new(success?: true, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, errors: [e.message])
    end
  end
end
```

**Step 7: Run tests to verify they pass**

Run: `bin/rspec spec/services/racks/`
Expected: PASS

**Step 8: Commit**

```bash
git add -A && git commit -m "feat(racks): add layout validation and update services"
```

---

## Task 7: Fabric.js Integration - Basic Setup

**Files:**
- Run: `yarn add fabric`
- Create: `app/javascript/controllers/rack_diagram_controller.js`
- Create: `app/javascript/lib/rack_diagram/index.js`

**Step 1: Install Fabric.js**

Run: `yarn add fabric`

**Step 2: Create the Stimulus controller**

Create `app/javascript/controllers/rack_diagram_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"
import { RackDiagram } from "../lib/rack_diagram"

export default class extends Controller {
  static targets = ["canvas", "details"]
  static values = {
    rackId: Number,
    rackHeight: Number,
    descUnits: Boolean,
    nodes: Array,
    readonly: Boolean
  }

  connect() {
    this.hasChanges = false
    this.diagram = new RackDiagram(this.canvasTarget, {
      rackHeight: this.rackHeightValue,
      descUnits: this.descUnitsValue,
      nodes: this.nodesValue,
      readonly: this.readonlyValue,
      onSelect: this.handleSelect.bind(this),
      onChange: this.handleChange.bind(this)
    })

    this.setupSaveButton()
    this.setupBeforeUnload()
  }

  disconnect() {
    if (this.diagram) {
      this.diagram.dispose()
    }
    window.removeEventListener("beforeunload", this.beforeUnloadHandler)
  }

  handleSelect(node) {
    if (node) {
      this.detailsTarget.innerHTML = this.nodeDetailsHTML(node)
    } else {
      this.detailsTarget.innerHTML = this.rackDetailsHTML()
    }
  }

  handleChange() {
    this.hasChanges = true
    this.showSaveButton()
  }

  setupSaveButton() {
    this.saveButton = document.getElementById("save-layout-btn")
    if (this.saveButton) {
      this.saveButton.addEventListener("click", this.saveLayout.bind(this))
    }
  }

  showSaveButton() {
    if (this.saveButton) {
      this.saveButton.classList.remove("hidden")
      this.saveButton.classList.add("animate-pulse")
    }
  }

  hideSaveButton() {
    if (this.saveButton) {
      this.saveButton.classList.add("hidden")
      this.saveButton.classList.remove("animate-pulse")
    }
  }

  setupBeforeUnload() {
    this.beforeUnloadHandler = (e) => {
      if (this.hasChanges) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.beforeUnloadHandler)
  }

  async saveLayout() {
    const positions = this.diagram.getPositions()
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(`/racks/${this.rackIdValue}/update_layout`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken
        },
        body: JSON.stringify({ positions })
      })

      const data = await response.json()

      if (data.success) {
        this.hasChanges = false
        this.hideSaveButton()
        this.showNotification("Layout saved successfully", "success")
      } else {
        this.showNotification(data.errors.join(", "), "error")
      }
    } catch (error) {
      this.showNotification("Failed to save layout", "error")
    }
  }

  showNotification(message, type) {
    // Simple notification - could be enhanced with a toast component
    const flash = document.getElementById("flash_messages")
    if (flash) {
      const alertClass = type === "success" ? "bg-green-50 text-green-800" : "bg-red-50 text-red-800"
      flash.innerHTML = `<div class="p-4 rounded-lg ${alertClass}">${message}</div>`
      setTimeout(() => { flash.innerHTML = "" }, 3000)
    }
  }

  nodeDetailsHTML(node) {
    return `
      <dl class="space-y-3">
        <div>
          <dt class="text-sm text-slate-500">Hostname</dt>
          <dd class="text-sm font-medium text-slate-900">
            <a href="/nodes/${node.id}" class="text-teal-600 hover:text-teal-800">${node.hostname}</a>
          </dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Position</dt>
          <dd class="text-sm font-medium text-slate-900">RU ${node.position}</dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Height</dt>
          <dd class="text-sm font-medium text-slate-900">${node.height}U</dd>
        </div>
        <div>
          <dt class="text-sm text-slate-500">Status</dt>
          <dd class="text-sm font-medium text-slate-900">${node.status}</dd>
        </div>
      </dl>
    `
  }

  rackDetailsHTML() {
    // Return default rack details - will be rendered server-side initially
    return this.detailsTarget.dataset.defaultContent || ""
  }
}
```

**Step 3: Create the RackDiagram library**

Create `app/javascript/lib/rack_diagram/index.js`:

```javascript
import * as fabric from "fabric"

export class RackDiagram {
  constructor(canvasElement, options) {
    this.options = {
      rackHeight: 42,
      descUnits: false,
      nodes: [],
      readonly: false,
      onSelect: () => {},
      onChange: () => {},
      ...options
    }

    this.nodeObjects = new Map()
    this.positions = new Map()
    this.selectedNode = null

    // Initialize positions from nodes
    this.options.nodes.forEach(node => {
      this.positions.set(node.id, {
        node_id: node.id,
        rack_position: node.position,
        rack_height: node.height
      })
    })

    this.initCanvas(canvasElement)
    this.render()
  }

  initCanvas(element) {
    const containerWidth = element.parentElement.clientWidth
    const ruHeight = 20
    const labelWidth = 40
    const rackWidth = containerWidth - labelWidth - 20
    const canvasHeight = this.options.rackHeight * ruHeight + 40

    this.ruHeight = ruHeight
    this.labelWidth = labelWidth
    this.rackWidth = rackWidth
    this.rackX = labelWidth + 10
    this.rackY = 20

    element.width = containerWidth
    element.height = canvasHeight

    this.canvas = new fabric.Canvas(element, {
      selection: false,
      backgroundColor: "#f8fafc"
    })

    this.canvas.on("mouse:down", this.handleMouseDown.bind(this))
  }

  render() {
    this.canvas.clear()
    this.drawRackFrame()
    this.drawRULabels()
    this.drawNodes()
    this.canvas.renderAll()
  }

  drawRackFrame() {
    const height = this.options.rackHeight * this.ruHeight

    // Rack outline
    const frame = new fabric.Rect({
      left: this.rackX,
      top: this.rackY,
      width: this.rackWidth,
      height: height,
      fill: "#e2e8f0",
      stroke: "#94a3b8",
      strokeWidth: 2,
      selectable: false,
      evented: false
    })
    this.canvas.add(frame)

    // RU grid lines
    for (let i = 1; i < this.options.rackHeight; i++) {
      const y = this.rackY + i * this.ruHeight
      const line = new fabric.Line(
        [this.rackX, y, this.rackX + this.rackWidth, y],
        {
          stroke: "#cbd5e1",
          strokeWidth: 1,
          selectable: false,
          evented: false
        }
      )
      this.canvas.add(line)
    }
  }

  drawRULabels() {
    for (let i = 1; i <= this.options.rackHeight; i++) {
      const ruNumber = this.options.descUnits ? i : this.options.rackHeight - i + 1
      const y = this.rackY + (i - 1) * this.ruHeight + this.ruHeight / 2

      const label = new fabric.Text(ruNumber.toString(), {
        left: this.labelWidth / 2,
        top: y,
        fontSize: 10,
        fontFamily: "system-ui",
        fill: "#64748b",
        originX: "center",
        originY: "center",
        selectable: false,
        evented: false
      })
      this.canvas.add(label)
    }
  }

  drawNodes() {
    this.nodeObjects.clear()

    this.options.nodes.forEach(node => {
      const pos = this.positions.get(node.id)
      if (!pos || !pos.rack_position) return

      const ruFromTop = this.options.descUnits
        ? pos.rack_position - 1
        : this.options.rackHeight - pos.rack_position - pos.rack_height + 1

      const y = this.rackY + ruFromTop * this.ruHeight
      const height = pos.rack_height * this.ruHeight

      const rect = new fabric.Rect({
        left: this.rackX + 4,
        top: y + 2,
        width: this.rackWidth - 8,
        height: height - 4,
        fill: "#14b8a6",
        stroke: "#0d9488",
        strokeWidth: 1,
        rx: 4,
        ry: 4,
        selectable: !this.options.readonly,
        hasControls: false,
        hasBorders: false,
        lockMovementX: true,
        lockScalingX: true,
        lockScalingY: true,
        lockRotation: true,
        data: { ...node, ...pos }
      })

      const text = new fabric.Text(node.hostname, {
        left: this.rackX + this.rackWidth / 2,
        top: y + height / 2,
        fontSize: 12,
        fontFamily: "system-ui",
        fontWeight: "bold",
        fill: "#ffffff",
        originX: "center",
        originY: "center",
        selectable: false,
        evented: false
      })

      const group = new fabric.Group([rect, text], {
        left: this.rackX + 4,
        top: y + 2,
        selectable: !this.options.readonly,
        hasControls: false,
        hasBorders: true,
        borderColor: "#0f766e",
        lockMovementX: true,
        lockScalingX: true,
        lockScalingY: true,
        lockRotation: true,
        data: { ...node, ...pos }
      })

      if (!this.options.readonly) {
        group.on("moving", this.handleNodeMove.bind(this, node.id))
        group.on("modified", this.handleNodeMoveEnd.bind(this, node.id))
      }

      this.canvas.add(group)
      this.nodeObjects.set(node.id, group)
    })
  }

  handleMouseDown(event) {
    const target = event.target

    if (target && target.data) {
      this.selectNode(target.data)
    } else {
      this.selectNode(null)
    }
  }

  selectNode(nodeData) {
    // Reset previous selection
    this.nodeObjects.forEach(obj => {
      obj.set({ borderColor: "#0f766e" })
    })

    if (nodeData) {
      const obj = this.nodeObjects.get(nodeData.id)
      if (obj) {
        obj.set({ borderColor: "#f59e0b" })
      }
      this.selectedNode = nodeData
    } else {
      this.selectedNode = null
    }

    this.canvas.renderAll()
    this.options.onSelect(this.selectedNode)
  }

  handleNodeMove(nodeId, event) {
    const obj = event.target
    const pos = this.positions.get(nodeId)
    const height = pos.rack_height

    // Constrain Y movement
    let y = obj.top
    y = Math.max(this.rackY + 2, y)
    y = Math.min(this.rackY + (this.options.rackHeight - height) * this.ruHeight + 2, y)

    // Snap to RU grid
    const ruFromTop = Math.round((y - this.rackY - 2) / this.ruHeight)
    y = this.rackY + ruFromTop * this.ruHeight + 2

    obj.set({ top: y, left: this.rackX + 4 })
  }

  handleNodeMoveEnd(nodeId, event) {
    const obj = event.target
    const pos = this.positions.get(nodeId)
    const height = pos.rack_height

    const ruFromTop = Math.round((obj.top - this.rackY - 2) / this.ruHeight)
    const newPosition = this.options.descUnits
      ? ruFromTop + 1
      : this.options.rackHeight - ruFromTop - height + 1

    // Check for overlaps
    if (this.wouldOverlap(nodeId, newPosition, height)) {
      // Revert to original position
      this.render()
      return
    }

    // Update position
    this.positions.set(nodeId, {
      node_id: nodeId,
      rack_position: newPosition,
      rack_height: height
    })

    // Update selected node data
    if (this.selectedNode && this.selectedNode.id === nodeId) {
      this.selectedNode.position = newPosition
      this.options.onSelect(this.selectedNode)
    }

    this.options.onChange()
    this.render()
  }

  wouldOverlap(nodeId, position, height) {
    const nodeTop = position + height - 1

    for (const [id, pos] of this.positions) {
      if (id === nodeId || !pos.rack_position) continue

      const otherTop = pos.rack_position + pos.rack_height - 1
      if (position <= otherTop && pos.rack_position <= nodeTop) {
        return true
      }
    }

    return false
  }

  getPositions() {
    return Array.from(this.positions.values())
  }

  dispose() {
    this.canvas.dispose()
  }
}
```

**Step 4: Register the controller**

The Stimulus controller should auto-register if using import maps or esbuild with the standard Rails setup.

**Step 5: Test manually**

Run: `bin/dev`
Navigate to a rack detail page and verify the canvas renders.

**Step 6: Commit**

```bash
git add -A && git commit -m "feat(racks): add Fabric.js interactive rack diagram"
```

---

## Task 8: Final Integration - Node Edit Form

**Files:**
- Modify: `app/views/nodes/_form.html.erb` (or equivalent)
- Modify: `app/controllers/nodes_controller.rb`

**Step 1: Update Node controller to permit rack fields**

Edit `app/controllers/nodes_controller.rb`, update `node_params`:

```ruby
def node_params
  params.require(:node).permit(:hostname, :ip, :arch, :ssh_port, :ssh_user, :ssh_key, :ssh_password, :sudo_credential, :ssh_connect_method, :jump_host, :jump_user, :jump_port, :agent_path, :benchmark_work_dir, :api_key_id, :rack_id, :rack_position, :rack_height)
end
```

**Step 2: Update Node form to include rack fields**

Add rack assignment fields to the node edit form (find and edit the appropriate view):

```erb
<%# Rack Assignment %>
<div class="border-t border-slate-200 pt-6 mt-6">
  <h3 class="text-lg font-medium text-slate-900 mb-4">Rack Assignment</h3>
  <div class="grid grid-cols-3 gap-4">
    <div>
      <%= f.label :rack_id, "Rack", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.collection_select :rack_id, Rack.includes(:site).order("sites.name, racks.name"), :id, ->(r) { "#{r.site.name} / #{r.name}" }, { include_blank: "Not assigned" }, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500" %>
    </div>
    <div>
      <%= f.label :rack_position, "Position (RU)", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.number_field :rack_position, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", min: 1 %>
    </div>
    <div>
      <%= f.label :rack_height, "Height (U)", class: "block text-sm font-medium text-slate-700 mb-1" %>
      <%= f.number_field :rack_height, class: "w-full px-3 py-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-teal-500 focus:border-teal-500", min: 1, value: f.object.rack_height || 1 %>
    </div>
  </div>
</div>
```

**Step 3: Run full test suite**

Run: `bin/rspec spec/models spec/services spec/requests`
Expected: All pass

**Step 4: Run linter**

Run: `bin/rubocop -a`
Fix any issues.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat(nodes): add rack assignment to node edit form"
```

---

## Task 9: Final Cleanup and Quality Gates

**Step 1: Run full Rails quality checks**

```bash
bin/rubocop -f github
bin/rspec spec/models spec/services spec/requests
```

Fix any issues.

**Step 2: Create final commit if needed**

```bash
git add -A && git commit -m "chore: fix linting issues"
```

**Step 3: Summary**

The rack management feature is complete with:
- Site and Rack models with validations
- Node rack assignment with overlap detection
- Sites and Racks controllers with CRUD
- Interactive Fabric.js rack diagram
- Layout save API with validation
- Sidebar navigation updated

---

## Execution Notes

- Each task should take 5-15 minutes
- Run tests after each step to catch issues early
- The Fabric.js integration (Task 7) may need debugging based on your specific JS build setup
- System specs are skipped due to pre-existing Capybara issues in the environment
