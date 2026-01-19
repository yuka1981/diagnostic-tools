# Feature Request: 機櫃管理與視覺化 (Rack Management & Visualization)

Version: 1.0.0
Status: Proposed
Last Updated: 2026-01-20

## **1. 概述 (Summary)**

Introduce physical location management for HPC nodes through a Room → Rack hierarchy. This feature enables:

* **Visual Inventory**: Rack elevation views showing node placement across U positions
* **Capacity Planning**: Track rack utilization and available space
* **Dashboard Grouping**: Organize nodes by physical location for monitoring

## **2. 核心需求 (Core Requirements)**

### **2.1 資料模型 (Data Models)**

#### **2.1.1 Room Model**

Represents a physical machine room or data center space.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | bigint | PK | Primary key |
| `name` | string | required, unique | Room identifier (e.g., "DC-1", "Machine Room A") |
| `description` | text | optional | Additional details about the room |
| `timestamps` | datetime | auto | created_at, updated_at |

**Associations:**
* `has_many :racks, dependent: :restrict_with_error`

#### **2.1.2 Rack Model**

Represents a physical equipment rack.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | bigint | PK | Primary key |
| `room_id` | bigint | FK, optional | Associated room (allows unassigned racks) |
| `name` | string | required, unique within room | Rack identifier (e.g., "R01", "A-12") |
| `u_height` | integer | default: 42 | Total rack units available |
| `width` | integer | default: 19 | Rack width in inches (standard: 19") |
| `notes` | text | optional | Additional notes |
| `timestamps` | datetime | auto | created_at, updated_at |

**Associations:**
* `belongs_to :room, optional: true`
* `has_many :nodes, dependent: :nullify`

#### **2.1.3 Node Model Extensions**

Add physical location fields to existing `nodes` table.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `rack_id` | bigint | FK, optional | Associated rack |
| `rack_position` | integer | >= 1 | Starting U position (1-based, from bottom) |
| `rack_height` | integer | default: 1 | Number of U units occupied |
| `rack_face` | integer | enum, default: 0 | Installation face (0: front, 1: rear) |

**Associations:**
* `belongs_to :rack, optional: true`

### **2.2 驗證邏輯 (Validation Rules)**

#### **2.2.1 Position Bounds Validation**

Ensure nodes fit within rack dimensions:

```
rack_position >= 1 AND
rack_position + rack_height - 1 <= rack.u_height
```

#### **2.2.2 Overlap Prevention**

No two nodes on the same rack and face can occupy overlapping U ranges:

```ruby
# Pseudo-validation logic
conflicting_nodes = rack.nodes
  .where(rack_face: self.rack_face)
  .where.not(id: self.id)
  .where("rack_position < ? AND rack_position + rack_height > ?",
         rack_position + rack_height, rack_position)

errors.add(:base, "overlaps with existing node") if conflicting_nodes.exists?
```

#### **2.2.3 Rack Height Constraint**

Cannot reduce `u_height` if existing nodes would exceed new height:

```ruby
# On Rack model
validate :u_height_not_below_occupied

def u_height_not_below_occupied
  return unless u_height_changed? && nodes.any?

  max_occupied = nodes.maximum("rack_position + rack_height - 1")
  if max_occupied && u_height < max_occupied
    errors.add(:u_height, "cannot be reduced below occupied position #{max_occupied}")
  end
end
```

#### **2.2.4 Room Deletion Protection**

Rooms cannot be deleted if they contain racks:

```ruby
# On Room model
has_many :racks, dependent: :restrict_with_error
```

## **3. 介面需求 (UI Requirements)**

### **3.1 導航結構 (Navigation Structure)**

```
Sidebar → Inventory
├── Nodes (existing)
├── Rooms (new)
└── Racks (new)
```

### **3.2 機櫃立面視圖 (Rack Elevation View)**

A vertical visualization component for the Rack Show page.

**Display Requirements:**
* Render U positions from top (42) to bottom (1)
* Show U number labels on left side
* Front/Rear toggle button to switch views

**Node Display:**
* Color-coded by status: online (emerald), offline (red/gray)
* Multi-U nodes span their full height visually
* Display node hostname within the occupied space
* Tooltip on hover showing: hostname, status, U range

**Interactions:**
* Click occupied slot → Navigate to node detail page
* Click empty slot → Open modal to assign node (Quick Add)

### **3.3 頁面規格 (Page Specifications)**

#### **3.3.1 Room Pages**

**Index Page:**
| Column | Description |
|--------|-------------|
| Name | Room name (link to show) |
| Description | Truncated description |
| Rack Count | Number of racks in room |
| Actions | Edit, Delete |

**Show Page:**
* Room details card (name, description)
* Rack list with thumbnail elevation previews
* "Add Rack" button

#### **3.3.2 Rack Pages**

**Index Page:**
| Column | Description |
|--------|-------------|
| Room | Parent room (link) or "Unassigned" |
| Name | Rack name (link to show) |
| U Height | Total units |
| Utilization | Percentage of U space occupied |
| Actions | Edit, Delete |

**Show Page:**
* Rack details card (name, room, u_height, width, notes)
* Full rack elevation view (front/rear toggle)
* Node list table showing mounted equipment

#### **3.3.3 Node Form Updates**

Add "Physical Location" section to node create/edit forms:

| Field | Type | Notes |
|-------|------|-------|
| Rack | Select dropdown | Optional, list all racks |
| Position (U) | Number input | 1 to rack.u_height |
| Height (U) | Number input | Default: 1 |
| Face | Radio buttons | Front (default) / Rear |

Show validation errors inline for overlap/bounds issues.

## **4. 儀表板整合 (Dashboard Integration)**

### **4.1 Rack Heatmap View**

Add toggle between existing Node Grid and new Rack-based view:

* **View Toggle:** Nodes | Racks (button group)
* **Rack Heatmap:** Mini rack icons showing utilization colors
* **Click Rack:** Filter dashboard to show only nodes in that rack

### **4.2 New Metrics Cards**

| Metric | Description |
|--------|-------------|
| Total Racks | Count of all racks |
| Average Utilization | Mean percentage across all racks |
| Available U Space | Sum of empty U positions |

## **5. 資料結構 (Data Schema)**

### **5.1 Database Migrations**

```ruby
# Migration: create_rooms
create_table :rooms do |t|
  t.string :name, null: false
  t.text :description
  t.timestamps
end
add_index :rooms, :name, unique: true

# Migration: create_racks
create_table :racks do |t|
  t.references :room, foreign_key: true
  t.string :name, null: false
  t.integer :u_height, default: 42, null: false
  t.integer :width, default: 19, null: false
  t.text :notes
  t.timestamps
end
add_index :racks, [:room_id, :name], unique: true

# Migration: add_rack_fields_to_nodes
add_reference :nodes, :rack, foreign_key: true
add_column :nodes, :rack_position, :integer
add_column :nodes, :rack_height, :integer, default: 1
add_column :nodes, :rack_face, :integer, default: 0
add_index :nodes, [:rack_id, :rack_face, :rack_position]
```

### **5.2 Model Definitions**

```ruby
# app/models/room.rb
class Room < ApplicationRecord
  has_many :racks, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end

# app/models/rack.rb
class Rack < ApplicationRecord
  belongs_to :room, optional: true
  has_many :nodes, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :room_id }
  validates :u_height, numericality: { only_integer: true, greater_than: 0 }
  validates :width, numericality: { only_integer: true, greater_than: 0 }

  validate :u_height_not_below_occupied

  # Returns elevation data for visualization
  # @param face [Symbol] :front or :rear
  # @return [Array<Hash>] Array of unit data from top to bottom
  def elevation_data(face: :front)
    face_value = face == :rear ? 1 : 0
    face_nodes = nodes.where(rack_face: face_value)

    units = Array.new(u_height) { |i| { u: i + 1, node: nil } }

    face_nodes.each do |node|
      next unless node.rack_position
      (0...node.rack_height).each do |offset|
        idx = node.rack_position + offset - 1
        units[idx][:node] = node if idx >= 0 && idx < u_height
      end
    end

    units.reverse # Display top-to-bottom (42 -> 1)
  end

  def utilization_percentage
    return 0 if u_height.zero?

    occupied = nodes.sum(:rack_height)
    (occupied.to_f / u_height * 100).round(1)
  end

  private

  def u_height_not_below_occupied
    return unless u_height_changed? && nodes.any?

    max_occupied = nodes.where.not(rack_position: nil)
                        .maximum(Arel.sql("rack_position + rack_height - 1"))
    if max_occupied && u_height < max_occupied
      errors.add(:u_height, "cannot be reduced below occupied position #{max_occupied}")
    end
  end
end

# app/models/node.rb (additions)
class Node < ApplicationRecord
  belongs_to :rack, optional: true

  enum :rack_face, { front: 0, rear: 1 }, prefix: true

  validate :rack_position_within_bounds, if: :rack_position_required?
  validate :rack_position_no_overlap, if: :rack_position_required?

  private

  def rack_position_required?
    rack.present? && rack_position.present?
  end

  def rack_position_within_bounds
    return unless rack_height.present?

    if rack_position < 1
      errors.add(:rack_position, "must be at least 1")
    elsif rack_position + rack_height - 1 > rack.u_height
      errors.add(:rack_position, "exceeds rack height (max U#{rack.u_height})")
    end
  end

  def rack_position_no_overlap
    conflicting = rack.nodes
      .where(rack_face: rack_face)
      .where.not(id: id)
      .where.not(rack_position: nil)
      .select do |other|
        my_range = rack_position...(rack_position + (rack_height || 1))
        other_range = other.rack_position...(other.rack_position + (other.rack_height || 1))
        my_range.cover?(other_range.first) || other_range.cover?(my_range.first)
      end

    if conflicting.any?
      errors.add(:rack_position, "overlaps with #{conflicting.first.hostname}")
    end
  end
end
```

## **6. API 端點 (API Endpoints)**

Future consideration for API v2:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v2/rooms` | GET | List all rooms |
| `/api/v2/rooms/:id` | GET | Room details with racks |
| `/api/v2/racks` | GET | List all racks |
| `/api/v2/racks/:id` | GET | Rack details with nodes |
| `/api/v2/racks/:id/elevation` | GET | Rack elevation data |

## **7. 未來增強 (Future Enhancements)**

| Feature | Description | Priority |
|---------|-------------|----------|
| Drag & Drop | Reposition nodes by dragging in elevation view | Medium |
| PDU Support | Track power distribution units in racks | Low |
| Site Hierarchy | Add Site level above Room (Site → Room → Rack) | Low |
| Network Ports | Track patch panel and switch port assignments | Low |
| Cable Management | Document inter-rack cabling | Low |
| Rack Templates | Pre-defined layouts for standard configurations | Low |
| Bulk Assignment | Assign multiple nodes to rack positions at once | Medium |
| Export/Import | CSV export/import for rack layouts | Low |
