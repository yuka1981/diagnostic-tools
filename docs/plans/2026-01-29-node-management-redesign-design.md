# Node Management Redesign: qis-agent to Salt API Migration Completion

**Date:** 2026-01-29
**Status:** Draft
**Depends on:** `2026-01-29-saltstack-migration-design.md` (completed)

## Summary

Complete the migration from qis-agent to SaltStack REST API by removing all legacy agent code and updating the frontend to consume Salt-based data. Add a Salt minion auto-discovery feature.

## Scope

### In Scope

1. **Remove all legacy agent code** - controllers, jobs, channels, models, views, routes
2. **Update frontend** - node list/show pages to display Salt-sourced status data
3. **Add Salt minion discovery** - auto-discover unregistered minions from Salt API
4. **Switch node status** - from agent heartbeat to Salt presence events via new `salt_status` enum

### Out of Scope

- Database column removal (columns kept, code stops using them)
- Salt minion lifecycle management (install/uninstall minion packages)
- Go agent code removal (separate cleanup task)
- Caching layer for Salt API responses

## Design

### 1. Legacy Agent Code Removal

#### Files to Delete

**Controllers:**
- `app/controllers/nodes/installs_controller.rb`
- `app/controllers/nodes/uninstalls_controller.rb`
- `app/controllers/nodes/updates_controller.rb`
- `app/controllers/settings/agents_controller.rb`
- `app/controllers/settings/agent_releases_controller.rb`
- `app/controllers/settings/agent_binaries_controller.rb`

**Jobs:**
- `app/jobs/agent/install_job.rb`
- `app/jobs/agent/uninstall_job.rb`
- `app/jobs/agent/update_job.rb`

**Channels:**
- `app/channels/agent_channel.rb`

**Models:**
- `app/models/agent_release.rb`
- `app/models/agent_binary.rb`
- `app/models/agent_event.rb`

**Views:**
- `app/views/nodes/installs/` (entire directory)
- `app/views/nodes/uninstalls/` (entire directory)
- `app/views/nodes/updates/` (entire directory)
- `app/views/settings/agents/` (entire directory)
- `app/views/settings/agent_releases/` (entire directory)

**Specs for removed code:**
- Any specs under `spec/` for the above controllers, jobs, models

#### Routes to Remove

```ruby
# In config/routes.rb, remove:
resource :update, only: %i[new create], controller: "nodes/updates"
resources :installs, only: %i[new create], controller: "nodes/installs", as: :node_install
resources :uninstalls, only: %i[new create], controller: "nodes/uninstalls", as: :node_uninstall
resource :agent, only: [ :show, :update ], controller: :agents
resources :agent_releases do
  member do
    patch :deprecate
    patch :activate
    patch :recall
  end
  resources :binaries, only: %i[new create destroy]
end
```

#### Node Model Changes

- Remove `DEFAULT_AGENT_PATH` constant
- Remove `effective_agent_path` method
- Remove agent-related display logic
- Keep `agent_version`, `agent_status`, `agent_path` DB columns (no migration to drop)
- Keep `source: :agent_push` enum value for backward compatibility with existing records

#### Sidebar Changes

- Remove "Agent Config" link from Admin section in `_sidebar.html.erb`

#### ApplicationCable::Connection Changes

- Remove `find_verified_node` and agent token authentication logic
- Keep user authentication for Turbo Stream subscriptions

### 2. Salt Status Model

#### Migration

```ruby
class AddSaltStatusToNodes < ActiveRecord::Migration[7.2]
  def change
    add_column :nodes, :salt_status, :integer, default: 0, null: false
    add_index :nodes, :salt_status
  end
end
```

#### Node Model

```ruby
class Node < ApplicationRecord
  enum :salt_status, {
    unknown: 0,       # Never seen by Salt (default for existing nodes)
    connected: 1,     # Salt minion responding
    disconnected: 2,  # Salt minion not responding
    pending: 3        # Key not yet accepted
  }, prefix: :salt

  # Add new source type
  enum :source, { manual: 0, csv: 1, agent_push: 2, salt_discovery: 3 }

  def online?
    salt_connected?
  end

  def status
    salt_status.to_sym
  end

  scope :online, -> { where(salt_status: :connected) }
end
```

#### Presence Check Service Update

Modify `Salt::PresenceCheckService` to update `salt_status` instead of `last_heartbeat_at`:

```ruby
module Salt
  class PresenceCheckService
    def call
      result = @salt_client.run_runner("manage.status")
      up_minions = result["up"] || []
      down_minions = result["down"] || []

      Node.where(hostname: up_minions).update_all(
        salt_status: :connected,
        last_seen_at: Time.current
      )

      Node.where(hostname: down_minions)
          .where.not(salt_status: :unknown)
          .update_all(salt_status: :disconnected)

      broadcast_status_changes(up_minions, down_minions)
    end
  end
end
```

### 3. Salt Minion Discovery

#### New Service: `Salt::MinionDiscoveryService`

```ruby
module Salt
  class MinionDiscoveryService
    Result = Struct.new(:success, :discovered, :existing, :error, keyword_init: true) do
      def success? = success
    end

    def initialize(salt_client: nil)
      @salt_client = salt_client || SaltApiClient.new
    end

    def call
      minions = @salt_client.get_minions
      existing_hostnames = Node.pluck(:hostname).to_set

      discovered = []
      existing = []

      minions.each do |minion_id, grains|
        if existing_hostnames.include?(minion_id)
          existing << minion_id
        else
          discovered << build_discovery_record(minion_id, grains)
        end
      end

      Result.new(success: true, discovered: discovered, existing: existing)
    rescue SaltApiClient::ApiError => e
      Result.new(success: false, error: e.message, discovered: [], existing: [])
    end

    private

    def build_discovery_record(minion_id, grains)
      {
        hostname: minion_id,
        ip: grains.dig("ipv4")&.reject { |ip| ip == "127.0.0.1" }&.first,
        arch: grains["cpuarch"],
        os: grains["os"],
        os_release: grains["osrelease"],
        kernel: grains["kernelrelease"],
        cpu_model: grains["cpu_model"],
        mem_total: grains["mem_total"],
        num_cpus: grains["num_cpus"]
      }
    end
  end
end
```

#### SaltApiClient Addition

```ruby
class SaltApiClient
  def get_minions
    ensure_authenticated
    response = get("/minions")
    data = parse_response(response)
    data.dig("return", 0) || {}
  end
end
```

#### Controller Actions

Add to `NodesController`:

```ruby
class NodesController < ApplicationController
  # GET /nodes/discover
  def discover
    authorize! :create, Node  # Approver role required
    result = Salt::MinionDiscoveryService.new.call

    if result.success?
      @discovered = result.discovered
      @existing_count = result.existing.size
    else
      @error = result.error
      @discovered = []
      @existing_count = 0
    end

    respond_to do |format|
      format.turbo_stream
      format.html
    end
  end

  # POST /nodes/import_minions
  def import_minions
    authorize! :create, Node
    hostnames = params[:hostnames] || []
    return redirect_to nodes_path, alert: "No minions selected" if hostnames.empty?

    imported = []
    errors = []

    hostnames.each do |hostname|
      node = Node.new(hostname: hostname, source: :salt_discovery, salt_status: :connected)
      if node.save
        imported << node
        InventoryCollectJob.perform_later(node.id, user_id: current_user.id)
      else
        errors << { hostname: hostname, error: node.errors.full_messages.join(", ") }
      end
    end

    if errors.empty?
      redirect_to nodes_path, notice: "#{imported.size} minion(s) imported successfully"
    else
      redirect_to nodes_path, alert: "#{imported.size} imported, #{errors.size} failed"
    end
  end
end
```

#### Routes Addition

```ruby
resources :nodes do
  collection do
    get :discover
    post :import_minions
  end
end
```

### 4. Frontend Updates

#### Nodes Index Page

**Header actions:**
- Keep "Add Node" button
- Add "Discover Minions" button (approver-only, triggers modal via Turbo Frame)

**Table columns (updated):**
| Column | Source |
|--------|--------|
| Hostname | `node.hostname` |
| Role | `node.role` |
| Architecture | `node.arch` (from Salt grains) |
| Salt Status | `node.salt_status` badge (connected/disconnected/pending/unknown) |
| Last Seen | `node.last_seen_at` (updated by Salt presence) |
| Actions | Show, Edit, Delete, Collect |

**Removed columns:** Agent Version
**Removed row actions:** Install, Update, Uninstall agent buttons

#### Discovery Modal

Triggered by "Discover Minions" button. Uses existing `_modal.html.erb` partial:

```erb
<!-- nodes/discover.turbo_stream.erb -->
<%= turbo_stream.replace "discovery_modal" do %>
  <%= render "shared/modal", title: "Discover Salt Minions" do %>
    <% if @error %>
      <div class="text-error-6 p-4">
        Salt API error: <%= @error %>
      </div>
    <% elsif @discovered.empty? %>
      <div class="text-neutral-45 p-4">
        All <%= @existing_count %> connected minions are already registered.
      </div>
    <% else %>
      <%= form_with url: import_minions_nodes_path, method: :post do |f| %>
        <div class="p-4">
          <p class="text-sm text-neutral-45 mb-4">
            Found <%= @discovered.size %> unregistered minion(s).
            <%= @existing_count %> already registered.
          </p>
          <div data-controller="bulk-select">
            <!-- Select all checkbox -->
            <!-- Table of discovered minions with checkboxes -->
            <table>
              <thead>
                <tr>
                  <th><input type="checkbox" data-bulk-select-target="selectAll"></th>
                  <th>Hostname</th>
                  <th>IP</th>
                  <th>OS</th>
                  <th>Arch</th>
                  <th>CPUs</th>
                  <th>Memory</th>
                </tr>
              </thead>
              <tbody>
                <% @discovered.each do |minion| %>
                  <tr>
                    <td>
                      <input type="checkbox" name="hostnames[]"
                             value="<%= minion[:hostname] %>"
                             data-bulk-select-target="checkbox">
                    </td>
                    <td><%= minion[:hostname] %></td>
                    <td><%= minion[:ip] %></td>
                    <td><%= minion[:os] %> <%= minion[:os_release] %></td>
                    <td><%= minion[:arch] %></td>
                    <td><%= minion[:num_cpus] %></td>
                    <td><%= number_to_human_size(minion[:mem_total].to_i * 1.megabyte) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
        <div class="flex justify-end gap-2 p-4 border-t">
          <button type="button" data-action="modal#close"
                  class="btn-secondary">Cancel</button>
          <button type="submit" class="btn-primary">
            Import Selected
          </button>
        </div>
      <% end %>
    <% end %>
  <% end %>
<% end %>
```

#### Node Show Page

**Remove:**
- Agent version display
- Agent update button
- Download uninstall script link
- Agent-specific conditional blocks (`@node.agent_push?`)

**Update:**
- Status badge to use `salt_status` with appropriate colors:
  - `connected` → green (polar-green)
  - `disconnected` → red (dust-red)
  - `pending` → yellow (sunrise-yellow)
  - `unknown` → gray (neutral)
- Keep Collect, Benchmark, Edit, Delete buttons

#### Overview Tab

Replace agent info section with Salt minion info:
- Minion ID (hostname)
- Salt status badge
- Last seen timestamp
- Source (manual/csv/salt_discovery)

### 5. Testing

#### New Tests

| File | Description |
|------|-------------|
| `spec/services/salt/minion_discovery_service_spec.rb` | Discovery logic, deduplication, error handling |
| `spec/requests/nodes/discover_spec.rb` | Discover and import_minions actions |

#### Updated Tests

| File | Changes |
|------|---------|
| `spec/models/node_spec.rb` | Add `salt_status` enum tests, update `online?` tests, add `:salt_discovery` source |
| `spec/services/salt/presence_check_service_spec.rb` | Update to verify `salt_status` column updates |
| `spec/system/node_management_spec.rb` | Remove agent button assertions, add discovery modal |
| `spec/requests/nodes_spec.rb` | Remove agent-related action tests |

#### Deleted Tests

Specs for any removed controllers, jobs, and models.

### 6. Error Handling

| Scenario | Behavior |
|----------|----------|
| Salt API unreachable during discovery | Show error in modal, suggest checking Salt API config |
| Salt API unreachable during presence check | Keep existing `salt_status` values unchanged (don't flip to disconnected on API error) |
| Duplicate hostname during import | Skip with error message, continue importing others |
| Salt API auth failure | Log error, show "Authentication failed" message |

## Implementation Phases

### Phase 1: Database & Model
- Migration: add `salt_status` column
- Node model: add `salt_status` enum, `:salt_discovery` source, update `online?`
- Update `Salt::PresenceCheckService` to set `salt_status`

### Phase 2: Agent Code Removal
- Delete all files listed in Section 1
- Remove routes
- Update sidebar
- Clean up `ApplicationCable::Connection`

### Phase 3: Salt Discovery Service
- Implement `Salt::MinionDiscoveryService`
- Add `get_minions` to `SaltApiClient`
- Add `discover` and `import_minions` controller actions
- Add routes

### Phase 4: Frontend Updates
- Update nodes index table (columns, actions, discovery button)
- Discovery modal view
- Update node show page (remove agent UI, add Salt status)
- Update overview tab
- Status badge color mapping

### Phase 5: Testing
- Write new specs
- Update existing specs
- Delete obsolete specs
- Run full suite: `bin/rspec` + `bin/rubocop`

## Risks

| Risk | Mitigation |
|------|------------|
| Removing agent code breaks existing features | Agent services were never implemented (missing classes), so no runtime breakage |
| Salt API unavailable | Discovery gracefully fails with error message; presence check preserves last known status |
| Existing nodes with agent_push source | Keep enum value, existing records unaffected |
| DB columns left unused | Document for future cleanup migration |
