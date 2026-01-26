# BMC Out-of-Band Management Implementation Plan

**Date:** 2026-01-26
**Design Document:** [2026-01-26-bmc-oob-management-design.md](./2026-01-26-bmc-oob-management-design.md)
**Branch:** `feature/bmc-oob-management`
**Worktree:** `/home/reid/diagnostic-tools-bmc-oob`

## Overview

This document outlines the implementation plan for adding BMC out-of-band management capabilities to the QIS diagnostic tools platform. The plan is organized into 5 phases with 28 tasks.

## Phase 1: Database Foundation (5 tasks)

### Task 1.1: Create BmcCredential Migration and Model

**Files to create/modify:**
- `db/migrate/YYYYMMDD_create_bmc_credentials.rb`
- `app/models/bmc_credential.rb`
- `spec/models/bmc_credential_spec.rb`
- `spec/factories/bmc_credentials.rb`

**Implementation:**
```ruby
# Migration
create_table :bmc_credentials do |t|
  t.references :node, foreign_key: true, null: true  # nil = global default
  t.string :bmc_address, null: false
  t.string :username, null: false
  t.string :password, null: false
  t.integer :protocol, default: 0  # 0=auto, 1=redfish, 2=ipmi
  t.integer :port
  t.boolean :verify_ssl, default: true
  t.boolean :is_global_default, default: false
  t.timestamps
end
add_index :bmc_credentials, :node_id, unique: true, where: 'node_id IS NOT NULL'
add_index :bmc_credentials, :is_global_default, unique: true, where: 'is_global_default = true'
```

**Validation criteria:**
- [ ] Migration runs and rolls back cleanly
- [ ] Model validates presence of required fields
- [ ] Encryption works for username and password
- [ ] Only one global default allowed
- [ ] RSpec tests pass

---

### Task 1.2: Create BmcInventory Migration and Model

**Files to create/modify:**
- `db/migrate/YYYYMMDD_create_bmc_inventories.rb`
- `app/models/bmc_inventory.rb`
- `spec/models/bmc_inventory_spec.rb`
- `spec/factories/bmc_inventories.rb`

**Implementation:**
```ruby
# Migration
create_table :bmc_inventories do |t|
  t.references :node, foreign_key: true, null: false
  t.jsonb :processors, default: []
  t.jsonb :memory, default: []
  t.jsonb :storage, default: []
  t.jsonb :network, default: []
  t.jsonb :infiniband, default: []
  t.jsonb :bios, default: {}
  t.jsonb :bmc_info, default: {}
  t.integer :collection_method  # 0=redfish, 1=ipmi
  t.datetime :captured_at, null: false
  t.timestamps
end
add_index :bmc_inventories, :node_id
add_index :bmc_inventories, :captured_at
```

**Validation criteria:**
- [ ] Migration runs and rolls back cleanly
- [ ] JSONB columns accept valid data structures
- [ ] `latest` scope returns most recent inventory per node
- [ ] RSpec tests pass

---

### Task 1.3: Create InventoryDiscrepancy Migration and Model

**Files to create/modify:**
- `db/migrate/YYYYMMDD_create_inventory_discrepancies.rb`
- `app/models/inventory_discrepancy.rb`
- `spec/models/inventory_discrepancy_spec.rb`
- `spec/factories/inventory_discrepancies.rb`

**Implementation:**
```ruby
# Migration
create_table :inventory_discrepancies do |t|
  t.references :node, foreign_key: true, null: false
  t.string :field_path, null: false
  t.string :inband_value
  t.string :bmc_value
  t.integer :severity, default: 0  # 0=info, 1=warning, 2=critical
  t.datetime :resolved_at
  t.text :resolution_note
  t.timestamps
end
add_index :inventory_discrepancies, :node_id
add_index :inventory_discrepancies, [:node_id, :resolved_at]
```

**Validation criteria:**
- [ ] Migration runs and rolls back cleanly
- [ ] `unresolved` scope filters correctly
- [ ] Severity enum works as expected
- [ ] RSpec tests pass

---

### Task 1.4: Add BMC Settings to Application Configuration

**Files to create/modify:**
- `db/migrate/YYYYMMDD_add_bmc_settings.rb`
- `app/models/setting.rb` (modify if exists, or create)
- `config/settings.yml` (default values)

**Implementation:**
Add global settings for:
- `bmc_sensor_polling_interval`: 1, 3, or 5 minutes (default: 5)
- `bmc_collection_enabled`: boolean (default: false)
- `prometheus_pushgateway_url`: string
- `prometheus_url`: string

**Validation criteria:**
- [ ] Settings can be read and written
- [ ] Defaults are applied correctly
- [ ] Settings persist across restarts

---

### Task 1.5: Add Node BMC Associations

**Files to modify:**
- `app/models/node.rb`
- `spec/models/node_spec.rb`

**Implementation:**
```ruby
# Add to Node model
has_one :bmc_credential, dependent: :destroy
has_many :bmc_inventories, dependent: :destroy
has_many :inventory_discrepancies, dependent: :destroy

def bmc_credential_for_connection
  bmc_credential || BmcCredential.global_default
end

def latest_bmc_inventory
  bmc_inventories.order(captured_at: :desc).first
end

def unresolved_discrepancies
  inventory_discrepancies.unresolved
end
```

**Validation criteria:**
- [ ] Associations work correctly
- [ ] `bmc_credential_for_connection` falls back to global
- [ ] Existing node tests still pass

---

## Phase 2: Go BMC Collector (7 tasks)

### Task 2.1: Create BMC Models and Interfaces

**Files to create:**
- `agent/core/model/bmc.go`
- `agent/core/ports/bmc_client.go`

**Implementation:**
Define data structures for:
- `Processor` (socket, model, cores, freq_base, freq_max, serial)
- `MemoryModule` (slot, size_gb, speed_mhz, manufacturer, serial, type)
- `StorageDrive` (name, capacity, model, serial, interface, health)
- `NetworkAdapter` (name, mac, model, speed, firmware)
- `InfinibandAdapter` (hca, port_state, firmware, guid)
- `BIOSInfo` (vendor, version, release_date)
- `BMCInfo` (model, firmware, ip)
- `SensorReading` (name, value, unit, status)
- `HealthSummary` (components map)

Define `BMCClient` interface with all methods.

**Validation criteria:**
- [ ] All structs have proper JSON tags
- [ ] Interface is comprehensive
- [ ] Unit tests pass

---

### Task 2.2: Implement Redfish Client

**Files to create:**
- `agent/bmc/redfish/client.go`
- `agent/bmc/redfish/client_test.go`

**Dependencies:**
- `github.com/stmcginnis/gofish`

**Implementation:**
- Connect to Redfish service with credentials
- Implement all `BMCClient` interface methods
- Map Redfish resources to internal models
- Handle connection errors gracefully

**Validation criteria:**
- [ ] Can connect to Redfish-enabled BMC
- [ ] All inventory methods return valid data
- [ ] All sensor methods return readings
- [ ] Error handling is robust
- [ ] Unit tests with mocked responses pass

---

### Task 2.3: Implement IPMI Client

**Files to create:**
- `agent/bmc/ipmi/client.go`
- `agent/bmc/ipmi/client_test.go`

**Implementation:**
- Wrapper around `ipmitool` CLI
- Parse `ipmitool` output into structured data
- Implement `BMCClient` interface methods
- Handle command execution errors

**Validation criteria:**
- [ ] Can execute ipmitool commands
- [ ] Output parsing is reliable
- [ ] Graceful fallback when ipmitool unavailable
- [ ] Unit tests pass

---

### Task 2.4: Implement Auto-Detect Client Factory

**Files to create:**
- `agent/bmc/client.go`
- `agent/bmc/client_test.go`

**Implementation:**
```go
func NewClient(ctx context.Context, config BMCConfig) (BMCClient, error) {
    if config.Protocol == "redfish" || config.Protocol == "auto" {
        client, err := redfish.NewClient(ctx, config)
        if err == nil {
            return client, nil
        }
        if config.Protocol == "redfish" {
            return nil, err
        }
    }
    return ipmi.NewClient(ctx, config)
}
```

**Validation criteria:**
- [ ] Auto-detect tries Redfish first
- [ ] Falls back to IPMI on Redfish failure
- [ ] Explicit protocol selection works
- [ ] Unit tests pass

---

### Task 2.5: Implement Prometheus Pushgateway Client

**Files to create:**
- `agent/bmc/metrics/prometheus.go`
- `agent/bmc/metrics/prometheus_test.go`

**Implementation:**
- Format metrics in Prometheus exposition format
- Push to Pushgateway with node labels
- Batch multiple sensor readings
- Handle push failures with retry

**Validation criteria:**
- [ ] Metrics formatted correctly
- [ ] Push to Pushgateway succeeds
- [ ] Node labels applied correctly
- [ ] Unit tests pass

---

### Task 2.6: Create BMC Collector CLI Commands

**Files to create:**
- `agent/cmd/bmc-collector/main.go`
- `agent/cmd/bmc-collector/sensors.go`
- `agent/cmd/bmc-collector/inventory.go`
- `agent/cmd/bmc-collector/health.go`

**Implementation:**
```bash
# Commands
qis-bmc-collector sensors --config /etc/qis/bmc-collector.yml
qis-bmc-collector inventory --config /etc/qis/bmc-collector.yml
qis-bmc-collector health
```

- Load configuration from YAML
- Fetch node list from Rails API
- Collect data from each node's BMC
- Push results to appropriate destination

**Validation criteria:**
- [ ] CLI commands execute correctly
- [ ] Configuration loading works
- [ ] Node list fetched from API
- [ ] Data collected and pushed
- [ ] Error handling with proper exit codes

---

### Task 2.7: Add BMC Collector Build Target

**Files to modify:**
- `agent/Makefile` (or create if not exists)
- `agent/go.mod` (add dependencies)

**Implementation:**
```makefile
build-bmc-collector:
	go build -o qis-bmc-collector ./cmd/bmc-collector

build-all: build-agent build-bmc-collector
```

**Validation criteria:**
- [ ] Binary builds successfully
- [ ] All tests pass
- [ ] golangci-lint passes

---

## Phase 3: Rails API and Services (6 tasks)

### Task 3.1: Create BMC Nodes API Endpoint

**Files to create:**
- `app/controllers/api/v1/bmc/nodes_controller.rb`
- `spec/requests/api/v1/bmc/nodes_spec.rb`

**Implementation:**
```ruby
# GET /api/v1/bmc/nodes
# Returns list of nodes with BMC credentials for collector
def index
  nodes = Node.includes(:bmc_credential).where.not(bmc_address: nil)
  render json: nodes.map { |n| node_with_credentials(n) }
end
```

**Validation criteria:**
- [ ] Returns nodes with BMC access
- [ ] Includes decrypted credentials
- [ ] Requires collector authentication
- [ ] RSpec tests pass

---

### Task 3.2: Create BMC Inventory Push Endpoint

**Files to create:**
- `app/controllers/api/v1/bmc/inventory_controller.rb`
- `app/services/bmc/inventory_processor.rb`
- `spec/requests/api/v1/bmc/inventory_spec.rb`
- `spec/services/bmc/inventory_processor_spec.rb`

**Implementation:**
```ruby
# POST /api/v1/bmc/inventory
def push
  result = Bmc::InventoryProcessor.call(
    node_id: params[:node_id],
    inventory_data: inventory_params,
    collection_method: params[:collection_method]
  )

  if result.success?
    render json: { status: 'ok', inventory_id: result.inventory.id }
  else
    render json: { status: 'error', message: result.error }, status: :unprocessable_entity
  end
end
```

**Validation criteria:**
- [ ] Creates BmcInventory record
- [ ] Triggers reconciliation after save
- [ ] Handles invalid data gracefully
- [ ] RSpec tests pass

---

### Task 3.3: Create Reconciliation Service

**Files to create:**
- `app/services/bmc/reconciliation_service.rb`
- `spec/services/bmc/reconciliation_service_spec.rb`

**Implementation:**
```ruby
module Bmc
  class ReconciliationService
    COMPARISON_RULES = {
      'processors.*.serial' => :critical,
      'processors.*.cores' => :critical,
      'memory.*.serial' => :critical,
      'memory.*.size_gb' => :warning,
      'bios.version' => :warning
    }.freeze

    def call(node)
      inband = node.latest_node_state
      bmc = node.latest_bmc_inventory
      return Result.success([]) unless inband && bmc

      discrepancies = compare(inband, bmc)
      save_discrepancies(node, discrepancies)
      Result.success(discrepancies)
    end
  end
end
```

**Validation criteria:**
- [ ] Compares matching fields correctly
- [ ] Creates InventoryDiscrepancy records
- [ ] Assigns correct severity levels
- [ ] Resolves old discrepancies when fixed
- [ ] RSpec tests pass

---

### Task 3.4: Create BMC Sensors Push Endpoint

**Files to create:**
- `app/controllers/api/v1/bmc/sensors_controller.rb`
- `app/services/bmc/prometheus_pusher.rb`
- `spec/requests/api/v1/bmc/sensors_spec.rb`

**Implementation:**
```ruby
# POST /api/v1/bmc/sensors
# Receives sensor data and pushes to Prometheus Pushgateway
def push
  result = Bmc::PrometheusPusher.call(
    node_id: params[:node_id],
    sensors: sensor_params
  )

  if result.success?
    render json: { status: 'ok' }
  else
    render json: { status: 'error', message: result.error }, status: :unprocessable_entity
  end
end
```

**Validation criteria:**
- [ ] Formats metrics correctly
- [ ] Pushes to Pushgateway
- [ ] Handles Pushgateway failures
- [ ] RSpec tests pass

---

### Task 3.5: Create Prometheus Query Service

**Files to create:**
- `app/services/bmc/prometheus_query_service.rb`
- `spec/services/bmc/prometheus_query_service_spec.rb`

**Implementation:**
```ruby
module Bmc
  class PrometheusQueryService
    def temperature_history(node, range: '24h')
      query = "qis_bmc_temperature_celsius{node=\"#{node.name}\"}"
      execute_range_query(query, range)
    end

    def fan_history(node, range: '24h')
      query = "qis_bmc_fan_rpm{node=\"#{node.name}\"}"
      execute_range_query(query, range)
    end

    def power_history(node, range: '24h')
      query = "qis_bmc_power_watts{node=\"#{node.name}\"}"
      execute_range_query(query, range)
    end
  end
end
```

**Validation criteria:**
- [ ] Queries Prometheus API correctly
- [ ] Parses response into chart-friendly format
- [ ] Handles Prometheus unavailability
- [ ] RSpec tests pass

---

### Task 3.6: Create Manual Collection Trigger Endpoint

**Files to create:**
- `app/controllers/api/v1/bmc/collect_controller.rb`
- `app/jobs/bmc/collect_inventory_job.rb`
- `spec/requests/api/v1/bmc/collect_spec.rb`

**Implementation:**
```ruby
# POST /api/v1/bmc/collect/inventory
def inventory
  node = Node.find(params[:node_id])
  Bmc::CollectInventoryJob.perform_later(node.id)
  render json: { status: 'queued', job_id: job.job_id }
end
```

The job triggers the collector via SSH to admin node:
```ruby
class Bmc::CollectInventoryJob < ApplicationJob
  def perform(node_id)
    # SSH to admin node and run:
    # qis-bmc-collector inventory --node #{node_id}
  end
end
```

**Validation criteria:**
- [ ] Job queued successfully
- [ ] Collector triggered via SSH
- [ ] Results received via push endpoint
- [ ] RSpec tests pass

---

## Phase 4: UI Components (6 tasks)

### Task 4.1: Create BMC Status Card Component

**Files to create:**
- `app/components/bmc/status_card_component.rb`
- `app/components/bmc/status_card_component.html.erb`
- `spec/components/bmc/status_card_component_spec.rb`

**Implementation:**
- Show BMC address and protocol
- Health status badge (OK/Warning/Critical)
- Last collected timestamp
- Discrepancy warning indicator
- Manual collect button (Turbo)

**Validation criteria:**
- [ ] Renders correctly for connected nodes
- [ ] Shows appropriate state for no BMC
- [ ] Collect button triggers job
- [ ] Component tests pass

---

### Task 4.2: Create Sensor Charts Component

**Files to create:**
- `app/components/bmc/sensor_charts_component.rb`
- `app/components/bmc/sensor_charts_component.html.erb`
- `app/javascript/controllers/sensor_chart_controller.js`
- `spec/components/bmc/sensor_charts_component_spec.rb`

**Implementation:**
- Temperature line chart with threshold lines
- Fan speed line chart
- Power consumption area chart
- Range selector (24h / 7d / 30d)
- Use Chartkick with Chart.js

**Validation criteria:**
- [ ] Charts render with data from Prometheus
- [ ] Range selector updates charts via Turbo
- [ ] Handles missing data gracefully
- [ ] Component tests pass

---

### Task 4.3: Create BMC Inventory Tables Component

**Files to create:**
- `app/components/bmc/inventory_component.rb`
- `app/components/bmc/inventory_component.html.erb`
- `app/views/bmc/inventory/_processors.html.erb`
- `app/views/bmc/inventory/_memory.html.erb`
- `app/views/bmc/inventory/_storage.html.erb`
- `app/views/bmc/inventory/_network.html.erb`
- `app/views/bmc/inventory/_infiniband.html.erb`
- `app/views/bmc/inventory/_bios.html.erb`
- `spec/components/bmc/inventory_component_spec.rb`

**Implementation:**
- Tabbed interface for inventory categories
- Data tables with sortable columns
- Show "No BMC inventory" if not collected

**Validation criteria:**
- [ ] Tabs switch content via Turbo
- [ ] Tables display JSONB data correctly
- [ ] Empty state handled
- [ ] Component tests pass

---

### Task 4.4: Create Discrepancy Panel Component

**Files to create:**
- `app/components/bmc/discrepancy_panel_component.rb`
- `app/components/bmc/discrepancy_panel_component.html.erb`
- `spec/components/bmc/discrepancy_panel_component_spec.rb`

**Implementation:**
- List unresolved discrepancies
- Show field path, in-band value, BMC value
- Severity badge (info/warning/critical)
- Resolve action with note field

**Validation criteria:**
- [ ] Lists discrepancies correctly
- [ ] Severity colors correct
- [ ] Resolve action works
- [ ] Component tests pass

---

### Task 4.5: Update Node Detail Page

**Files to modify:**
- `app/views/nodes/show.html.erb`
- `app/controllers/nodes_controller.rb`

**Implementation:**
Add sections for:
1. BMC Status Card (right column)
2. Sensor Charts Section (new tab or section)
3. BMC Inventory Section (new tab)
4. Discrepancy Panel (if any unresolved)

**Validation criteria:**
- [ ] All new sections render
- [ ] Page still performant
- [ ] Existing functionality preserved
- [ ] System specs pass

---

### Task 4.6: Update Node List with BMC Status

**Files to modify:**
- `app/views/nodes/_node.html.erb` (or list partial)
- `app/controllers/nodes_controller.rb`

**Implementation:**
- Add BMC status indicator dot
- Add discrepancy count badge
- Color coding: green (OK), amber (warning), red (critical), gray (no BMC)

**Validation criteria:**
- [ ] Status indicators render correctly
- [ ] Discrepancy count accurate
- [ ] Performance acceptable with many nodes
- [ ] System specs pass

---

## Phase 5: Deployment (4 tasks)

### Task 5.1: Create Prometheus Stack Configuration

**Files to create:**
- `deploy/prometheus/podman-compose.prometheus.yml`
- `deploy/prometheus/prometheus/prometheus.yml`
- `deploy/prometheus/prometheus/rules/bmc_rules.yml`
- `deploy/prometheus/grafana/provisioning/datasources/prometheus.yml`
- `deploy/prometheus/grafana/dashboards/bmc-overview.json`

**Implementation:**
Per design document Prometheus stack configuration.

**Validation criteria:**
- [ ] Podman compose brings up all services
- [ ] Prometheus scrapes Pushgateway
- [ ] Grafana provisions datasource
- [ ] Dashboard loads correctly

---

### Task 5.2: Create Systemd Service Files

**Files to create:**
- `deploy/systemd/qis-prometheus.service`
- `deploy/systemd/qis-bmc-collector.service`
- `deploy/systemd/qis-bmc-collector.timer`

**Implementation:**
Per design document systemd configurations with file-based logging.

**Validation criteria:**
- [ ] Services start and stop cleanly
- [ ] Timer triggers collector correctly
- [ ] Logs written to files

---

### Task 5.3: Create Logrotate Configuration

**Files to create:**
- `deploy/logrotate/qis-bmc-collector`
- `deploy/logrotate/qis-prometheus`

**Implementation:**
Per design document logrotate configuration.

**Validation criteria:**
- [ ] Log rotation works
- [ ] Compressed logs archived
- [ ] Permissions correct

---

### Task 5.4: Create Deployment Scripts

**Files to create:**
- `deploy/scripts/install-bmc-collector.sh`
- `deploy/scripts/install-prometheus.sh`
- `deploy/scripts/configure-bmc.sh`

**Implementation:**
```bash
#!/bin/bash
# install-bmc-collector.sh

set -euo pipefail

# Install binary
cp qis-bmc-collector /usr/local/bin/
chmod +x /usr/local/bin/qis-bmc-collector

# Create directories
mkdir -p /etc/qis /var/log/qis/bmc-collector

# Install service files
cp systemd/qis-bmc-collector.* /etc/systemd/system/
cp logrotate/qis-bmc-collector /etc/logrotate.d/

# Enable and start
systemctl daemon-reload
systemctl enable --now qis-bmc-collector.timer
```

**Validation criteria:**
- [ ] Scripts run without errors
- [ ] All files installed to correct locations
- [ ] Services enabled and running
- [ ] Tested on fresh system

---

## Dependencies Between Tasks

```
Phase 1 (Database)
├── 1.1 BmcCredential ─────┐
├── 1.2 BmcInventory ──────┼─► 1.5 Node Associations
├── 1.3 InventoryDiscrepancy┘
└── 1.4 Settings

Phase 2 (Go Collector)
├── 2.1 Models/Interfaces ──┬─► 2.2 Redfish Client ──┐
│                           └─► 2.3 IPMI Client ─────┼─► 2.4 Auto-Detect Factory
├── 2.5 Prometheus Client                            │
└── 2.6 CLI Commands ◄───────────────────────────────┴─► 2.7 Build Target

Phase 3 (Rails API) requires Phase 1
├── 3.1 Nodes API
├── 3.2 Inventory Push ─────► 3.3 Reconciliation
├── 3.4 Sensors Push
├── 3.5 Prometheus Query
└── 3.6 Manual Trigger

Phase 4 (UI) requires Phase 3
├── 4.1 Status Card
├── 4.2 Sensor Charts (requires 3.5)
├── 4.3 Inventory Tables
├── 4.4 Discrepancy Panel
├── 4.5 Node Detail (requires 4.1-4.4)
└── 4.6 Node List

Phase 5 (Deployment) can run parallel to Phase 4
├── 5.1 Prometheus Stack
├── 5.2 Systemd Services
├── 5.3 Logrotate
└── 5.4 Deploy Scripts (requires 5.1-5.3)
```

## Testing Strategy

### Unit Tests
- All models have RSpec model specs
- All services have service specs
- Go packages have `_test.go` files

### Integration Tests
- Request specs for all API endpoints
- System specs for UI workflows

### Manual Testing
- Test against real BMC (Dell iDRAC, HP iLO, etc.)
- Test IPMI fallback with older servers
- Verify Prometheus metrics collection

## Quality Gates

Before merging:
- [ ] All RSpec tests pass (`bin/rspec`)
- [ ] All Go tests pass (`go test ./...`)
- [ ] RuboCop passes (`bin/rubocop`)
- [ ] golangci-lint passes
- [ ] Brakeman security scan clean
- [ ] Manual testing against real hardware

## Rollback Plan

If issues arise:
1. Disable BMC collection via settings
2. Stop `qis-bmc-collector` timer
3. Revert migrations if needed (new tables only, no destructive changes to existing)

## Notes

- All new code should follow existing patterns in the codebase
- Use Result objects for service return values
- Follow Rails service object conventions
- Go code should follow existing agent patterns
