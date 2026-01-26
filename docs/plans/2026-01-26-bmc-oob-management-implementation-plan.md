# BMC Out-of-Band Management Implementation Plan

**Date:** 2026-01-26
**Design Document:** [2026-01-26-bmc-oob-management-design.md](./2026-01-26-bmc-oob-management-design.md)
**Branch:** `feature/bmc-oob-management`
**Worktree:** `/home/reid/diagnostic-tools-bmc-oob`

## Overview

This document outlines the implementation plan for adding BMC out-of-band management capabilities to the QIS diagnostic tools platform. The plan is organized into 5 phases with 28 tasks.

## Phase 1: Database Foundation (5 tasks) ✅ COMPLETE

### Task 1.1: Create BmcCredential Migration and Model ✅

**Files created:**
- `db/migrate/20260126234126_create_bmc_credentials.rb`
- `app/models/bmc_credential.rb`
- `spec/models/bmc_credential_spec.rb`
- `spec/factories/bmc_credentials.rb`
- `config/initializers/active_record_encryption.rb`

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
- [x] Migration runs and rolls back cleanly
- [x] Model validates presence of required fields
- [x] Encryption works for username and password
- [x] Only one global default allowed
- [x] RSpec tests pass (27 examples)

---

### Task 1.2: Create BmcInventory Migration and Model ✅

**Files created:**
- `db/migrate/20260126234115_create_bmc_inventories.rb`
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
- [x] Migration runs and rolls back cleanly
- [x] JSONB columns accept valid data structures
- [x] `latest` scope returns most recent inventory per node
- [x] RSpec tests pass (21 examples)

---

### Task 1.3: Create InventoryDiscrepancy Migration and Model ✅

**Files created:**
- `db/migrate/20260126234055_create_inventory_discrepancies.rb`
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
- [x] Migration runs and rolls back cleanly
- [x] `unresolved` scope filters correctly
- [x] Severity enum works as expected
- [x] RSpec tests pass (20 examples)

---

### Task 1.4: Add BMC Settings to Application Configuration ✅

**Files created/modified:**
- `db/migrate/20260126234127_add_bmc_settings_to_ssh_settings.rb`
- `app/models/ssh_setting.rb` (modified - added BMC fields)
- `spec/models/ssh_setting_spec.rb` (modified - added BMC tests)

**Implementation:**
Added to SshSetting model:
- `bmc_sensor_polling_interval`: 1, 3, or 5 minutes (default: 5)
- `bmc_collection_enabled`: boolean (default: false)
- `prometheus_pushgateway_url`: string
- `prometheus_url`: string

**Validation criteria:**
- [x] Settings can be read and written
- [x] Defaults are applied correctly
- [x] Settings persist across restarts
- [x] RSpec tests pass (22 examples)

---

### Task 1.5: Add Node BMC Associations ✅

**Files modified:**
- `app/models/node.rb`
- `spec/models/node_spec.rb`
- `spec/factories/nodes.rb`

**Implementation:**
```ruby
# Add to Node model
has_one :bmc_credential, dependent: :destroy
has_many :bmc_inventories, dependent: :destroy
has_many :inventory_discrepancies, dependent: :destroy

def bmc_credential_for_connection
  bmc_credential || BmcCredential.global_default_record
end

def latest_bmc_inventory
  bmc_inventories.order(captured_at: :desc).first
end

def unresolved_discrepancies
  inventory_discrepancies.unresolved
end
```

**Validation criteria:**
- [x] Associations work correctly
- [x] `bmc_credential_for_connection` falls back to global
- [x] Existing node tests still pass (92 examples)

---

## Phase 2: Go BMC Collector (7 tasks) ✅ COMPLETE

### Task 2.1: Create BMC Models and Interfaces ✅

**Files created:**
- `agent/core/model/bmc.go`
- `agent/core/model/bmc_test.go`
- `agent/core/ports/bmc_client.go`
- `agent/core/ports/bmc_client_test.go`

**Implementation:**
Defined data structures (prefixed with BMC to avoid conflicts):
- `BMCProcessor` (socket, model, cores, freq_base, freq_max, serial)
- `BMCMemoryModule` (slot, size_gb, speed_mhz, manufacturer, serial, type)
- `BMCStorageDrive` (name, capacity, model, serial, interface, health)
- `BMCNetworkAdapter` (name, mac, model, speed, firmware)
- `BMCInfinibandAdapter` (hca, port_state, firmware, guid)
- `BMCBIOSInfo` (vendor, version, release_date)
- `BMCControllerInfo` (model, firmware, ip)
- `BMCSensorReading` (name, value, unit, status)
- `BMCHealthSummary` (components map)
- `BMCInventory` (aggregates all components)

Defined `BMCClient` interface with 10 methods + `BMCConfig` struct.

**Validation criteria:**
- [x] All structs have proper JSON tags
- [x] Interface is comprehensive
- [x] Unit tests pass

---

### Task 2.2: Implement Redfish Client ✅

**Files created:**
- `agent/bmc/redfish/client.go`
- `agent/bmc/redfish/client_test.go`

**Dependencies:**
- `github.com/stmcginnis/gofish v0.20.0`

**Implementation:**
- Connect to Redfish service with credentials and optional SSL verification
- Implement all `BMCClient` interface methods
- Map Redfish resources to internal models
- Handle connection errors gracefully
- Detect Infiniband adapters by name/model keywords

**Validation criteria:**
- [x] Can connect to Redfish-enabled BMC (mocked)
- [x] All inventory methods return valid data
- [x] All sensor methods return readings
- [x] Error handling is robust
- [x] Unit tests with mocked responses pass (21 tests)

---

### Task 2.3: Implement IPMI Client ✅

**Files created:**
- `agent/bmc/ipmi/client.go`
- `agent/bmc/ipmi/client_test.go`
- `agent/bmc/ipmi/parser.go`
- `agent/bmc/ipmi/parser_test.go`

**Implementation:**
- Wrapper around `ipmitool` CLI with `CommandExecutor` interface for testing
- Parse `ipmitool` output into structured data (sensor, FRU, mc info, chassis status)
- Implement `BMCClient` interface methods
- Handle command execution errors gracefully
- Derive health from sensors and chassis status

**Validation criteria:**
- [x] Can execute ipmitool commands (mocked)
- [x] Output parsing is reliable
- [x] Graceful fallback when ipmitool unavailable
- [x] Unit tests pass (55+ tests, 90.1% coverage)

---

### Task 2.4: Implement Auto-Detect Client Factory ✅

**Files created:**
- `agent/bmc/client.go`
- `agent/bmc/client_test.go`

**Implementation:**
```go
func NewClient(ctx context.Context, config BMCConfig) (BMCClient, error) {
    // Uses ClientFactory interface for testability
    switch config.Protocol {
    case ProtocolRedfish:
        return newRedfishClient(ctx, config)
    case ProtocolIPMI:
        return newIPMIClient(ctx, config)
    case ProtocolAuto, "":
        // Try Redfish first, fall back to IPMI
        client, err := newRedfishClient(ctx, config)
        if err == nil {
            return client, nil
        }
        return newIPMIClient(ctx, config)
    }
}
```

**Validation criteria:**
- [x] Auto-detect tries Redfish first
- [x] Falls back to IPMI on Redfish failure
- [x] Explicit protocol selection works
- [x] Unit tests pass (17 tests)

---

### Task 2.5: Implement Prometheus Pushgateway Client ✅

**Files created:**
- `agent/bmc/metrics/prometheus.go`
- `agent/bmc/metrics/prometheus_test.go`

**Implementation:**
- Format metrics in Prometheus exposition format
- Push to Pushgateway with node labels (job=qis_bmc_collector, instance=nodeName)
- Map sensor units to metric names (temperature, fan, power, voltage, current)
- Convert status to numeric (OK=0, Warning=1, Critical=2)
- Handle push failures gracefully

**Validation criteria:**
- [x] Metrics formatted correctly
- [x] Push to Pushgateway succeeds (mocked)
- [x] Node labels applied correctly
- [x] Unit tests pass (21 tests)

---

### Task 2.6: Create BMC Collector CLI Commands ✅

**Files created:**
- `agent/cmd/bmc-collector/main.go`
- `agent/cmd/bmc-collector/config.go`
- `agent/cmd/bmc-collector/sensors.go`
- `agent/cmd/bmc-collector/inventory.go`
- `agent/cmd/bmc-collector/health.go`

**Implementation:**
```bash
# Commands
qis-bmc-collector sensors --config /etc/qis/bmc-collector.yml
qis-bmc-collector inventory --config /etc/qis/bmc-collector.yml
qis-bmc-collector inventory --node node01 --config /etc/qis/bmc-collector.yml
qis-bmc-collector health --address 192.168.1.100 --user admin --password secret
```

- Load configuration from YAML (server_url, api_token, prometheus_url)
- Fetch node list from Rails API (/api/v1/bmc/nodes)
- Collect data from each node's BMC
- Push results to appropriate destination

**Validation criteria:**
- [x] CLI commands execute correctly
- [x] Configuration loading works
- [x] Node list fetched from API
- [x] Data collected and pushed
- [x] Error handling with proper exit codes

---

### Task 2.7: Add BMC Collector Build Target ✅

**Files created:**
- `agent/Makefile`

**Files modified:**
- `agent/go.mod` (added gopkg.in/yaml.v3, github.com/stmcginnis/gofish)

**Implementation:**
```makefile
build-bmc-collector:
	go build -ldflags="-s -w" -o build/qis-bmc-collector ./cmd/bmc-collector

build: build-agent build-bmc-collector

test:
	go test ./...

lint:
	golangci-lint run
```

**Validation criteria:**
- [x] Binary builds successfully (7.4 MB)
- [x] All tests pass
- [x] golangci-lint passes for cmd/bmc-collector

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
