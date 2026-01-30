# BMC Out-of-Band Management Re-Design

**Date:** 2026-01-30
**Status:** Draft
**Supersedes:** 2026-01-26-bmc-oob-management-design.md

## Overview

Re-design of the BMC Out-of-Band management feature to align with the project's migration from standalone Go agents to Salt Stack. The original design specified a dedicated Go binary (`qis-bmc-collector`) on the admin node. This re-design replaces it with a Salt runner module, drops the Prometheus metrics stack in favor of TimescaleDB on PostgreSQL, and keeps the full UI scope.

## Key Changes from Original Design

| Aspect | Original | Re-Design |
|--------|----------|-----------|
| Collector | Standalone Go binary (`qis-bmc-collector`) | Salt runner module (`qis_bmc.py`) |
| Metrics Storage | Prometheus + Pushgateway + Grafana | TimescaleDB extension on PostgreSQL |
| Scheduling | Systemd timer | Salt schedule |
| Credential Delivery | Go binary fetches from Rails API | Salt runner fetches from Rails API |
| Data Ingest | Go binary POSTs to Rails API | Salt event bus → EventListenerService |
| BMC Protocols | Redfish + IPMI auto-detect | Redfish + IPMI auto-detect (unchanged) |
| Container Runtime | Podman for Prometheus stack | Not needed |
| Password Storage | Plaintext strings | Rails encrypted attributes |

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Rails Server                               │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                      API Layer                                  ││
│  │  GET  /api/v1/bmc/credentials        (Salt runner fetches)     ││
│  │  POST /api/v1/bmc/collect/inventory  (UI triggers)             ││
│  │  POST /api/v1/bmc/collect/sensors    (UI triggers)             ││
│  │  POST /api/v1/bmc/check_connectivity (UI triggers)             ││
│  │  GET  /api/v1/bmc/sensors/:node_id   (chart data)              ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Services                                                       ││
│  │  Bmc::SensorIngestionService     (Salt event → hypertable)     ││
│  │  Bmc::InventoryIngestionService  (Salt event → bmc_inventories)││
│  │  Bmc::ReconciliationService      (in-band vs OOB comparison)   ││
│  │  Bmc::SensorQueryService         (TimescaleDB → chart data)    ││
│  │  Bmc::CredentialService          (per-node + global fallback)  ││
│  │  Bmc::SaltTriggerService         (Rails → Salt API calls)      ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Salt::EventListenerService (existing, extended for qis/bmc/*) ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ Salt events                  │ Salt API (runner_async)
         │ (qis/bmc/sensors,            │
         │  qis/bmc/inventory)          │
         │                              │
┌────────┴──────────────────────────────┴────────┐
│              Salt Master (Admin Node)           │
│  ┌──────────────────────────────────────────┐  │
│  │  _runners/qis_bmc.py                     │  │
│  │  - collect_sensors(node=None)            │  │
│  │  - collect_inventory(node=None)          │  │
│  │  - check_connectivity(node=None)         │  │
│  │                                          │  │
│  │  Dependencies:                           │  │
│  │  - ipmitool (CLI)                        │  │
│  │  - requests (Python, for Redfish)        │  │
│  └──────────────┬───────────────────────────┘  │
└─────────────────┼──────────────────────────────┘
                  │
         ┌────────▼────────┐
         │  BMC Network    │
         │  (management)   │
         └─────────────────┘
```

### No New Binaries or Services

The re-design eliminates all new infrastructure:
- No Go binary to build, deploy, or maintain
- No Prometheus, Pushgateway, or Grafana containers
- No Podman compose files or systemd services for metrics
- Just a Salt runner module, Rails services, and a PostgreSQL extension

## Data Flows

### 1. Scheduled Sensor Collection (automatic)

Salt schedule fires → `qis_bmc.collect_sensors` runner executes on master → runner iterates over nodes with BMC credentials → queries each BMC for temperature/fan/power → fires Salt event `qis/bmc/sensors` with results → Rails `Salt::EventListenerService` picks up event → `Bmc::SensorIngestionService` writes to TimescaleDB hypertable

### 2. On-Demand Sensor Collection (manual trigger)

Admin clicks "Collect Sensors" in UI → Rails calls Salt API `runner_async` → same flow as scheduled, but for a single node or all nodes → Turbo Stream updates the UI when results arrive

### 3. Inventory Collection (manual trigger only)

Admin clicks "Collect BMC Inventory" → Rails calls Salt API `runner_async` for `qis_bmc.collect_inventory` → runner queries BMC for hardware details (CPU, memory, storage, network, BIOS, BMC info) → fires Salt event `qis/bmc/inventory` → Rails processes into `BmcInventory` snapshot → `Bmc::ReconciliationService` compares against latest `NodeState` → creates/updates `InventoryDiscrepancy` records

### 4. Credential Management

Admin configures BMC credentials in Rails UI → stored in `bmc_credentials` table (password encrypted via Rails Active Record Encryption) → Salt runner fetches credentials from Rails API when collection runs

## Data Models

### Existing Tables (kept with minor adjustments)

#### BmcCredential

```ruby
class BmcCredential < ApplicationRecord
  belongs_to :node, optional: true  # nil = global default

  encrypts :password

  enum :protocol, { auto: 0, redfish: 1, ipmi: 2 }

  # Fields:
  # - bmc_address: string (IP or hostname)
  # - username: string
  # - password: string (encrypted via Active Record Encryption)
  # - protocol: enum [:auto, :redfish, :ipmi]
  # - port: integer (443 for Redfish, 623 for IPMI)
  # - verify_ssl: boolean
  # - is_global_default: boolean
end
```

**Change from original:** Added `encrypts :password` for at-rest encryption. No schema migration needed — encryption is transparent at the model layer.

#### BmcInventory (unchanged)

```ruby
class BmcInventory < ApplicationRecord
  belongs_to :node

  enum :collection_method, { redfish: 0, ipmi: 1 }

  # Fields:
  # - processors: jsonb    [{socket, model, cores_physical, freq_base, freq_max, serial}]
  # - memory: jsonb        [{slot, size_gb, speed_mhz, manufacturer, serial, type}]
  # - storage: jsonb       [{name, capacity_bytes, model, serial, interface, health}]
  # - network: jsonb       [{name, mac, model, speed, firmware}]
  # - infiniband: jsonb    [{hca, port_state, firmware, guid}]
  # - bios: jsonb          {vendor, version, release_date}
  # - bmc_info: jsonb      {model, firmware, ip}
  # - captured_at: datetime
  # - collection_method: enum [:redfish, :ipmi]
end
```

#### InventoryDiscrepancy (unchanged)

```ruby
class InventoryDiscrepancy < ApplicationRecord
  belongs_to :node

  enum :severity, { info: 0, warning: 1, critical: 2 }

  # Fields:
  # - field_path: string      e.g., "memory.0.serial"
  # - inband_value: string
  # - bmc_value: string
  # - severity: enum [:info, :warning, :critical]
  # - resolved_at: datetime
  # - resolution_note: text
end
```

### New Table: bmc_sensor_readings (TimescaleDB hypertable)

```ruby
class CreateBmcSensorReadings < ActiveRecord::Migration[7.2]
  def change
    create_table :bmc_sensor_readings, id: false do |t|
      t.bigint :node_id, null: false
      t.string :sensor_type, null: false   # temperature, fan, power, health
      t.string :sensor_name, null: false   # cpu1, inlet, fan1, psu_total
      t.float :value, null: false
      t.string :unit, null: false          # celsius, rpm, percent, watts
      t.string :status                     # ok, warning, critical
      t.timestamptz :recorded_at, null: false
    end

    add_index :bmc_sensor_readings, [:node_id, :recorded_at]
    add_index :bmc_sensor_readings, [:sensor_type, :recorded_at]
    add_foreign_key :bmc_sensor_readings, :nodes

    # Convert to TimescaleDB hypertable
    execute "SELECT create_hypertable('bmc_sensor_readings', 'recorded_at', chunk_time_interval => INTERVAL '7 days')"

    # Enable compression after 7 days
    execute "ALTER TABLE bmc_sensor_readings SET (timescaledb.compress)"
    execute "SELECT add_compression_policy('bmc_sensor_readings', INTERVAL '7 days')"
  end
end
```

### TimescaleDB Configuration

```sql
-- Continuous aggregate for hourly averages
CREATE MATERIALIZED VIEW bmc_sensor_readings_hourly
WITH (timescaledb.continuous) AS
SELECT
  node_id,
  sensor_type,
  sensor_name,
  time_bucket('1 hour', recorded_at) AS bucket,
  AVG(value) AS avg_value,
  MIN(value) AS min_value,
  MAX(value) AS max_value,
  unit
FROM bmc_sensor_readings
GROUP BY node_id, sensor_type, sensor_name, time_bucket('1 hour', recorded_at), unit;

-- Retention policies
SELECT add_retention_policy('bmc_sensor_readings', INTERVAL '7 days');
SELECT add_retention_policy('bmc_sensor_readings_hourly', INTERVAL '90 days');

-- Refresh policy for continuous aggregate
SELECT add_continuous_aggregate_policy('bmc_sensor_readings_hourly',
  start_offset => INTERVAL '2 hours',
  end_offset => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');
```

## Salt Runner Module

### Module: `_runners/qis_bmc.py`

The runner executes on the Salt master, which has access to the BMC management network.

#### Functions

**`qis_bmc.collect_sensors(node=None)`**
- If `node` is specified, collect from that node only; otherwise collect from all configured nodes
- Fetches BMC credentials from Rails API (`GET /api/v1/bmc/credentials`)
- For each node: tries Redfish first (HTTP GET to `/redfish/v1/Chassis/1/Thermal`, `/Power`), falls back to `ipmitool sdr` if Redfish fails
- Caches the detected protocol per node to avoid re-detection on every cycle
- Fires a Salt event `qis/bmc/sensors` with the collected readings
- Returns a summary (nodes collected, failures)

**`qis_bmc.collect_inventory(node=None)`**
- Same credential/protocol logic as sensors
- Redfish: queries `/Systems`, `/Chassis`, `/Managers` endpoints for full hardware inventory
- IPMI: uses `ipmitool fru`, `ipmitool mc info`, `ipmitool lan print` to gather equivalent data
- Normalizes both protocol outputs into a common schema matching the `BmcInventory` JSONB structure
- Fires `qis/bmc/inventory` event with results

**`qis_bmc.check_connectivity(node=None)`**
- Quick check: can we reach the BMC and authenticate?
- Returns per-node status (reachable, protocol detected, any errors)
- Used by the UI to show BMC connection health

#### Dependencies

- `ipmitool` — installed on the Salt master
- Python `requests` — for Redfish REST API calls (standard library in most Salt installations)

#### Protocol Auto-Detection

```
For each node:
  1. If protocol explicitly set to "redfish" or "ipmi" → use that
  2. If protocol is "auto":
     a. Try Redfish: GET https://{bmc_address}/redfish/v1/
     b. If 200 OK → cache "redfish" for this node, use Redfish
     c. If connection refused/timeout → try IPMI
     d. Try IPMI: ipmitool -H {bmc_address} -U {user} -P {pass} mc info
     e. If success → cache "ipmi" for this node, use IPMI
     f. If both fail → report error for this node, continue to next
```

#### Salt Event Payload Format

```python
# Sensor event (qis/bmc/sensors)
{
    "node_hostname": "compute-001",
    "node_id": 42,
    "protocol": "redfish",
    "collected_at": "2026-01-30T10:00:00Z",
    "readings": [
        {"type": "temperature", "name": "cpu1", "value": 52.0, "unit": "celsius", "status": "ok"},
        {"type": "temperature", "name": "inlet", "value": 24.0, "unit": "celsius", "status": "ok"},
        {"type": "fan", "name": "fan1", "value": 4200, "unit": "rpm", "status": "ok"},
        {"type": "fan", "name": "fan1", "value": 35, "unit": "percent", "status": "ok"},
        {"type": "power", "name": "psu_total", "value": 450, "unit": "watts", "status": "ok"},
        {"type": "health", "name": "thermal", "value": 0, "unit": "status", "status": "ok"}
    ]
}

# Inventory event (qis/bmc/inventory)
{
    "node_hostname": "compute-001",
    "node_id": 42,
    "protocol": "redfish",
    "collected_at": "2026-01-30T10:00:00Z",
    "inventory": {
        "processors": [...],
        "memory": [...],
        "storage": [...],
        "network": [...],
        "infiniband": [...],
        "bios": {...},
        "bmc_info": {...}
    }
}
```

## Rails Services

### Bmc::SensorIngestionService

Receives sensor data from Salt events, writes to `bmc_sensor_readings` hypertable. Handles batch inserts for efficiency (one Salt event may contain readings from many nodes).

### Bmc::InventoryIngestionService

Receives inventory data from Salt events, creates new `BmcInventory` snapshots. Triggers reconciliation after ingestion.

### Bmc::ReconciliationService

Compares latest `BmcInventory` against latest `NodeState` for a given node. Generates `InventoryDiscrepancy` records for mismatches. Auto-resolves previously open discrepancies that no longer exist.

### Bmc::SensorQueryService

Queries TimescaleDB for chart data. Supports raw readings (last 24h) and hourly aggregates (7d/30d/90d) via the continuous aggregate view. Returns data formatted for Chartkick.

### Bmc::CredentialService

Manages credential resolution: per-node override → global default fallback. Provides credentials to Salt runner via API endpoint.

### Bmc::SaltTriggerService

Wraps Salt API calls for `runner_async`. Triggers inventory collection, sensor collection, and connectivity checks. Manages Salt schedule configuration for periodic collection interval.

## API Endpoints

### New Endpoints

```ruby
namespace :api do
  namespace :v1 do
    namespace :bmc do
      get  'credentials',        to: 'credentials#index'     # Salt runner fetches creds
      post 'collect/inventory',  to: 'collect#inventory'     # UI triggers inventory collection
      post 'collect/sensors',    to: 'collect#sensors'       # UI triggers sensor collection
      post 'check_connectivity', to: 'connectivity#check'    # UI triggers connectivity check
      get  'sensors/:node_id',   to: 'sensors#show'          # Chart data for a node
    end
  end
end
```

Salt event ingestion goes through the existing `Salt::EventListenerService` — no new API endpoint needed for data ingest.

## UI Components

### Node Detail Page — New Sections

#### 1. BMC Status Card (sidebar/right column)
- Connection status badge (connected / unreachable / not configured)
- Protocol detected (Redfish / IPMI)
- Last sensor collection timestamp
- Last inventory collection timestamp
- Discrepancy count badge (if any unresolved)
- "Collect Sensors" and "Collect Inventory" buttons (Turbo)

#### 2. Sensor Charts Section
- Temperature line chart (CPU, inlet, outlet — with warning/critical threshold lines)
- Fan speed line chart (RPM)
- Power consumption area chart (Watts)
- Current readings grid showing latest values with colored status indicators
- Time range selector: 24h / 7d / 30d / 90d
- Built with Chartkick

#### 3. BMC Inventory Section
- Tabbed interface: Processors / Memory / Storage / Network / InfiniBand / BIOS / BMC Info
- Data tables for each tab showing fields from the JSONB columns
- "Last collected" timestamp with manual collect button

#### 4. Discrepancy Panel
- Table: field path, in-band value, BMC value, severity badge (color-coded)
- "Resolve" button per row — opens a note field and marks resolved
- Filter: show all / unresolved only

### Node List Page — Enhancements
- BMC status dot (green/amber/red/gray) per node
- Discrepancy count badge on nodes with unresolved mismatches

### Settings Page — New Section
- Global BMC default credentials form
- Sensor collection interval selector (1/3/5 min)
- Connectivity test button (check all configured BMCs)

## Discrepancy Severity Levels

| Severity | Examples | Action |
|----------|----------|--------|
| **Critical** | Serial number mismatch, core count differs | Flag for manual review |
| **Warning** | BIOS version differs, speed mismatch | Visual indicator |
| **Info** | Minor naming differences | Log only |

## Hardware Fields Collected

### Via BMC

| Component | Fields |
|-----------|--------|
| **CPU** | Model, physical cores (no HT), base/max frequency, serial number, architecture |
| **Memory** | Slot, size (GB), speed (MHz), manufacturer, serial, type (DDR4/DDR5) |
| **Storage** | Name, capacity, model, serial, interface (NVMe/SAS/SATA), health status |
| **Network** | Interface name, MAC address, model, speed, firmware version |
| **InfiniBand** | HCA info, port state, firmware version, GUID |
| **BIOS** | Vendor, version, release date |
| **BMC** | Model, firmware version, IP address |

### Sensors Collected

| Type | Metrics |
|------|---------|
| **Temperature** | CPU, inlet, outlet, memory, chipset (°C) |
| **Fan** | Speed (RPM), percentage (%) |
| **Power** | Total system, per-PSU (Watts) |
| **Health** | Component status (OK/Warning/Critical) |

## Implementation Phases

### Phase 1: Foundation
- [ ] Add TimescaleDB extension to PostgreSQL
- [ ] Create `bmc_sensor_readings` hypertable migration
- [ ] Add `encrypts :password` to `BmcCredential` model
- [ ] Add enums, validations, and scopes to existing BMC models
- [ ] BMC credential management UI (settings page — global default CRUD)
- [ ] Per-node BMC credential form on node edit page

### Phase 2: Salt Runner Module
- [ ] Write `_runners/qis_bmc.py` with Redfish and IPMI support
- [ ] Protocol auto-detection with caching
- [ ] `collect_sensors`, `collect_inventory`, `check_connectivity` functions
- [ ] Deploy mechanism (Salt fileserver or manual placement)
- [ ] API endpoint for credential retrieval by the runner

### Phase 3: Data Pipeline
- [ ] Extend `Salt::EventListenerService` to handle `qis/bmc/*` events
- [ ] `Bmc::SensorIngestionService` — batch write to hypertable
- [ ] `Bmc::InventoryIngestionService` — create inventory snapshots
- [ ] `Bmc::ReconciliationService` — compare in-band vs OOB
- [ ] `Bmc::SaltTriggerService` — trigger collection from Rails
- [ ] TimescaleDB continuous aggregate and retention policies

### Phase 4: UI
- [ ] BMC status card on node detail page
- [ ] Sensor charts with Chartkick (temperature, fan, power)
- [ ] BMC inventory tabbed tables
- [ ] Discrepancy panel with resolution workflow
- [ ] Node list BMC status indicators
- [ ] Settings page: collection interval configuration

### Phase 5: Scheduling & Polish
- [ ] Configure Salt schedule for periodic sensor collection
- [ ] Interval configurable from settings UI via Salt API
- [ ] Connectivity check on credential save
- [ ] Error handling and notification for collection failures

## Open Questions

1. Should we support BMC firmware updates in a future phase?
2. Do we need email/webhook alerts for critical sensor thresholds?
3. Should discrepancy resolution require admin acknowledgment?
4. What authentication should the credential API endpoint use for the Salt runner? (API key vs Salt pillar)
