# Nodes CRUD UI/UX Redesign

## Overview

Redesign the Nodes CRUD interface to reduce complexity and add auto-fill/autocomplete functionality based on existing database data.

**Goals:**
- Simplify the complex 5-section node form into a 3-step wizard
- Add SSH profiles for reusable connection configurations
- Add agent config settings page for default agent settings
- Implement hostname autocomplete with duplicate detection and bulk pattern support
- Support bulk node creation with per-node customization

---

## New Settings Pages

### SSH Profiles Page (`/settings/ssh_profiles`)

**List View:**
- Table with columns: Name, SSH User, Connection Method, Bastion Host, Actions
- "Add Profile" button
- Edit/Delete actions per row

**Profile Fields:**
- Name (e.g., "Compute Cluster A", "Login Nodes") - required, unique
- Connection method (global_bastion, custom_bastion, direct)
- SSH port, user, password, sudo credential
- SSH key (textarea)
- Custom bastion fields (if custom_bastion): jump host, user, port

### Agent Config Page (`/settings/agent_config`)

**Single form with defaults:**
- Default agent path (default: `/usr/local/bin/qis-agent`)
- Default benchmark working directory
- Extensible for future agent settings

These values preload into node forms but can be overridden per-node.

---

## Node Form Wizard

### Step 1: Basic Info

**Progress indicator:** `● Basic Info → ○ Server & Location → ○ Connection`

**Hostname field:**
- Text input with autocomplete dropdown
- As user types, shows:
  - Matching existing hostnames (grayed, labeled "exists") to avoid duplicates
  - Suggested "next in sequence" (e.g., typing `compute-00` suggests `compute-003` if 001, 002 exist)
- Supports bulk pattern: `compute-[001-010]`
  - Detected automatically, shows badge: "10 nodes will be created"
  - Validates pattern syntax and checks for conflicts with existing hostnames

**Role:** Dropdown (compute, login, admin)

**Architecture:** Dropdown (x86_64, aarch64)

**Navigation:** "Next" button (disabled until hostname valid)

### Step 2: Server & Location

**Progress indicator:** `✓ Basic Info → ● Server & Location → ○ Connection`

**Server Model:** Existing searchable dropdown with thumbnail preview, auto-fills rack height

**Rack Assignment:**
- Rack selector (Site / Room / Rack hierarchy)
- Position (RU) - starting position
- Height (U) - auto-filled from server model, editable

**Navigation:** "Back" and "Next" buttons

### Step 3: Connection (Single Node Mode)

**Progress indicator:** `✓ Basic Info → ✓ Server & Location → ● Connection`

**SSH Profile:**
- Dropdown listing existing profiles
- "+ Create new profile" option opens modal (same fields as Settings page)
- Selecting a profile auto-fills all SSH fields below

**SSH Override Fields (collapsed by default):**
- "Customize SSH settings" toggle expands fields
- Shows all SSH fields pre-filled from profile, user can override
- Overrides apply to this node only, don't modify the profile

**Agent Configuration:**
- Agent path (preloaded from Agent Config settings)
- Benchmark working directory (preloaded)
- API token dropdown

**Navigation:** "Back" and "Create Node" buttons

### Step 3: Connection (Bulk Mode)

When pattern like `compute-[001-010]` is detected:

**Same SSH Profile and Agent Config at top (applies to all)**

**Review Table below:**

| Hostname | Role | Rack Position | SSH Profile | Actions |
|----------|------|---------------|-------------|---------|
| compute-001 | compute | Rack-A / RU 1 | Cluster-A | Edit |
| compute-002 | compute | Rack-A / RU 1 | Cluster-A | Edit |
| ... | | | | |

- "Edit" opens inline row editing for that node
- User can change role, rack/position, SSH profile, or agent settings per node
- Bulk actions: "Apply SSH profile to selected", "Apply rack to selected"

**Navigation:** "Back" and "Create N Nodes" button (shows count)

---

## Hostname Autocomplete Behavior

As user types in hostname field:

```
┌─────────────────────────────────────────┐
│ compute-00█                             │
├─────────────────────────────────────────┤
│ Suggestions                             │
│   compute-003  (next available)         │
│   compute-004  (next available)         │
├─────────────────────────────────────────┤
│ Existing (avoid duplicates)             │
│   compute-001  (exists)                 │
│   compute-002  (exists)                 │
└─────────────────────────────────────────┘
```

**Logic:**
- Query existing nodes matching prefix
- Calculate gaps and next sequence numbers
- "Next available" suggestions appear first, highlighted
- Existing hostnames shown grayed out as reference
- Selecting an existing hostname shows validation error

**Bulk pattern detection:**
- When input matches `name-[start-end]` pattern (e.g., `compute-[001-010]`)
- Badge appears: "10 nodes will be created"
- Dropdown shows conflict check: "2 conflicts: compute-003, compute-005 already exist"
- User must resolve conflicts before proceeding

---

## Data Model Changes

### New Model: `SshProfile`

```ruby
# Fields
- name: string (required, unique)
- ssh_connect_method: enum (global_bastion, custom_bastion, direct)
- ssh_port: integer (default: 22)
- ssh_user: string
- ssh_password: string (encrypted)
- ssh_key: text (encrypted)
- sudo_credential: string (encrypted)
- jump_host: string
- jump_user: string
- jump_port: integer

# Association
- has_many :nodes
```

### New Model: `AgentConfig` (singleton settings)

```ruby
# Fields
- default_agent_path: string (default: "/usr/local/bin/qis-agent")
- default_benchmark_working_dir: string

# Single record pattern - use find_or_create for ID 1
```

### Changes to `Node` Model

```ruby
# New association
- belongs_to :ssh_profile, optional: true

# Existing SSH fields remain for overrides
# Add flag to track if using profile or custom
- ssh_profile_override: boolean (default: false)
```

**Behavior:** When node has `ssh_profile` and `ssh_profile_override: false`, SSH settings come from profile. When `override: true`, use node's own SSH fields.

---

## API & Controller Changes

### New Controllers

**`Settings::SshProfilesController`**
- Standard CRUD actions (index, new, create, edit, update, destroy)
- Turbo Stream responses for modal interactions
- Prevent delete if profile has associated nodes (or offer reassignment)

**`Settings::AgentConfigController`**
- `show` and `update` only (singleton pattern)
- Single form that saves/updates the one config record

### Changes to `NodesController`

**`create` action changes:**
- Accept `hostname_pattern` param for bulk creation
- Parse pattern, expand to individual hostnames
- Create multiple nodes in transaction
- Return Turbo Stream that appends all new rows

**New endpoint for hostname suggestions:**
- `GET /api/nodes/hostname_suggestions?prefix=compute-00`
- Returns JSON: `{ suggestions: [...], existing: [...], conflicts: [...] }`

### Routes

```ruby
namespace :settings do
  resources :ssh_profiles
  resource :agent_config, only: [:show, :update]
end

namespace :api do
  resources :nodes, only: [] do
    collection do
      get :hostname_suggestions
    end
  end
end
```

---

## UI Components & Stimulus Controllers

### New ViewComponents

**`NodeFormWizardComponent`**
- Manages 3-step wizard state
- Renders step indicators and navigation buttons
- Contains step partials

**`HostnameAutocompleteComponent`**
- Input with dropdown for suggestions
- Bulk pattern badge display
- Conflict warnings

**`BulkNodeReviewTableComponent`**
- Expandable table for bulk creation
- Inline editing per row

### New Stimulus Controllers

**`wizard_controller.js`**
- Tracks current step (1, 2, 3)
- Validates step before allowing "Next"
- Shows/hides step content

**`hostname_autocomplete_controller.js`**
- Debounced API calls to `/api/nodes/hostname_suggestions`
- Renders suggestion dropdown
- Detects bulk patterns, shows node count badge
- Displays conflict warnings

**`bulk_review_controller.js`**
- Manages inline row editing (toggle edit mode per row)
- Tracks per-node customizations
- Collects all node data for form submission

**`ssh_profile_select_controller.js`**
- Handles profile dropdown selection
- Triggers "Create new" modal
- Auto-fills SSH fields from selected profile

---

## Implementation Phases

### Phase 1: Foundation
- Create `SshProfile` model and migrations
- Create `AgentConfig` model and migrations
- Add `ssh_profile_id` and `ssh_profile_override` to nodes table
- Build SSH Profiles settings page (CRUD)
- Build Agent Config settings page

### Phase 2: Wizard Infrastructure
- Create `NodeFormWizardComponent`
- Create `wizard_controller.js`
- Refactor existing node form into 3-step wizard
- Integrate SSH profile selection into Step 3
- Preload agent config defaults

### Phase 3: Hostname Autocomplete
- Create `/api/nodes/hostname_suggestions` endpoint
- Create `HostnameAutocompleteComponent`
- Create `hostname_autocomplete_controller.js`
- Add bulk pattern detection and validation

### Phase 4: Bulk Creation
- Extend `NodesController#create` for bulk patterns
- Create `BulkNodeReviewTableComponent`
- Create `bulk_review_controller.js`
- Add inline editing functionality
- Turbo Stream responses for multiple node creation
