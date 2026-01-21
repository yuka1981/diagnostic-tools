# Room Hierarchy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Room as intermediate layer between Site and Rack (Site → Room → Rack → Node)

**Architecture:** Create Room model with physical/location attributes. Racks belong to Room (required), access Site via delegation. Migration auto-creates "Default Room" per site for existing racks.

**Tech Stack:** Rails 7.2, PostgreSQL, RSpec, FactoryBot, Hotwire/Stimulus, Tailwind CSS

**Working Directory:** `/home/reid/diagnostic-tools/.worktrees/room-hierarchy`

---

## Task 1: Create Room Model and Migration

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_room_hierarchy.rb`
- Create: `app/models/room.rb`
- Modify: `app/models/site.rb`
- Modify: `app/models/server_rack.rb`

### Step 1.1: Generate migration file

Run:
```bash
bin/rails generate migration AddRoomHierarchy
```

### Step 1.2: Write the migration

Edit the generated migration file (`db/migrate/*_add_room_hierarchy.rb`):

```ruby
# frozen_string_literal: true

class AddRoomHierarchy < ActiveRecord::Migration[7.2]
  def up
    # Drop orphaned rooms table
    drop_table :rooms if table_exists?(:rooms)

    # Create new rooms table with full schema
    create_table :rooms do |t|
      t.references :site, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.decimal :floor_area_sqm, precision: 10, scale: 2
      t.decimal :power_capacity_kw, precision: 10, scale: 2
      t.decimal :cooling_capacity_kw, precision: 10, scale: 2
      t.integer :max_rack_count
      t.integer :floor_number
      t.string :building_wing
      t.string :grid_coordinates
      t.timestamps
    end

    add_index :rooms, [:site_id, :name], unique: true

    # Add room_id to racks (nullable initially)
    add_reference :racks, :room, foreign_key: true

    # Data migration: create default room per site, reassign racks
    Site.find_each do |site|
      room = Room.create!(
        site: site,
        name: "Default Room",
        description: "Auto-created during migration"
      )
      ServerRack.where(site_id: site.id).update_all(room_id: room.id)
    end

    # Finalize: make room_id required, remove site_id
    change_column_null :racks, :room_id, false
    remove_index :racks, [:site_id, :name]
    remove_index :racks, [:site_id, :facility_id]
    remove_index :racks, :site_id
    remove_foreign_key :racks, :sites
    remove_column :racks, :site_id

    # Add new unique indexes scoped to room
    add_index :racks, [:room_id, :name], unique: true
    add_index :racks, [:room_id, :facility_id], unique: true, where: "facility_id IS NOT NULL"
  end

  def down
    # Add site_id back
    add_reference :racks, :site, foreign_key: true

    # Restore site_id from room's site
    ServerRack.includes(:room).find_each do |rack|
      rack.update_column(:site_id, rack.room.site_id)
    end

    # Make site_id required
    change_column_null :racks, :site_id, false

    # Remove room_id
    remove_index :racks, [:room_id, :name]
    remove_index :racks, [:room_id, :facility_id]
    remove_foreign_key :racks, :rooms
    remove_column :racks, :room_id

    # Restore original indexes
    add_index :racks, [:site_id, :name], unique: true
    add_index :racks, [:site_id, :facility_id], unique: true, where: "facility_id IS NOT NULL"
    add_index :racks, :site_id

    # Delete auto-created rooms and drop table
    Room.where(name: "Default Room", description: "Auto-created during migration").destroy_all
    drop_table :rooms
  end
end
```

### Step 1.3: Create Room model

Create `app/models/room.rb`:

```ruby
# frozen_string_literal: true

class Room < ApplicationRecord
  belongs_to :site
  has_many :server_racks, dependent: :restrict_with_error
  has_many :nodes, through: :server_racks

  validates :name, presence: true, uniqueness: { scope: :site_id }
  validates :floor_area_sqm, numericality: { greater_than: 0 }, allow_nil: true
  validates :power_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
  validates :cooling_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
  validates :max_rack_count, numericality: { greater_than: 0, only_integer: true }, allow_nil: true

  def rack_count
    server_racks.size
  end

  def total_u_capacity
    server_racks.sum(:u_height)
  end

  def total_u_used
    server_racks.joins(:nodes).sum("nodes.rack_height")
  end

  def utilization_percentage
    return 0.0 if total_u_capacity.zero?

    (total_u_used.to_f / total_u_capacity * 100).round(1)
  end

  def at_capacity?
    max_rack_count.present? && rack_count >= max_rack_count
  end
end
```

### Step 1.4: Update Site model

Edit `app/models/site.rb`:

```ruby
# frozen_string_literal: true

class Site < ApplicationRecord
  has_many :rooms, dependent: :destroy
  has_many :server_racks, through: :rooms

  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
end
```

### Step 1.5: Update ServerRack model

Edit `app/models/server_rack.rb`, change `belongs_to :site` to `belongs_to :room` and add delegation:

```ruby
# frozen_string_literal: true

class ServerRack < ApplicationRecord
  self.table_name = "racks"
  belongs_to :room
  has_many :nodes, foreign_key: :rack_id

  delegate :site, to: :room

  enum :status, { active: 0, planned: 1, decommissioned: 2 }, default: :active

  validates :name, presence: true, length: { maximum: 255 }, uniqueness: { scope: :room_id }
  validates :facility_id, uniqueness: { scope: :room_id }, allow_nil: true
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

### Step 1.6: Run migration

Run:
```bash
bin/rails db:migrate
```

Expected: Migration succeeds, schema updated.

### Step 1.7: Verify schema

Run:
```bash
grep -A 15 "create_table \"rooms\"" db/schema.rb
```

Expected: New rooms table with all columns including `site_id`.

### Step 1.8: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(rooms): add Room model with site hierarchy

- Create rooms table with physical/location attributes
- Migrate racks from site_id to room_id
- Auto-create "Default Room" per site for existing racks
- Add Room model with validations and utilization methods
- Update Site to has_many :rooms
- Update ServerRack to belongs_to :room with site delegation

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create Room Factory and Model Specs

**Files:**
- Create: `spec/factories/rooms.rb`
- Modify: `spec/factories/racks.rb`
- Create: `spec/models/room_spec.rb`
- Modify: `spec/models/server_rack_spec.rb`

### Step 2.1: Create Room factory

Create `spec/factories/rooms.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    site
    sequence(:name) { |n| "Room #{n}" }
    description { "Test room" }

    trait :with_physical_specs do
      floor_area_sqm { 100.0 }
      power_capacity_kw { 50.0 }
      cooling_capacity_kw { 40.0 }
      max_rack_count { 10 }
    end

    trait :with_location do
      floor_number { 1 }
      building_wing { "East" }
      grid_coordinates { "A1" }
    end

    trait :full do
      with_physical_specs
      with_location
    end
  end
end
```

### Step 2.2: Update ServerRack factory

Edit `spec/factories/racks.rb` to use `room` instead of `site`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :server_rack do
    room
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

### Step 2.3: Create Room model spec

Create `spec/models/room_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Room, type: :model do
  describe "validations" do
    subject { build(:room) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:site_id) }
    it { is_expected.to validate_numericality_of(:floor_area_sqm).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:power_capacity_kw).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:cooling_capacity_kw).is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_rack_count).only_integer.is_greater_than(0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:site) }
    it { is_expected.to have_many(:server_racks).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:nodes).through(:server_racks) }
  end

  describe "factory" do
    it "creates a valid room" do
      room = build(:room)
      expect(room).to be_valid
    end

    it "creates a valid room with physical specs" do
      room = build(:room, :with_physical_specs)
      expect(room).to be_valid
      expect(room.floor_area_sqm).to eq(100.0)
    end

    it "creates a valid room with location" do
      room = build(:room, :with_location)
      expect(room).to be_valid
      expect(room.floor_number).to eq(1)
    end
  end

  describe "#rack_count" do
    let(:room) { create(:room) }

    it "returns 0 with no racks" do
      expect(room.rack_count).to eq(0)
    end

    it "returns count of racks" do
      create_list(:server_rack, 3, room: room)
      expect(room.rack_count).to eq(3)
    end
  end

  describe "#total_u_capacity" do
    let(:room) { create(:room) }

    it "returns 0 with no racks" do
      expect(room.total_u_capacity).to eq(0)
    end

    it "returns sum of rack u_heights" do
      create(:server_rack, room: room, u_height: 42)
      create(:server_rack, room: room, u_height: 48)
      expect(room.total_u_capacity).to eq(90)
    end
  end

  describe "#at_capacity?" do
    let(:room) { create(:room, max_rack_count: 2) }

    it "returns false when under capacity" do
      create(:server_rack, room: room)
      expect(room.at_capacity?).to be false
    end

    it "returns true when at capacity" do
      create_list(:server_rack, 2, room: room)
      expect(room.at_capacity?).to be true
    end

    it "returns false when max_rack_count is nil" do
      room_no_limit = create(:room, max_rack_count: nil)
      create_list(:server_rack, 10, room: room_no_limit)
      expect(room_no_limit.at_capacity?).to be false
    end
  end

  describe "dependent restrict" do
    let(:room) { create(:room) }

    it "prevents deletion when room has racks" do
      create(:server_rack, room: room)
      expect { room.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end

    it "allows deletion when room has no racks" do
      expect { room.destroy }.to change(Room, :count).by(-1)
    end
  end
end
```

### Step 2.4: Update ServerRack model spec

Edit `spec/models/server_rack_spec.rb` to update association tests:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServerRack, type: :model do
  describe "validations" do
    subject { build(:server_rack) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:room_id) }
    it { is_expected.to validate_uniqueness_of(:facility_id).scoped_to(:room_id).allow_nil }

    it { is_expected.to validate_numericality_of(:u_height).only_integer.is_greater_than(0).is_less_than_or_equal_to(100) }
    it { is_expected.to validate_numericality_of(:width_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:depth_mm).only_integer.is_greater_than(0).allow_nil }
    it { is_expected.to validate_numericality_of(:max_weight_kg).only_integer.is_greater_than(0).allow_nil }
  end

  describe "associations" do
    it { is_expected.to belong_to(:room) }
    it { is_expected.to have_many(:nodes) }
  end

  describe "delegation" do
    let(:site) { create(:site) }
    let(:room) { create(:room, site: site) }
    let(:server_rack) { create(:server_rack, room: room) }

    it "delegates site to room" do
      expect(server_rack.site).to eq(site)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(ServerRack.statuses).to eq({ "active" => 0, "planned" => 1, "decommissioned" => 2 })
    end

    it "defaults to active status" do
      server_rack = ServerRack.new
      expect(server_rack.status).to eq("active")
    end
  end

  describe "defaults" do
    it "defaults u_height to 42" do
      server_rack = ServerRack.new
      expect(server_rack.u_height).to eq(42)
    end

    it "defaults desc_units to false" do
      server_rack = ServerRack.new
      expect(server_rack.desc_units).to be false
    end
  end

  describe "factory" do
    it "creates a valid server_rack" do
      server_rack = build(:server_rack)
      expect(server_rack).to be_valid
    end

    it "creates a valid server_rack with planned trait" do
      server_rack = build(:server_rack, :planned)
      expect(server_rack).to be_valid
      expect(server_rack).to be_planned
    end

    it "creates a valid server_rack with decommissioned trait" do
      server_rack = build(:server_rack, :decommissioned)
      expect(server_rack).to be_valid
      expect(server_rack).to be_decommissioned
    end
  end

  describe "#utilization" do
    let(:server_rack) { create(:server_rack, u_height: 42) }

    context "with no nodes" do
      it "returns 0" do
        expect(server_rack.utilization).to eq(0)
      end
    end

    context "with nodes" do
      it "returns sum of node rack heights" do
        create(:node, server_rack: server_rack, rack_position: 1, rack_height: 2)
        create(:node, server_rack: server_rack, rack_position: 5, rack_height: 4)
        expect(server_rack.utilization).to eq(6)
      end
    end
  end

  describe "#utilization_percentage" do
    let(:server_rack) { create(:server_rack, u_height: 10) }

    context "with no nodes" do
      it "returns 0.0" do
        expect(server_rack.utilization_percentage).to eq(0.0)
      end
    end

    context "with nodes" do
      it "returns correct percentage" do
        create(:node, server_rack: server_rack, rack_position: 1, rack_height: 3)
        expect(server_rack.utilization_percentage).to eq(30.0)
      end
    end
  end
end
```

### Step 2.5: Run model specs

Run:
```bash
bin/rspec spec/models/room_spec.rb spec/models/server_rack_spec.rb
```

Expected: All tests pass.

### Step 2.6: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
test(rooms): add Room factory and model specs

- Create room factory with physical_specs and location traits
- Update server_rack factory to use room instead of site
- Add comprehensive Room model specs
- Update ServerRack model specs for room association

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create RoomsController

**Files:**
- Create: `app/controllers/rooms_controller.rb`
- Modify: `config/routes.rb`

### Step 3.1: Create RoomsController

Create `app/controllers/rooms_controller.rb`:

```ruby
# frozen_string_literal: true

class RoomsController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_room, only: %i[show edit update destroy]
  before_action :authorize_approver!, only: %i[new create edit update destroy]

  def index
    @rooms = Room.includes(:site, :server_racks).order(:name)
    @rooms = @rooms.where(site_id: params[:site_id]) if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def show
    @server_racks = @room.server_racks.includes(:nodes).order(:name)
  end

  def new
    @room = Room.new
    @room.site_id = params[:site_id] if params[:site_id].present?
    @sites = Site.order(:name)
  end

  def create
    @room = Room.new(room_params)

    if @room.save
      redirect_to room_path(@room), notice: "Room was successfully created."
    else
      @sites = Site.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @sites = Site.order(:name)
  end

  def update
    if @room.update(room_params)
      redirect_to room_path(@room), notice: "Room was successfully updated."
    else
      @sites = Site.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @room.server_racks.any?
      redirect_to room_path(@room), alert: "Cannot delete room with racks. Remove all racks first."
    else
      @room.destroy
      redirect_to rooms_path, notice: "Room was successfully deleted."
    end
  end

  # API endpoint for cascading select
  def for_site
    @rooms = Room.where(site_id: params[:site_id]).order(:name)
    render json: @rooms.map { |r| { id: r.id, name: r.name } }
  end

  private

  def set_room
    @room = Room.includes(:site, server_racks: :nodes).find(params[:id])
  end

  def room_params
    params.require(:room).permit(
      :site_id, :name, :description,
      :floor_area_sqm, :power_capacity_kw, :cooling_capacity_kw, :max_rack_count,
      :floor_number, :building_wing, :grid_coordinates
    )
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to rooms_path, alert: "You are not authorized to manage rooms."
  end
end
```

### Step 3.2: Update routes

Edit `config/routes.rb`, add rooms routes after sites:

```ruby
  resources :sites
  resources :rooms do
    collection do
      get :for_site
    end
  end
  resources :server_racks, path: "racks" do
    member do
      patch :update_layout
    end
  end
```

### Step 3.3: Verify routes

Run:
```bash
bin/rails routes | grep room
```

Expected: Routes for rooms index, show, new, create, edit, update, destroy, and for_site.

### Step 3.4: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(rooms): add RoomsController with CRUD actions

- Create RoomsController with full CRUD
- Add for_site endpoint for cascading select
- Add routes for rooms resource
- Approver authorization for write actions

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create Room Views

**Files:**
- Create: `app/views/rooms/index.html.erb`
- Create: `app/views/rooms/show.html.erb`
- Create: `app/views/rooms/new.html.erb`
- Create: `app/views/rooms/edit.html.erb`
- Create: `app/views/rooms/_form.html.erb`

### Step 4.1: Create rooms index view

Create `app/views/rooms/index.html.erb`:

```erb
<% content_for(:page_title) { "Rooms" } %>

<div class="flex items-center justify-between mb-6">
  <div>
    <h1 class="text-2xl font-bold text-slate-900">Rooms</h1>
    <p class="text-sm text-slate-500 mt-1">Manage data center rooms across your sites</p>
  </div>
  <% if current_user.approver? %>
    <%= link_to new_room_path, class: "btn-primary" do %>
      <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
      </svg>
      Add Room
    <% end %>
  <% end %>
</div>

<%# Site Filter %>
<div class="mb-4">
  <%= form_with url: rooms_path, method: :get, data: { turbo_frame: "_top" }, class: "flex items-center gap-4" do |f| %>
    <div class="flex items-center gap-2">
      <%= f.label :site_id, "Filter by Site:", class: "text-sm font-medium text-slate-700" %>
      <%= f.select :site_id,
          options_from_collection_for_select(@sites, :id, :name, params[:site_id]),
          { include_blank: "All Sites" },
          class: "rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
          onchange: "this.form.submit()" %>
    </div>
    <% if params[:site_id].present? %>
      <%= link_to "Clear Filter", rooms_path, class: "text-sm text-teal-600 hover:text-teal-700" %>
    <% end %>
  <% end %>
</div>

<div class="card-netbox">
  <% if @rooms.any? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Name</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Site</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Floor</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Wing</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Racks</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Utilization</th>
            <th scope="col" class="relative px-3 py-2 border-b">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-200 bg-white">
          <% @rooms.each do |room| %>
            <tr class="hover:bg-slate-50 transition-colors">
              <td class="whitespace-nowrap px-3 py-2">
                <%= link_to room_path(room), class: "group" do %>
                  <p class="text-sm font-bold text-slate-900 group-hover:text-teal-600"><%= room.name %></p>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-600">
                <%= link_to room.site.name, site_path(room.site), class: "hover:text-teal-600" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= room.floor_number.presence || "—" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= room.building_wing.presence || "—" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= room.rack_count %><%= " / #{room.max_rack_count}" if room.max_rack_count %>
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                <div class="flex items-center gap-2">
                  <div class="w-24 h-2 bg-slate-200 rounded-full overflow-hidden">
                    <div class="h-full bg-teal-500 rounded-full" style="width: <%= room.utilization_percentage %>%"></div>
                  </div>
                  <span class="text-xs text-slate-500"><%= room.utilization_percentage %>%</span>
                </div>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-right text-sm">
                <%= link_to "View", room_path(room), class: "text-teal-600 hover:text-teal-700 font-medium" %>
                <% if current_user.approver? %>
                  <span class="text-slate-300 mx-1">|</span>
                  <%= link_to "Edit", edit_room_path(room), class: "text-slate-600 hover:text-slate-700 font-medium" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-900">No rooms yet</p>
      <p class="mt-1 text-xs text-slate-500">Create a room to organize your rack infrastructure</p>
      <% if current_user.approver? %>
        <%= link_to new_room_path, class: "mt-4 btn-primary" do %>
          Add Room
        <% end %>
      <% end %>
    </div>
  <% end %>
</div>
```

### Step 4.2: Create rooms show view

Create `app/views/rooms/show.html.erb`:

```erb
<% content_for(:page_title) { @room.name } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Sites", sites_path, class: "hover:text-teal-600" %> /
    <%= link_to @room.site.name, site_path(@room.site), class: "hover:text-teal-600" %> /
    <span class="text-slate-700"><%= @room.name %></span>
  </nav>
  <div class="flex items-center justify-between">
    <div class="flex items-center gap-4">
      <h1 class="text-2xl font-bold text-slate-900"><%= @room.name %></h1>
      <% if @room.at_capacity? %>
        <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-amber-100 text-amber-800 border border-amber-200">
          At Capacity
        </span>
      <% end %>
    </div>
    <% if current_user.approver? %>
      <div class="flex items-center gap-2">
        <%= link_to new_server_rack_path(room_id: @room.id), class: "btn-secondary" do %>
          <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          Add Rack
        <% end %>
        <%= link_to edit_room_path(@room), class: "btn-secondary" do %>
          <svg class="h-4 w-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
          </svg>
          Edit
        <% end %>
      </div>
    <% end %>
  </div>
</div>

<div class="grid gap-6 lg:grid-cols-2">
  <%# Overview Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Overview</h3>
    </div>
    <div class="p-0">
      <table class="w-full text-sm text-left">
        <tbody class="divide-y divide-slate-100">
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 w-1/3 border-r border-slate-200">Name</th>
            <td class="px-4 py-2 text-slate-700 font-bold"><%= @room.name %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Site</th>
            <td class="px-4 py-2 text-slate-700">
              <%= link_to @room.site.name, site_path(@room.site), class: "text-teal-600 hover:text-teal-700" %>
            </td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Description</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.description.presence || "—" %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Floor</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.floor_number.presence || "—" %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Building Wing</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.building_wing.presence || "—" %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Grid Coordinates</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.grid_coordinates.presence || "—" %></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>

  <%# Capacity Card %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Capacity</h3>
    </div>
    <div class="p-0">
      <table class="w-full text-sm text-left">
        <tbody class="divide-y divide-slate-100">
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 w-1/3 border-r border-slate-200">Racks</th>
            <td class="px-4 py-2 text-slate-700">
              <%= @room.rack_count %><%= " / #{@room.max_rack_count}" if @room.max_rack_count %>
            </td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Total U Capacity</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.total_u_capacity %>U</td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Total U Used</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.total_u_used %>U</td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Utilization</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.utilization_percentage %>%</td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Floor Area</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.floor_area_sqm ? "#{@room.floor_area_sqm} m²" : "—" %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Power Capacity</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.power_capacity_kw ? "#{@room.power_capacity_kw} kW" : "—" %></td>
          </tr>
          <tr class="hover:bg-slate-50">
            <th class="px-4 py-2 font-bold text-slate-700 border-r border-slate-200">Cooling Capacity</th>
            <td class="px-4 py-2 text-slate-700"><%= @room.cooling_capacity_kw ? "#{@room.cooling_capacity_kw} kW" : "—" %></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</div>

<%# Racks List %>
<div class="card-netbox mt-6">
  <div class="card-header flex items-center justify-between">
    <h3 class="card-title">Racks</h3>
  </div>
  <% if @server_racks.any? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Name</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Facility ID</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Status</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Height</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Utilization</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Nodes</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-200 bg-white">
          <% @server_racks.each do |rack| %>
            <tr class="hover:bg-slate-50 transition-colors">
              <td class="whitespace-nowrap px-3 py-2">
                <%= link_to server_rack_path(rack), class: "group" do %>
                  <p class="text-sm font-bold text-slate-900 group-hover:text-teal-600"><%= rack.name %></p>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-600 font-mono">
                <%= rack.facility_id.presence || "—" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                <% case rack.status %>
                <% when "active" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-emerald-100 text-emerald-800 border border-emerald-200">
                    Active
                  </span>
                <% when "planned" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-800 border border-blue-200">
                    Planned
                  </span>
                <% when "decommissioned" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-slate-100 text-slate-600 border border-slate-200">
                    Decommissioned
                  </span>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= rack.u_height %>U
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                <div class="flex items-center gap-2">
                  <div class="w-24 h-2 bg-slate-200 rounded-full overflow-hidden">
                    <div class="h-full bg-teal-500 rounded-full" style="width: <%= rack.utilization_percentage %>%"></div>
                  </div>
                  <span class="text-xs text-slate-500"><%= rack.utilization_percentage %>%</span>
                </div>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= rack.nodes.count %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-900">No racks in this room</p>
      <p class="mt-1 text-xs text-slate-500">Add racks to organize your servers</p>
      <% if current_user.approver? %>
        <%= link_to new_server_rack_path(room_id: @room.id), class: "mt-4 btn-primary" do %>
          Add Rack
        <% end %>
      <% end %>
    </div>
  <% end %>
</div>

<%# Danger Zone %>
<% if current_user.approver? && @room.server_racks.empty? %>
  <div class="card-netbox mt-6 border-red-200">
    <div class="card-header bg-red-50 border-red-200">
      <h3 class="card-title text-red-800">Danger Zone</h3>
    </div>
    <div class="p-4">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm font-medium text-slate-900">Delete this room</p>
          <p class="text-xs text-slate-500">Once deleted, this room cannot be recovered.</p>
        </div>
        <%= button_to room_path(@room),
            method: :delete,
            class: "btn-danger",
            data: { turbo_confirm: "Are you sure you want to delete this room? This action cannot be undone." } do %>
          Delete Room
        <% end %>
      </div>
    </div>
  </div>
<% end %>
```

### Step 4.3: Create room form partial

Create `app/views/rooms/_form.html.erb`:

```erb
<%= form_with(model: @room, class: "space-y-6") do |f| %>
  <% if @room.errors.any? %>
    <div class="rounded-lg bg-red-50 p-4 text-sm text-red-700 border border-red-200">
      <h2 class="font-bold mb-2"><%= pluralize(@room.errors.count, "error") %> prohibited this room from being saved:</h2>
      <ul class="list-disc list-inside">
        <% @room.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%# Basic Information %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Room Information</h3>
    </div>
    <div class="p-4 grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <%= f.label :site_id, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.collection_select :site_id, @sites, :id, :name,
            { prompt: "Select a site" },
            { required: true, class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" } %>
        <p class="mt-1 text-xs text-slate-500">Site where this room is located.</p>
      </div>

      <div>
        <%= f.label :name, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :name, required: true,
            placeholder: "Server Room A",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Display name for this room.</p>
      </div>

      <div class="md:col-span-2">
        <%= f.label :description, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_area :description, rows: 2,
            placeholder: "Primary compute server room...",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Optional description of this room.</p>
      </div>
    </div>
  </div>

  <%# Location Information %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Location</h3>
    </div>
    <div class="p-4 grid grid-cols-1 md:grid-cols-3 gap-6">
      <div>
        <%= f.label :floor_number, "Floor", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :floor_number,
            placeholder: "1",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Floor number within the building.</p>
      </div>

      <div>
        <%= f.label :building_wing, "Building Wing", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :building_wing,
            placeholder: "East Wing",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Section of the building.</p>
      </div>

      <div>
        <%= f.label :grid_coordinates, "Grid Coordinates", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :grid_coordinates,
            placeholder: "A1-B2",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Location reference within the site.</p>
      </div>
    </div>
  </div>

  <%# Physical Specifications %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Physical Specifications</h3>
    </div>
    <div class="p-4 grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <%= f.label :floor_area_sqm, "Floor Area (m²)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :floor_area_sqm, step: 0.01, min: 0,
            placeholder: "100.00",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Total floor area in square meters.</p>
      </div>

      <div>
        <%= f.label :max_rack_count, "Maximum Rack Count", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :max_rack_count, min: 1,
            placeholder: "20",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Maximum number of racks this room can hold.</p>
      </div>

      <div>
        <%= f.label :power_capacity_kw, "Power Capacity (kW)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :power_capacity_kw, step: 0.01, min: 0,
            placeholder: "500.00",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Total power capacity in kilowatts.</p>
      </div>

      <div>
        <%= f.label :cooling_capacity_kw, "Cooling Capacity (kW)", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :cooling_capacity_kw, step: 0.01, min: 0,
            placeholder: "400.00",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Total cooling capacity in kilowatts.</p>
      </div>
    </div>
  </div>

  <div class="flex items-center justify-end gap-3 pt-4">
    <%= link_to "Cancel", @room.persisted? ? room_path(@room) : rooms_path, class: "btn-secondary" %>
    <%= f.submit @room.new_record? ? "Create Room" : "Update Room", class: "btn-primary" %>
  </div>
<% end %>
```

### Step 4.4: Create new and edit views

Create `app/views/rooms/new.html.erb`:

```erb
<% content_for(:page_title) { "New Room" } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Rooms", rooms_path, class: "hover:text-teal-600" %> /
    <span class="text-slate-700">New</span>
  </nav>
  <h1 class="text-2xl font-bold text-slate-900">New Room</h1>
</div>

<%= render "form" %>
```

Create `app/views/rooms/edit.html.erb`:

```erb
<% content_for(:page_title) { "Edit #{@room.name}" } %>

<div class="mb-6">
  <nav class="text-sm text-slate-500 mb-2">
    <%= link_to "Rooms", rooms_path, class: "hover:text-teal-600" %> /
    <%= link_to @room.name, room_path(@room), class: "hover:text-teal-600" %> /
    <span class="text-slate-700">Edit</span>
  </nav>
  <h1 class="text-2xl font-bold text-slate-900">Edit <%= @room.name %></h1>
</div>

<%= render "form" %>
```

### Step 4.5: Verify views render

Run:
```bash
bin/rails runner "puts Room.count"
```

Then start server and manually verify views render (or run specs).

### Step 4.6: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(rooms): add Room views (index, show, new, edit, form)

- Index with site filter and utilization display
- Show with overview, capacity stats, and racks list
- Form with location and physical specification fields
- Consistent NetBox-style design

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create Rooms Request Specs

**Files:**
- Create: `spec/requests/rooms_spec.rb`

### Step 5.1: Create rooms request spec

Create `spec/requests/rooms_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rooms", type: :request do
  let(:user) { create(:user, :approver) }
  let(:site) { create(:site) }
  let(:room) { create(:room, site: site) }

  before do
    sign_in user
  end

  describe "GET /rooms" do
    it "returns http success" do
      get rooms_path
      expect(response).to have_http_status(:success)
    end

    it "displays rooms" do
      room # create the room
      get rooms_path
      expect(response.body).to include(room.name)
    end

    context "with site filter" do
      let(:other_site) { create(:site) }
      let!(:room_in_site) { create(:room, site: site, name: "FilteredRoom") }
      let!(:room_in_other_site) { create(:room, site: other_site, name: "OtherRoom") }

      it "filters rooms by site when site_id param is provided" do
        get rooms_path, params: { site_id: site.id }
        expect(response.body).to include("FilteredRoom")
        expect(response.body).not_to include("OtherRoom")
      end

      it "shows all rooms when no site filter" do
        get rooms_path
        expect(response.body).to include("FilteredRoom")
        expect(response.body).to include("OtherRoom")
      end
    end
  end

  describe "GET /rooms/:id" do
    it "returns http success" do
      get room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "shows room details" do
      get room_path(room)
      expect(response.body).to include(room.name)
      expect(response.body).to include(room.site.name)
    end

    context "with racks" do
      let!(:rack) { create(:server_rack, room: room) }

      it "displays racks" do
        get room_path(room)
        expect(response.body).to include(rack.name)
      end
    end
  end

  describe "GET /rooms/new" do
    it "returns http success" do
      get new_room_path
      expect(response).to have_http_status(:success)
    end

    it "renders the form" do
      get new_room_path
      expect(response.body).to include("Name")
      expect(response.body).to include("Floor")
    end

    it "preselects site when site_id param is provided" do
      get new_room_path, params: { site_id: site.id }
      expect(response).to have_http_status(:success)
      expect(response.body).to include(site.name)
    end
  end

  describe "POST /rooms" do
    let(:valid_params) do
      {
        room: {
          site_id: site.id,
          name: "New Server Room",
          description: "Main server room",
          floor_number: 1,
          building_wing: "East",
          floor_area_sqm: 100.0,
          power_capacity_kw: 50.0
        }
      }
    end

    it "creates a new room" do
      expect do
        post rooms_path, params: valid_params
      end.to change(Room, :count).by(1)
    end

    it "redirects to room show page" do
      post rooms_path, params: valid_params
      expect(response).to redirect_to(room_path(Room.last))
    end

    context "with invalid params" do
      let(:invalid_params) { { room: { name: "", site_id: site.id } } }

      it "does not create a room" do
        expect do
          post rooms_path, params: invalid_params
        end.not_to change(Room, :count)
      end

      it "renders unprocessable_entity status" do
        post rooms_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /rooms/:id/edit" do
    it "returns http success" do
      get edit_room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "renders the form with existing data" do
      get edit_room_path(room)
      expect(response.body).to include(room.name)
    end
  end

  describe "PATCH /rooms/:id" do
    let(:update_params) { { room: { description: "Updated description" } } }

    it "updates the room" do
      patch room_path(room), params: update_params
      expect(room.reload.description).to eq("Updated description")
    end

    it "redirects to room show page" do
      patch room_path(room), params: update_params
      expect(response).to redirect_to(room_path(room))
    end

    context "with invalid params" do
      let(:invalid_params) { { room: { name: "" } } }

      it "renders edit with unprocessable_entity status" do
        patch room_path(room), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /rooms/:id" do
    context "when room has no racks" do
      it "deletes the room" do
        room_to_delete = create(:room)
        expect {
          delete room_path(room_to_delete)
        }.to change(Room, :count).by(-1)
      end

      it "redirects to rooms index" do
        delete room_path(room)
        expect(response).to redirect_to(rooms_path)
      end
    end

    context "when room has racks" do
      let!(:rack) { create(:server_rack, room: room) }

      it "does not delete the room" do
        expect {
          delete room_path(room)
        }.not_to change(Room, :count)
      end

      it "redirects to room show with alert" do
        delete room_path(room)
        expect(response).to redirect_to(room_path(room))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "GET /rooms/for_site" do
    let!(:room1) { create(:room, site: site, name: "Room A") }
    let!(:room2) { create(:room, site: site, name: "Room B") }
    let(:other_site) { create(:site) }
    let!(:other_room) { create(:room, site: other_site, name: "Other Room") }

    it "returns rooms for the specified site" do
      get for_site_rooms_path, params: { site_id: site.id }
      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body)
      expect(json.map { |r| r["name"] }).to contain_exactly("Room A", "Room B")
    end
  end

  describe "authorization" do
    let(:viewer_user) { create(:user, :viewer) }

    before do
      sign_in viewer_user
    end

    it "allows viewers to access index" do
      get rooms_path
      expect(response).to have_http_status(:success)
    end

    it "allows viewers to access show" do
      get room_path(room)
      expect(response).to have_http_status(:success)
    end

    it "denies viewers access to new" do
      get new_room_path
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to create" do
      post rooms_path, params: { room: { name: "Denied", site_id: site.id } }
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to edit" do
      get edit_room_path(room)
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to update" do
      patch room_path(room), params: { room: { name: "Denied" } }
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end

    it "denies viewers access to destroy" do
      delete room_path(room)
      expect(response).to redirect_to(rooms_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "requires authentication for index" do
      get rooms_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "requires authentication for show" do
      get room_path(room)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
```

### Step 5.2: Run rooms specs

Run:
```bash
bin/rspec spec/requests/rooms_spec.rb
```

Expected: All tests pass.

### Step 5.3: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
test(rooms): add RoomsController request specs

- Full CRUD coverage
- Site filtering tests
- Authorization tests (approver vs viewer)
- Authentication tests
- for_site endpoint tests

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Update ServerRacksController and Views

**Files:**
- Modify: `app/controllers/server_racks_controller.rb`
- Modify: `app/views/server_racks/index.html.erb`
- Modify: `app/views/server_racks/_form.html.erb`
- Modify: `app/views/server_racks/show.html.erb`

### Step 6.1: Update ServerRacksController

Edit `app/controllers/server_racks_controller.rb`:

```ruby
# frozen_string_literal: true

class ServerRacksController < ApplicationController
  layout "dashboard"
  before_action :authenticate_user!
  before_action :set_server_rack, only: %i[show edit update destroy update_layout]
  before_action :authorize_approver!, only: %i[new create edit update destroy update_layout]

  def index
    @server_racks = ServerRack.includes(room: :site).includes(:nodes).order(:name)

    if params[:room_id].present?
      @server_racks = @server_racks.where(room_id: params[:room_id])
    elsif params[:site_id].present?
      @server_racks = @server_racks.joins(:room).where(rooms: { site_id: params[:site_id] })
    end

    @sites = Site.order(:name)
    @rooms = if params[:site_id].present?
               Room.where(site_id: params[:site_id]).order(:name)
             else
               Room.includes(:site).order(:name)
             end
  end

  def show
  end

  def new
    @server_rack = ServerRack.new
    @server_rack.room_id = params[:room_id] if params[:room_id].present?
    @rooms = Room.includes(:site).order("sites.name", :name)
    @sites = Site.order(:name)
  end

  def create
    @server_rack = ServerRack.new(server_rack_params)

    if @server_rack.save
      redirect_to server_racks_path, notice: "Rack was successfully created."
    else
      @rooms = Room.includes(:site).order("sites.name", :name)
      @sites = Site.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @rooms = Room.includes(:site).order("sites.name", :name)
    @sites = Site.order(:name)
  end

  def update
    if @server_rack.update(server_rack_params)
      redirect_to server_racks_path, notice: "Rack was successfully updated."
    else
      @rooms = Room.includes(:site).order("sites.name", :name)
      @sites = Site.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @server_rack.destroy
    redirect_to server_racks_path, notice: "Rack was successfully deleted."
  end

  def update_layout
    service = Racks::UpdateLayoutService.new(@server_rack, params[:positions])
    result = service.call

    render json: { success: result.success?, errors: result.errors }
  end

  private

  def set_server_rack
    @server_rack = ServerRack.includes(room: :site).includes(:nodes).find(params[:id])
  end

  def server_rack_params
    params.require(:server_rack).permit(:room_id, :name, :u_height, :status, :facility_id, :asset_tag, :desc_units)
  end

  def authorize_approver!
    return if current_user.approver?

    redirect_to server_racks_path, alert: "You are not authorized to manage racks."
  end
end
```

### Step 6.2: Update server_racks index view

Edit `app/views/server_racks/index.html.erb` to add Room column and filters:

```erb
<% content_for(:page_title) { "Racks" } %>

<div class="flex items-center justify-between mb-6">
  <div>
    <h1 class="text-2xl font-bold text-slate-900">Racks</h1>
    <p class="text-sm text-slate-500 mt-1">Manage server racks across your sites</p>
  </div>
  <% if current_user.approver? %>
    <%= link_to new_server_rack_path, class: "btn-primary" do %>
      <svg class="h-4 w-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
      </svg>
      Add Rack
    <% end %>
  <% end %>
</div>

<%# Filters %>
<div class="mb-4" data-controller="cascading-select">
  <%= form_with url: server_racks_path, method: :get, data: { turbo_frame: "_top" }, class: "flex items-center gap-4 flex-wrap" do |f| %>
    <div class="flex items-center gap-2">
      <%= f.label :site_id, "Site:", class: "text-sm font-medium text-slate-700" %>
      <%= f.select :site_id,
          options_from_collection_for_select(@sites, :id, :name, params[:site_id]),
          { include_blank: "All Sites" },
          class: "rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
          data: { cascading_select_target: "parent", action: "change->cascading-select#parentChanged" } %>
    </div>
    <div class="flex items-center gap-2">
      <%= f.label :room_id, "Room:", class: "text-sm font-medium text-slate-700" %>
      <%= f.select :room_id,
          options_from_collection_for_select(@rooms, :id, proc { |r| "#{r.site.name} / #{r.name}" }, params[:room_id]),
          { include_blank: "All Rooms" },
          class: "rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
          data: { cascading_select_target: "child" },
          onchange: "this.form.submit()" %>
    </div>
    <% if params[:site_id].present? || params[:room_id].present? %>
      <%= link_to "Clear Filters", server_racks_path, class: "text-sm text-teal-600 hover:text-teal-700" %>
    <% end %>
  <% end %>
</div>

<div class="card-netbox">
  <% if @server_racks.any? %>
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-slate-200 text-sm">
        <thead class="bg-slate-50">
          <tr>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Name</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Site</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Room</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Height</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Utilization</th>
            <th scope="col" class="px-3 py-2 text-left text-xs font-bold uppercase tracking-wider text-slate-500 border-b">Status</th>
            <th scope="col" class="relative px-3 py-2 border-b">
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-200 bg-white">
          <% @server_racks.each do |rack| %>
            <tr class="hover:bg-slate-50 transition-colors">
              <td class="whitespace-nowrap px-3 py-2">
                <%= link_to server_rack_path(rack), class: "group" do %>
                  <p class="text-sm font-bold text-slate-900 group-hover:text-teal-600"><%= rack.name %></p>
                  <% if rack.facility_id.present? %>
                    <p class="text-xs text-slate-500 font-mono"><%= rack.facility_id %></p>
                  <% end %>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-600">
                <%= link_to rack.site.name, site_path(rack.site), class: "hover:text-teal-600" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-600">
                <%= link_to rack.room.name, room_path(rack.room), class: "hover:text-teal-600" %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-sm text-slate-500">
                <%= rack.u_height %>U
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                <div class="flex items-center gap-2">
                  <div class="w-24 h-2 bg-slate-200 rounded-full overflow-hidden">
                    <div class="h-full bg-teal-500 rounded-full" style="width: <%= rack.utilization_percentage %>%"></div>
                  </div>
                  <span class="text-xs text-slate-500"><%= rack.utilization_percentage %>%</span>
                </div>
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                <% case rack.status %>
                <% when "active" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-emerald-100 text-emerald-800 border border-emerald-200">
                    Active
                  </span>
                <% when "planned" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-blue-100 text-blue-800 border border-blue-200">
                    Planned
                  </span>
                <% when "decommissioned" %>
                  <span class="inline-flex items-center rounded-sm px-2 py-0.5 text-xs font-medium bg-slate-100 text-slate-600 border border-slate-200">
                    Decommissioned
                  </span>
                <% end %>
              </td>
              <td class="whitespace-nowrap px-3 py-2 text-right text-sm">
                <%= link_to "View", server_rack_path(rack), class: "text-teal-600 hover:text-teal-700 font-medium" %>
                <% if current_user.approver? %>
                  <span class="text-slate-300 mx-1">|</span>
                  <%= link_to "Edit", edit_server_rack_path(rack), class: "text-slate-600 hover:text-slate-700 font-medium" %>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% else %>
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <div class="h-12 w-12 rounded-full bg-slate-100 flex items-center justify-center mb-4">
        <svg class="h-6 w-6 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01" />
        </svg>
      </div>
      <p class="text-sm font-medium text-slate-900">No racks yet</p>
      <p class="mt-1 text-xs text-slate-500">Create a rack to organize your server infrastructure</p>
      <% if current_user.approver? %>
        <%= link_to new_server_rack_path, class: "mt-4 btn-primary" do %>
          Add Rack
        <% end %>
      <% end %>
    </div>
  <% end %>
</div>
```

### Step 6.3: Update server_racks form

Edit `app/views/server_racks/_form.html.erb` to use room_id instead of site_id:

```erb
<%= form_with(model: @server_rack, class: "space-y-6") do |f| %>
  <% if @server_rack.errors.any? %>
    <div class="rounded-lg bg-red-50 p-4 text-sm text-red-700 border border-red-200">
      <h2 class="font-bold mb-2"><%= pluralize(@server_rack.errors.count, "error") %> prohibited this rack from being saved:</h2>
      <ul class="list-disc list-inside">
        <% @server_rack.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <%# Basic Information %>
  <div class="card-netbox">
    <div class="card-header">
      <h3 class="card-title">Rack Information</h3>
    </div>
    <div class="p-4 grid grid-cols-1 md:grid-cols-2 gap-6">
      <div>
        <%= f.label :room_id, "Room", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.collection_select :room_id, @rooms, :id, proc { |r| "#{r.site.name} / #{r.name}" },
            { prompt: "Select a room" },
            { required: true, class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" } %>
        <p class="mt-1 text-xs text-slate-500">Room where this rack is located.</p>
      </div>

      <div>
        <%= f.label :name, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :name, required: true,
            placeholder: "Rack A1",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Display name for this rack.</p>
      </div>

      <div>
        <%= f.label :u_height, "U Height", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.number_field :u_height, required: true,
            min: 1, max: 100, value: @server_rack.u_height || 42,
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Height of the rack in rack units (1-100U).</p>
      </div>

      <div>
        <%= f.label :status, class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.select :status,
            options_for_select([["Active", "active"], ["Planned", "planned"], ["Decommissioned", "decommissioned"]], @server_rack.status || "active"),
            {},
            { class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" } %>
        <p class="mt-1 text-xs text-slate-500">Current operational status of the rack.</p>
      </div>

      <div>
        <%= f.label :facility_id, "Facility ID", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :facility_id,
            placeholder: "FAC-001",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Optional facility identifier.</p>
      </div>

      <div>
        <%= f.label :asset_tag, "Asset Tag", class: "block text-sm font-bold text-slate-700 mb-1" %>
        <%= f.text_field :asset_tag,
            placeholder: "ASSET-001",
            class: "block w-full rounded-md border-slate-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" %>
        <p class="mt-1 text-xs text-slate-500">Optional asset tag for tracking.</p>
      </div>

      <div class="md:col-span-2">
        <div class="flex items-center gap-2">
          <%= f.check_box :desc_units, class: "rounded border-slate-300 text-teal-600 focus:ring-teal-500" %>
          <%= f.label :desc_units, "Descending Units", class: "text-sm font-bold text-slate-700" %>
        </div>
        <p class="mt-1 text-xs text-slate-500 ml-6">Check if rack units are numbered from top to bottom (U1 at top).</p>
      </div>
    </div>
  </div>

  <div class="flex items-center justify-end gap-3 pt-4">
    <%= link_to "Cancel", server_racks_path, class: "btn-secondary" %>
    <%= f.submit @server_rack.new_record? ? "Create Rack" : "Update Rack", class: "btn-primary" %>
  </div>
<% end %>
```

### Step 6.4: Update server_racks show breadcrumb

Edit `app/views/server_racks/show.html.erb`, update the breadcrumb at the top (first ~10 lines):

Change from:
```erb
<nav class="text-sm text-slate-500 mb-2">
  <%= link_to "Racks", server_racks_path, class: "hover:text-teal-600" %> /
  <span class="text-slate-700"><%= @server_rack.name %></span>
</nav>
```

To:
```erb
<nav class="text-sm text-slate-500 mb-2">
  <%= link_to "Sites", sites_path, class: "hover:text-teal-600" %> /
  <%= link_to @server_rack.site.name, site_path(@server_rack.site), class: "hover:text-teal-600" %> /
  <%= link_to @server_rack.room.name, room_path(@server_rack.room), class: "hover:text-teal-600" %> /
  <span class="text-slate-700"><%= @server_rack.name %></span>
</nav>
```

### Step 6.5: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(racks): update ServerRacks to use room hierarchy

- Controller uses room_id instead of site_id
- Index has Site and Room filters
- Form selects room instead of site
- Breadcrumb shows full hierarchy path
- Room column added to index table

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update Sites Views for Room Hierarchy

**Files:**
- Modify: `app/views/sites/show.html.erb`
- Modify: `app/views/sites/index.html.erb`

### Step 7.1: Update sites show view

Edit `app/views/sites/show.html.erb` to show rooms instead of racks directly. Replace the Racks List section with a Rooms List:

The changes are extensive - replace the entire "Racks List" section (starting around line 85) with a "Rooms List" section. Also update the Overview and Statistics cards to reference rooms.

See the full updated file in the implementation.

### Step 7.2: Update sites index view

Edit `app/views/sites/index.html.erb` to add a "Rooms" column and update counts.

### Step 7.3: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(sites): update Sites views for room hierarchy

- Show view displays rooms instead of direct racks
- Index shows room count column
- Statistics updated to aggregate through rooms

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update ServerRacks Request Specs

**Files:**
- Modify: `spec/requests/server_racks_spec.rb`

### Step 8.1: Update server_racks specs

Update `spec/requests/server_racks_spec.rb` to use room instead of site:

Key changes:
- Replace `let(:site)` with `let(:room)`
- Update factory calls to use `room` instead of `site`
- Update filter tests to test both `site_id` and `room_id` params
- Update params in create/update tests

### Step 8.2: Run updated specs

Run:
```bash
bin/rspec spec/requests/server_racks_spec.rb
```

Expected: All tests pass.

### Step 8.3: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
test(racks): update ServerRacks specs for room hierarchy

- Use room factory instead of direct site
- Test room_id and site_id filters
- Update create/update params

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add Cascading Select Stimulus Controller

**Files:**
- Create: `app/javascript/controllers/cascading_select_controller.js`

### Step 9.1: Create cascading select controller

Create `app/javascript/controllers/cascading_select_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["parent", "child"]
  static values = {
    url: { type: String, default: "/rooms/for_site" }
  }

  parentChanged() {
    const siteId = this.parentTarget.value

    if (!siteId) {
      // Reset to all rooms and submit
      this.element.submit()
      return
    }

    // Fetch rooms for site and update child select
    fetch(`${this.urlValue}?site_id=${siteId}`)
      .then(response => response.json())
      .then(rooms => {
        this.updateChildOptions(rooms)
        this.element.submit()
      })
  }

  updateChildOptions(rooms) {
    const child = this.childTarget
    const currentValue = child.value

    // Clear existing options except "All Rooms"
    while (child.options.length > 1) {
      child.remove(1)
    }

    // Add new options
    rooms.forEach(room => {
      const option = new Option(room.name, room.id)
      child.add(option)
    })

    // Restore selection if still valid
    if (rooms.some(r => r.id.toString() === currentValue)) {
      child.value = currentValue
    }
  }
}
```

### Step 9.2: Verify controller is loaded

Run:
```bash
bin/rails stimulus:manifest:update
```

### Step 9.3: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(js): add cascading select Stimulus controller

Fetches rooms for selected site and updates room dropdown.
Used in racks index filter form.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Add Sidebar Navigation for Rooms

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb` (or equivalent)

### Step 10.1: Add Rooms link to sidebar

Find the sidebar partial and add a "Rooms" link in the Infrastructure section, after Sites.

### Step 10.2: Commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): add Rooms link to sidebar navigation

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Run Full Test Suite

### Step 11.1: Run all specs

Run:
```bash
bin/rspec
```

Expected: All tests pass (may need to fix any specs that reference site directly on racks).

### Step 11.2: Run rubocop

Run:
```bash
bin/rubocop -a
```

Expected: No offenses (or auto-corrected).

### Step 11.3: Fix any failures

If any tests fail, fix them following the TDD approach.

### Step 11.4: Final commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
chore: fix remaining specs and lint issues

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

This plan implements the Room hierarchy feature in 11 tasks:

1. **Migration + Models** - Core database and model changes
2. **Factories + Model Specs** - Testing foundation
3. **RoomsController** - Controller with CRUD + for_site API
4. **Room Views** - Index, show, form views
5. **Rooms Request Specs** - Controller tests
6. **ServerRacks Updates** - Controller, views for room_id
7. **Sites Views Updates** - Show rooms instead of racks
8. **ServerRacks Specs** - Update for room hierarchy
9. **Cascading Select JS** - Stimulus controller for filters
10. **Sidebar Navigation** - Add Rooms link
11. **Full Test Suite** - Verify everything works

Each task has bite-sized steps (2-5 minutes each) with exact file paths, code, and commands.
