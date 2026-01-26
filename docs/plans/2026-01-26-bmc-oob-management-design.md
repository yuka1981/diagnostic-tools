# BMC Out-of-Band Management Design

**Date:** 2026-01-26
**Status:** Draft
**Author:** Claude (AI-assisted design)

## Overview

This document describes the design for integrating out-of-band (OOB) management capabilities into the QIS diagnostic tools platform. The feature enables hardware monitoring and inventory collection via BMC (Baseboard Management Controller) using Redfish and IPMI protocols.

## Goals

1. **Hardware Monitoring**: Collect sensor data (temperatures, fan speeds, power consumption) not accessible from the OS
2. **Extended Inventory**: Retrieve comprehensive hardware information including CPU serial numbers, storage controller details, and firmware versions
3. **Hybrid Data Model**: Combine in-band (OS-level) and out-of-band (BMC) data with discrepancy detection
4. **Prometheus Integration**: Store time-series sensor data with configurable retention

## Design Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Data Source | Hybrid (in-band + BMC) with reconciliation | Maximum visibility, catch hardware misconfigurations |
| BMC Protocol | Auto-detect (Redfish → IPMI fallback) | Support mixed fleet of servers |
| Inventory Collection | Manual trigger only | Hardware rarely changes |
| Sensor Collection | Configurable: 1/3/5 min (global setting) | Balance between freshness and BMC load |
| BMC Access | Rails/Admin node only | BMC on isolated management network |
| Collector Location | Dedicated Go binary on admin node | Network topology constraint |
| Discrepancy Handling | Visual indicator on dashboard | Non-intrusive, admin reviews when viewing node |
| Sensor Alerts | Visual only (red/yellow status) | Consistent with discrepancy handling |
| Metrics Storage | Prometheus + Pushgateway | Purpose-built for time-series data |
| Data Retention | Raw 24h → Hourly 30 days | Balance detail and storage |
| BMC Credentials | Global default + per-node override | Practical for HPC clusters |
| Visualization | Rails-native charts + optional Grafana | Integrated experience with power-user option |
| Container Runtime | Podman | Enterprise Linux compatibility |

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Rails Server                                 │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │                      API Layer                                   ││
│  │  POST /api/v1/inventory/push      (from compute agents)         ││
│  │  POST /api/v1/bmc/inventory       (from BMC collector)          ││
│  │  POST /api/v1/bmc/sensors         (sensor data → Pushgateway)   ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  ReconciliationService (compares in-band vs BMC data)           ││
│  └─────────────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────────────┘
         ▲                              ▲
         │ In-band inventory            │ BMC inventory + metrics
         │                              │
┌────────┴────────┐            ┌────────┴────────┐
│  Compute Nodes  │            │   Admin Node    │
│  ┌───────────┐  │            │  ┌───────────┐  │
│  │ qis-agent │  │            │  │    BMC    │  │
│  │ (in-band) │  │            │  │ Collector │  │
│  └───────────┘  │            │  └─────┬─────┘  │
└─────────────────┘            └────────┼────────┘
                                        │
                               ┌────────▼────────┐
                               │  BMC Network    │
                               │  (management)   │
                               └─────────────────┘
```

### Binary Components

| Binary | Location | Purpose |
|--------|----------|---------|
| `qis-agent` | Each compute node | In-band collection (existing) |
| `qis-bmc-collector` | Admin node | OOB collection for all nodes |

## Data Models

### PostgreSQL Schema

#### BmcCredential

```ruby
class BmcCredential
  belongs_to :node, optional: true  # nil = global default

  # Fields:
  # - bmc_address: string (IP or hostname)
  # - username: string (encrypted)
  # - password: string (encrypted)
  # - protocol: enum [:auto, :redfish, :ipmi]
  # - port: integer (443 for Redfish, 623 for IPMI)
  # - verify_ssl: boolean
  # - is_global_default: boolean
end
```

#### BmcInventory

```ruby
class BmcInventory
  belongs_to :node

  # Fields:
  # - processors: jsonb    # [{socket, model, cores_physical, freq_base, freq_max, serial}]
  # - memory: jsonb        # [{slot, size_gb, speed_mhz, manufacturer, serial, type}]
  # - storage: jsonb       # [{name, capacity_bytes, model, serial, interface, health}]
  # - network: jsonb       # [{name, mac, model, speed, firmware}]
  # - infiniband: jsonb    # [{hca, port_state, firmware, guid}]
  # - bios: jsonb          # {vendor, version, release_date}
  # - bmc_info: jsonb      # {model, firmware, ip}
  # - captured_at: datetime
  # - collection_method: enum [:redfish, :ipmi]
end
```

#### InventoryDiscrepancy

```ruby
class InventoryDiscrepancy
  belongs_to :node

  # Fields:
  # - field_path: string      # e.g., "memory.0.serial"
  # - inband_value: string
  # - bmc_value: string
  # - severity: enum [:info, :warning, :critical]
  # - resolved_at: datetime
  # - resolution_note: text
end
```

### Prometheus Metrics

```prometheus
# Temperature sensors
qis_bmc_temperature_celsius{node="compute-001", sensor="cpu1"} 52.0
qis_bmc_temperature_celsius{node="compute-001", sensor="inlet"} 24.0

# Fan speeds
qis_bmc_fan_rpm{node="compute-001", fan="fan1"} 4200
qis_bmc_fan_percent{node="compute-001", fan="fan1"} 35

# Power consumption
qis_bmc_power_watts{node="compute-001", psu="total"} 450

# Health status (0=OK, 1=Warning, 2=Critical)
qis_bmc_health_status{node="compute-001", component="thermal"} 0
```

## Go BMC Collector

### Command Structure

```bash
# Collect sensor data (scheduled every 1/3/5 min)
qis-bmc-collector sensors --config /etc/qis/bmc-collector.yml

# Collect hardware inventory (manual trigger via Rails)
qis-bmc-collector inventory --config /etc/qis/bmc-collector.yml

# Health check
qis-bmc-collector health
```

### Project Structure

```
agent/
├── cmd/
│   ├── agent/           # qis-agent (existing)
│   │   └── main.go
│   └── bmc-collector/   # qis-bmc-collector (new)
│       └── main.go
├── core/
│   ├── model/
│   │   ├── inventory.go      # existing in-band models
│   │   └── bmc.go            # BMC inventory + sensor models
│   └── ports/
│       ├── interfaces.go     # existing
│       └── bmc_client.go     # BMCClient interface
├── inventory/               # existing in-band collectors
├── bmc/                     # new BMC collectors
│   ├── client.go            # Auto-detect factory
│   ├── redfish/
│   │   └── client.go        # Redfish implementation (gofish)
│   ├── ipmi/
│   │   └── client.go        # IPMI implementation (ipmitool wrapper)
│   └── metrics/
│       └── prometheus.go    # Pushgateway client
└── go.mod
```

### BMC Client Interface

```go
type BMCClient interface {
    // Hardware inventory (manual trigger)
    GetProcessors(ctx context.Context) ([]Processor, error)
    GetMemoryModules(ctx context.Context) ([]MemoryModule, error)
    GetStorageDrives(ctx context.Context) ([]StorageDrive, error)
    GetNetworkAdapters(ctx context.Context) ([]NetworkAdapter, error)
    GetBIOSInfo(ctx context.Context) (*BIOSInfo, error)
    GetBMCInfo(ctx context.Context) (*BMCInfo, error)

    // Sensor data (periodic polling)
    GetTemperatures(ctx context.Context) ([]SensorReading, error)
    GetFanSpeeds(ctx context.Context) ([]SensorReading, error)
    GetPowerReadings(ctx context.Context) ([]SensorReading, error)
    GetHealthStatus(ctx context.Context) (*HealthSummary, error)

    // Connection info
    Protocol() string  // "redfish" or "ipmi"
    Close() error
}
```

## Rails API Endpoints

### New Endpoints

```ruby
namespace :api do
  namespace :v1 do
    namespace :bmc do
      get  'nodes',     to: 'nodes#index'      # Collector fetches node list + creds
      post 'inventory', to: 'inventory#push'   # Collector pushes hardware inventory
      post 'sensors',   to: 'sensors#push'     # Collector pushes sensor readings
      post 'health',    to: 'health#report'    # Collector reports its status

      # Manual trigger from UI
      post 'collect/inventory', to: 'collect#inventory'
      post 'collect/sensors',   to: 'collect#sensors'
    end
  end
end
```

## Prometheus Stack Deployment

### Podman Compose

```yaml
# podman-compose.prometheus.yml

version: '3.8'

services:
  prometheus:
    image: docker.io/prom/prometheus:v2.48.0
    container_name: qis-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z
      - ./prometheus/rules:/etc/prometheus/rules:ro,Z
      - prometheus_data:/prometheus:Z
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    networks:
      - qis-network

  pushgateway:
    image: docker.io/prom/pushgateway:v1.6.2
    container_name: qis-pushgateway
    restart: unless-stopped
    ports:
      - "9091:9091"
    networks:
      - qis-network

  grafana:
    image: docker.io/grafana/grafana:10.2.0
    container_name: qis-grafana
    restart: unless-stopped
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro,Z
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro,Z
      - grafana_data:/var/lib/grafana:Z
    networks:
      - qis-network

volumes:
  prometheus_data:
  grafana_data:

networks:
  qis-network:
    driver: bridge
```

### Systemd Services

#### Main Service

```ini
# /etc/systemd/system/qis-prometheus.service

[Unit]
Description=QIS Prometheus Stack (Podman Compose)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/qis/prometheus

StandardOutput=append:/var/log/qis/prometheus/service.log
StandardError=append:/var/log/qis/prometheus/service-error.log
SyslogIdentifier=qis-prometheus

ExecStartPre=/usr/bin/podman-compose -f podman-compose.prometheus.yml pull --quiet
ExecStart=/usr/bin/podman-compose -f podman-compose.prometheus.yml up -d
ExecStop=/usr/bin/podman-compose -f podman-compose.prometheus.yml down
ExecReload=/usr/bin/podman-compose -f podman-compose.prometheus.yml restart

TimeoutStartSec=300
TimeoutStopSec=120
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
```

#### BMC Collector Timer

```ini
# /etc/systemd/system/qis-bmc-collector.timer

[Unit]
Description=QIS BMC Collector Timer

[Timer]
OnCalendar=*:0/5
RandomizedDelaySec=30
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
```

### Logrotate Configuration

```conf
# /etc/logrotate.d/qis

/var/log/qis/*/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    dateext
    dateformat -%Y%m%d
    size 100M
    sharedscripts
    postrotate
        systemctl try-restart qis-prometheus-server-logs.service >/dev/null 2>&1 || true
        systemctl try-restart qis-pushgateway-logs.service >/dev/null 2>&1 || true
        systemctl try-restart qis-grafana-logs.service >/dev/null 2>&1 || true
    endscript
}
```

## UI Components

### Node Detail Page Sections

1. **BMC Status Card** (right column)
   - Connection info (address, protocol, last collected)
   - Health badge (OK/Warning/Critical)
   - Discrepancy warning indicator
   - Manual collect button

2. **Sensor Charts Section**
   - Temperature chart (line, with threshold lines)
   - Fan speed chart (line)
   - Power consumption chart (area)
   - Current readings grid
   - Range selector (24h / 7d / 30d)

3. **BMC Inventory Section**
   - Tabbed interface (Processors / Memory / Storage / Network / InfiniBand / BIOS)
   - Data tables for each category

4. **Discrepancy Panel**
   - List of detected discrepancies
   - Field path, in-band value, BMC value, severity badge

### Node List Enhancements

- BMC status dot (green/amber/red/gray)
- Discrepancy count badge

## Directory Structure

```
/opt/qis/
├── bmc-collector/
│   ├── systemd/
│   │   ├── qis-bmc-collector.service
│   │   └── qis-bmc-collector.timer
│   └── logrotate/
│       └── qis-bmc-collector
├── prometheus/
│   ├── podman-compose.prometheus.yml
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── rules/
│   │       └── bmc_rules.yml
│   ├── grafana/
│   │   ├── provisioning/
│   │   └── dashboards/
│   ├── systemd/
│   │   ├── qis-prometheus.service
│   │   └── qis-*-logs.service
│   └── logrotate/
│       └── qis-prometheus
└── rails/
    └── (existing Rails app)

/etc/qis/
├── bmc-collector.yml
├── bmc-collector.env
└── rails.env

/var/log/qis/
├── bmc-collector/
├── prometheus/
├── pushgateway/
└── grafana/

/usr/local/bin/
└── qis-bmc-collector
```

## Hardware Inventory Fields

### Collected via BMC

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

## Discrepancy Severity Levels

| Severity | Examples | Action |
|----------|----------|--------|
| **Critical** | Serial number mismatch, core count differs | Flag for manual review |
| **Warning** | BIOS version differs, speed mismatch | Visual indicator |
| **Info** | Minor naming differences | Log only |

## FigJam Diagrams

The following diagrams were created in FigJam:

1. BMC System Architecture
2. Data Model Relationships
3. BMC Protocol Detection Flow
4. Inventory Reconciliation Flow
5. Sensor Collection Sequence
6. Manual Inventory Collection Sequence
7. UI Component Hierarchy
8. Node Detail Page Layout
9. Settings Page Components
10. Shared UI Components

## Implementation Phases

### Phase 1: Foundation
- [ ] Database migrations for BMC tables
- [ ] BMC credential management (model, UI)
- [ ] Global settings for polling interval

### Phase 2: Go Collector
- [ ] BMC client interface with auto-detect
- [ ] Redfish implementation (using gofish)
- [ ] IPMI implementation (ipmitool wrapper)
- [ ] Pushgateway integration
- [ ] Systemd service and timer

### Phase 3: Rails Integration
- [ ] API endpoints for collector
- [ ] BmcInventory processing service
- [ ] Reconciliation service
- [ ] Prometheus query service for charts

### Phase 4: UI
- [ ] BMC status card component
- [ ] Sensor charts with Chartkick
- [ ] BMC inventory tables
- [ ] Discrepancy panel
- [ ] Node list enhancements

### Phase 5: Deployment
- [ ] Prometheus stack (Podman)
- [ ] Systemd services with logging
- [ ] Logrotate configuration
- [ ] Deployment scripts

## Open Questions

1. Should we support BMC firmware updates in a future phase?
2. Do we need email/webhook alerts for critical sensor thresholds?
3. Should discrepancy resolution require admin acknowledgment?

## References

- [DMTF Redfish Specification](https://www.dmtf.org/standards/redfish)
- [IPMI Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-home.html)
- [gofish - Go Redfish client](https://github.com/stmcginnis/gofish)
- [Prometheus Documentation](https://prometheus.io/docs/)
