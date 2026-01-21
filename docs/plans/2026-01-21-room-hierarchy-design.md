# Room Hierarchy Design

**Date:** 2026-01-21
**Status:** Approved
**Goal:** Restore 3-layer architecture (Site → Room → Rack) for physical accuracy

## Overview

Data centers have distinct rooms/halls that need to be modeled. The current 2-layer hierarchy (Site → Rack) doesn't reflect physical reality. This design adds Room as an intermediate layer with full physical and location attributes.

## Architecture

```
Site (1) ──→ Room (many) ──→ ServerRack (many) ──→ Node (many)
```

**Key constraints:**
- All racks MUST belong to a room (mandatory hierarchy)
- Room count per site varies (some sites have 1 room, others have many)
- Can't delete a room that has racks (`dependent: :restrict_with_error`)

## Data Model

### Room Model (new table: `rooms`)

| Field | Type | Constraints |
|-------|------|-------------|
| `id` | bigint | PK |
| `site_id` | bigint | FK, required, indexed |
| `name` | string | required, unique per site |
| `description` | text | optional |
| `floor_area_sqm` | decimal | optional, > 0 |
| `power_capacity_kw` | decimal | optional, > 0 |
| `cooling_capacity_kw` | decimal | optional, > 0 |
| `max_rack_count` | integer | optional, > 0 |
| `floor_number` | integer | optional |
| `building_wing` | string | optional |
| `grid_coordinates` | string | optional |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Relationship Changes

```ruby
# app/models/site.rb
class Site < ApplicationRecord
  has_many :rooms, dependent: :destroy
  has_many :server_racks, through: :rooms
end

# app/models/room.rb (new)
class Room < ApplicationRecord
  belongs_to :site
  has_many :server_racks, dependent: :restrict_with_error
end

# app/models/server_rack.rb
class ServerRack < ApplicationRecord
  belongs_to :room                    # CHANGED from :site
  has_many :nodes, foreign_key: :rack_id
  delegate :site, to: :room           # NEW - convenience accessor
end
```

### Room Model Validations

```ruby
validates :name, presence: true, uniqueness: { scope: :site_id }
validates :floor_area_sqm, numericality: { greater_than: 0 }, allow_nil: true
validates :power_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
validates :cooling_capacity_kw, numericality: { greater_than: 0 }, allow_nil: true
validates :max_rack_count, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
```

### Room Model Methods

```ruby
def rack_count
  server_racks.count
end

def utilization
  # Total U used / Total U available across all racks
end

def at_capacity?
  max_rack_count.present? && rack_count >= max_rack_count
end
```

## Migration Strategy

### Step 1: Create rooms table

New migration adds the `rooms` table with all fields defined above.

### Step 2: Add room_id to racks

Add `room_id` column to `racks` table (nullable initially for migration).

### Step 3: Data migration

For each existing site:
1. Create a room named "Default Room" with `description: "Auto-created during migration"`
2. Update all racks belonging to that site to point to the new room

### Step 4: Finalize schema

- Make `room_id` NOT NULL on racks
- Remove `site_id` column from racks (site accessed via room)
- Add foreign key constraint and index on `room_id`

### Rollback safety

The migration will be reversible:
- Rollback re-adds `site_id` to racks, copies from `room.site_id`
- Deletes auto-created "Default Room" records
- Drops `rooms` table

### Note on existing orphaned rooms table

The current schema has an unused `rooms` table (orphaned from previous architecture). Drop it first and recreate with proper structure.

## Controllers & Routes

### New RoomsController

Standard CRUD actions: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`

- `index`: List all rooms, filterable by `site_id` param
- `show`: Room details with rack list and capacity utilization
- `destroy`: Blocked if room has racks (model enforces this)
- Authorization: `authorize_approver!` for write actions

### ServerRacksController Changes

- `index`: Add `room_id` filter dropdown (alongside existing `site_id` filter)
- `new`/`create`/`edit`/`update`: Change `site_id` param to `room_id`
- Site filter becomes cascading filter (select site → room dropdown updates)

### Routes

```ruby
resources :sites do
  resources :rooms, shallow: true
end

resources :rooms do
  resources :server_racks, shallow: true, only: [:new, :create]
end

resources :server_racks, except: [:new, :create] do
  patch :update_layout, on: :member
end
```

Shallow nesting keeps URLs clean: `/rooms/5` instead of `/sites/1/rooms/5` after creation.

### SitesController Changes

- `show`: Include rooms list with rack counts per room

## Views & UI

### Rooms Views (new)

- `index.html.erb`: Table with site filter, columns: Name, Site, Rack Count, Utilization, Floor, Wing
- `show.html.erb`: Room details panel, capacity stats card, racks table, danger zone for delete
- `_form.html.erb`: All room fields, site dropdown (pre-selected if coming from site page)

### Sites Views (changes)

- `show.html.erb`: Replace racks table with rooms table showing:
  - Room name, rack count, total nodes, utilization
  - Click-through to room detail

### ServerRacks Views (changes)

- `index.html.erb`:
  - Two filter dropdowns: Site (primary), Room (secondary, updates via Stimulus when site changes)
  - Add "Room" column to table between Site and Name
- `_form.html.erb`: Replace site dropdown with room dropdown (optionally cascading site→room selectors)
- `show.html.erb`: Breadcrumb updates to: Site → Room → Rack

### Stimulus Controller (new)

`cascading_select_controller.js` - When site dropdown changes, fetch rooms for that site and populate room dropdown. Reusable pattern.

## Services

### Existing Services (minimal changes)

- `Racks::UpdateLayoutService` - No changes needed (works with rack, not site/room)
- `Racks::ValidateLayoutService` - No changes needed

No new services required - the hierarchy change is primarily a data model concern.

## Testing

### New Factories

```ruby
# spec/factories/rooms.rb
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
end
```

### Updated Factories

- `server_rack` factory: Change `site` association to `room`

### Model Specs

- `spec/models/room_spec.rb`: Validations, associations, methods (`utilization`, `at_capacity?`)
- `spec/models/server_rack_spec.rb`: Update association tests, add `delegate :site` test

### Controller Specs

- `spec/requests/rooms_spec.rb`: Full CRUD coverage, authorization checks
- `spec/requests/server_racks_spec.rb`: Update to use room_id, test cascading filters

### System Specs

- Update any rack-related system specs to create room first

### Migration Spec

- Test that migration correctly creates default rooms and reassigns racks

## Files Summary

| Type | Files |
|------|-------|
| Migration | 1 new (create rooms, modify racks) |
| Models | 1 new (Room), 2 modified (Site, ServerRack) |
| Controllers | 1 new (RoomsController), 2 modified (Sites, ServerRacks) |
| Views | ~5 new (rooms/), ~4 modified (sites/, server_racks/) |
| JavaScript | 1 new (cascading_select_controller) |
| Tests | ~3 new spec files, ~2 modified |
