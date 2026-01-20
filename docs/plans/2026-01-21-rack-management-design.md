# Rack Management Feature Design

## Overview

Add rack management functionality to track physical node locations, plan capacity, and visualize rack layouts with interactive diagrams.

## Scope

- **Physical location tracking**: Which rack/RU is each node in
- **Capacity planning**: RU utilization per rack
- **Visual rack diagrams**: Interactive canvas-based elevation view with drag-and-drop

**Out of scope**: Power/cooling metrics, cable tracing, nested location hierarchy, half-depth mounting.

## Data Model

### New Models

#### Site (room-level container)

| Field | Type | Notes |
|-------|------|-------|
| id | bigint | PK |
| name | string | Required, unique |
| description | text | Optional |
| created_at | datetime | |
| updated_at | datetime | |

#### Rack

| Field | Type | Notes |
|-------|------|-------|
| id | bigint | PK |
| site_id | bigint | FK, required |
| name | string | Required, unique within site |
| facility_id | string | Optional, unique within site |
| asset_tag | string | Optional |
| u_height | integer | Default: 42 |
| width_mm | integer | Optional |
| depth_mm | integer | Optional |
| max_weight_kg | integer | Optional |
| status | integer | Enum: active (0), planned (1), decommissioned (2) |
| desc_units | boolean | Default: false (bottom-to-top numbering) |
| created_at | datetime | |
| updated_at | datetime | |

**Constraints:**
- Unique: `(site_id, name)`
- Unique: `(site_id, facility_id)` where facility_id is not null

### Node Additions

| Field | Type | Notes |
|-------|------|-------|
| rack_id | bigint | FK, optional |
| rack_position | integer | Starting RU, nullable |
| rack_height | integer | Default: 1, units occupied |

**Validations:**
- If rack_id present, rack_position required
- rack_position must be >= 1 and <= rack.u_height
- rack_position + rack_height - 1 must be <= rack.u_height
- No overlapping positions within same rack

### Relationships

```
Site
└── has_many :racks, dependent: :destroy

Rack
├── belongs_to :site
└── has_many :nodes

Node
└── belongs_to :rack, optional: true
```

## UI Navigation

### Sidebar

```
Organization
├── Dashboard
├── Sites (NEW)
├── Racks (NEW)
└── Nodes
```

### Views

#### Sites Index (`/sites`)

- Table: Name, Description, Rack Count, Node Count, Actions
- "Add Site" button (approver-only)

#### Site Detail (`/sites/:id`)

- Header: Name, description
- Tabs: Overview (list of racks), Settings (edit form)

#### Racks Index (`/racks`)

- Table: Name, Site, Height, Utilization (used/total RU), Status, Actions
- Filter dropdown by Site
- "Add Rack" button (approver-only)

#### Rack Detail (`/racks/:id`)

Main interactive view:

- Header: Name, Site breadcrumb, Status badge, Utilization bar (e.g., "28/42 RU")
- Left panel: Interactive rack elevation diagram (canvas)
- Right panel: Selected node details, or rack properties when nothing selected
- Action buttons: Edit Rack, Add Node to Rack, Save Layout

#### Node Integration

- Node detail: Shows rack assignment with link to rack view
- Node edit form: Rack selector, position, height fields
- Nodes index: "Unracked" filter option

## Interactive Rack Diagram

### Technology

Canvas-based rendering using Fabric.js for full control over interactions.

### Visual Layout

- Left side: RU numbers (1 to u_height), bottom-to-top by default
- Center: Rack frame with grid of RU slots
- Nodes rendered as colored rectangles spanning their height

### Visual States

| Element | Appearance |
|---------|------------|
| Empty slot | Light gray background |
| Mounted node | Teal fill (#14b8a6), white text (hostname) |
| Selected node | Highlighted border, elevated shadow |
| Hover | Tooltip: hostname, IP, role, status |
| Drag preview | Semi-transparent ghost at target position |

### Interactions

| Action | Result |
|--------|--------|
| Click node | Select, show details in right panel |
| Drag node | Reposition within rack (validates no overlap) |
| Drag from unracked list | Assign node to position |
| Drag out of rack | Unassign node |
| Double-click node | Navigate to node detail page |

### Save Workflow

- Changes tracked locally until "Save Layout" clicked
- Unsaved changes indicator (dot badge on save button)
- Confirm dialog when navigating away with unsaved changes

## Backend

### Controllers

- `SitesController` - Standard CRUD (index, show, new, create, edit, update, destroy)
- `RacksController` - CRUD + `update_layout` action

### Services

- `Racks::ValidateLayoutService` - Check for overlaps, bounds violations
- `Racks::UpdateLayoutService` - Bulk update node positions in transaction

### Layout API Endpoint

```
PATCH /racks/:id/layout

Request:
{
  "positions": [
    { "node_id": 1, "rack_position": 10, "rack_height": 2 },
    { "node_id": 5, "rack_position": 1, "rack_height": 1 },
    { "node_id": 3, "rack_position": null }
  ]
}

Response (success):
{ "success": true }

Response (error):
{ "success": false, "errors": ["Node 1 overlaps with Node 5"] }
```

### Validation Rules

1. All positions within 1..rack.u_height bounds
2. No overlapping ranges (position to position + height - 1)
3. Node must exist
4. User must have approver role
5. Rollback entire transaction if any validation fails

### Permissions

| Action | Required Role |
|--------|---------------|
| View sites/racks | Any authenticated user |
| Create/edit/delete sites/racks | Approver |
| Modify rack layout | Approver |

## Frontend Implementation

### File Structure

```
app/javascript/
├── controllers/
│   ├── rack_diagram_controller.js    # Stimulus wrapper for Fabric.js
│   └── rack_layout_controller.js     # Save state, navigation guard
└── lib/
    └── rack_diagram/
        ├── index.js                  # Main RackDiagram class
        ├── rack_renderer.js          # Rack frame, RU labels
        ├── node_renderer.js          # Node blocks, styling
        └── drag_handler.js           # Drag-and-drop, snap-to-grid
```

### Stimulus Controller

```javascript
// rack_diagram_controller.js
static values = {
  rackHeight: Number,      // e.g., 42
  nodes: Array,            // [{ id, hostname, position, height, status }]
  readonly: Boolean        // disable editing for non-approvers
}

static targets = ["canvas", "details"]

// Emits custom events:
// - rack-diagram:select (node selected)
// - rack-diagram:change (positions modified)
```

### Dependencies

- `fabric` (Fabric.js) - via yarn

### CSS

- Fixed aspect ratio container for rack diagram
- Responsive scaling on smaller screens
- Dark mode support via Tailwind

## Database Migrations

Execute in order:

1. `CreateSites` - sites table
2. `CreateRacks` - racks table with site_id FK, indexes
3. `AddRackFieldsToNodes` - rack_id, rack_position, rack_height columns

No data migration required - existing nodes will have null rack assignments.

## Testing Strategy

### Model Specs

- Site: validations, associations
- Rack: validations, associations, status enum
- Node: rack validations, overlap detection scope

### Service Specs

- `ValidateLayoutService`: overlap detection, bounds checking, error messages
- `UpdateLayoutService`: successful bulk update, rollback on failure

### Controller Specs

- Sites/Racks CRUD operations
- Layout endpoint: success, validation errors, permission denied

### System Specs (Capybara + JS driver)

- Navigate to rack detail, verify diagram renders
- Select node, verify details panel updates
- Drag node to new position, save, verify persistence
- Attempt invalid position, verify error message

## Rollout

- Feature is additive - no breaking changes
- Existing node workflows unchanged
- Agent push/collect operations unaffected
- Benchmark functionality unaffected

Users can gradually assign rack positions to existing nodes via the new UI.
