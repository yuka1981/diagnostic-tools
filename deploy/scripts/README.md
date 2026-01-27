# QIS Deployment Scripts

This directory contains installation and configuration scripts for the QIS BMC Out-of-Band Management system.

## Overview

| Script | Purpose |
|--------|---------|
| `install-bmc-collector.sh` | Install the BMC collector binary, config, and systemd services |
| `install-prometheus.sh` | Install the Prometheus monitoring stack using Podman |
| `configure-bmc.sh` | Interactive tool for configuring and testing BMC connections |

## Prerequisites

### For BMC Collector
- Root access
- The `qis-bmc-collector` binary
- Network access to BMC/IPMI interfaces

### For Prometheus Stack
- Root access
- Podman installed (`dnf install podman`)
- podman-compose installed (`pip3 install podman-compose`)
- Ports 9090, 9091, and 3001 available

## Installation

### Step 1: Install Prometheus Stack (Monitoring Server)

```bash
# Navigate to the scripts directory
cd /path/to/deploy/scripts

# Run the Prometheus installation script
sudo ./install-prometheus.sh
```

This will:
- Install Prometheus, Pushgateway, and Grafana containers
- Configure systemd service for automatic startup
- Set up log rotation
- Create necessary directories

After installation:
- Prometheus: http://localhost:9090
- Pushgateway: http://localhost:9091
- Grafana: http://localhost:3001 (default: admin/admin)

### Step 2: Install BMC Collector (On Each Collection Node)

```bash
# Build or obtain the qis-bmc-collector binary first
# Then install it
sudo ./install-bmc-collector.sh /path/to/qis-bmc-collector
```

This will:
- Copy the binary to `/usr/local/bin/`
- Create default configuration in `/etc/qis/bmc-collector.yml`
- Install systemd timer for periodic collection
- Set up log rotation

### Step 3: Configure BMC Collector

1. Edit the configuration file:
   ```bash
   sudo nano /etc/qis/bmc-collector.yml
   ```

2. Set the required values:
   ```yaml
   server_url: "http://your-qis-server:3000"
   api_token: "your-api-token-here"
   prometheus_pushgateway_url: "http://prometheus-server:9091"
   ```

3. Use the configuration script to verify:
   ```bash
   sudo ./configure-bmc.sh --test
   ```

## Script Details

### install-bmc-collector.sh

Installs the BMC collector with all required components.

```bash
# Basic usage
sudo ./install-bmc-collector.sh /path/to/binary

# The script will:
# 1. Create directories (/etc/qis, /var/log/qis/bmc-collector)
# 2. Copy binary to /usr/local/bin/
# 3. Create default configuration
# 4. Install systemd services and timer
# 5. Install logrotate configuration
# 6. Enable (and optionally start) the timer
```

**Installed Files:**
- `/usr/local/bin/qis-bmc-collector` - The collector binary
- `/etc/qis/bmc-collector.yml` - Configuration file
- `/etc/systemd/system/qis-bmc-collector.service` - Main service
- `/etc/systemd/system/qis-bmc-collector.timer` - Timer for periodic runs
- `/etc/systemd/system/qis-bmc-collector@.service` - Per-node service template
- `/etc/logrotate.d/qis-bmc-collector` - Log rotation config

### install-prometheus.sh

Deploys the complete Prometheus monitoring stack using Podman containers.

```bash
# Basic usage
sudo ./install-prometheus.sh

# The script will:
# 1. Check for podman and podman-compose
# 2. Create directories (/opt/qis/prometheus, /var/log/qis/prometheus)
# 3. Copy configuration files
# 4. Pull container images
# 5. Install systemd service
# 6. Enable (and optionally start) the service
```

**Installed Components:**
- Prometheus (port 9090) - Metrics storage and querying
- Pushgateway (port 9091) - Accepts metrics from collectors
- Grafana (port 3001) - Dashboards and visualization

**Installed Files:**
- `/opt/qis/prometheus/` - All Prometheus stack files
- `/etc/systemd/system/qis-prometheus.service` - Systemd service
- `/etc/logrotate.d/qis-prometheus` - Log rotation config

### configure-bmc.sh

Interactive tool for managing BMC configuration and testing connections.

```bash
# Interactive mode
sudo ./configure-bmc.sh

# Command-line options
sudo ./configure-bmc.sh --list        # List configured nodes
sudo ./configure-bmc.sh --test        # Test API connection
sudo ./configure-bmc.sh --collect     # Collect from all nodes
sudo ./configure-bmc.sh --collect node01  # Collect from specific node
sudo ./configure-bmc.sh --sensors     # Collect sensors from all nodes
sudo ./configure-bmc.sh --status      # Show service status
```

**Features:**
- List all BMC-configured nodes
- Test API connectivity
- Test individual BMC connections
- Run ad-hoc collection jobs
- View and edit configuration
- Check service status

## Idempotency

All scripts are designed to be **idempotent** - safe to run multiple times:

- Existing configuration files are preserved
- Directories are only created if missing
- Services are not restarted unless requested
- Binary is overwritten only if provided

## Troubleshooting

### BMC Collector Issues

```bash
# Check timer status
systemctl list-timers qis-bmc-collector.timer

# View recent logs
journalctl -u qis-bmc-collector.service -f

# Run collection manually
sudo qis-bmc-collector inventory --config /etc/qis/bmc-collector.yml

# Test specific node
sudo qis-bmc-collector health --node node01 --config /etc/qis/bmc-collector.yml
```

### Prometheus Stack Issues

```bash
# Check service status
systemctl status qis-prometheus.service

# View container logs
podman logs qis-prometheus
podman logs qis-pushgateway
podman logs qis-grafana

# Restart the stack
systemctl restart qis-prometheus.service

# Check container status
podman ps -a | grep qis-
```

### Common Problems

| Problem | Solution |
|---------|----------|
| API connection failed | Check `server_url` and `api_token` in config |
| BMC connection timeout | Verify network access to BMC IPs |
| Podman pull fails | Check network/proxy settings |
| Timer not running | Ensure `systemctl enable qis-bmc-collector.timer` |
| Grafana login fails | Default is admin/admin, may need reset |

## Uninstallation

### Remove BMC Collector

```bash
# Stop and disable services
sudo systemctl stop qis-bmc-collector.timer
sudo systemctl disable qis-bmc-collector.timer

# Remove files
sudo rm /usr/local/bin/qis-bmc-collector
sudo rm /etc/systemd/system/qis-bmc-collector.*
sudo rm /etc/logrotate.d/qis-bmc-collector

# Optionally remove configuration and logs
sudo rm -rf /etc/qis
sudo rm -rf /var/log/qis/bmc-collector

sudo systemctl daemon-reload
```

### Remove Prometheus Stack

```bash
# Stop and disable service
sudo systemctl stop qis-prometheus.service
sudo systemctl disable qis-prometheus.service

# Remove containers and volumes
cd /opt/qis/prometheus
podman-compose -f podman-compose.prometheus.yml down -v

# Remove files
sudo rm -rf /opt/qis/prometheus
sudo rm /etc/systemd/system/qis-prometheus.service
sudo rm /etc/logrotate.d/qis-prometheus

# Optionally remove logs
sudo rm -rf /var/log/qis/prometheus

sudo systemctl daemon-reload
```

## Security Considerations

1. **API Token**: Store securely, rotate periodically
2. **BMC Credentials**: Managed through QIS web interface, encrypted at rest
3. **Grafana**: Change default admin password immediately
4. **Network**: Consider firewall rules for BMC network access
5. **File Permissions**: Config files are mode 600 (owner-only read)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs with `journalctl`
3. Contact your system administrator
