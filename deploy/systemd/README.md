# QIS BMC Systemd Services

## Installation

1. Copy service files to systemd directory:
   ```bash
   sudo cp qis-*.service qis-*.timer /etc/systemd/system/
   ```

2. Create log directories:
   ```bash
   sudo mkdir -p /var/log/qis/{prometheus,bmc-collector}
   ```

3. Reload systemd:
   ```bash
   sudo systemctl daemon-reload
   ```

4. Enable and start services:
   ```bash
   # Start Prometheus stack
   sudo systemctl enable --now qis-prometheus.service

   # Start BMC collector timer
   sudo systemctl enable --now qis-bmc-collector.timer
   ```

## Management Commands

```bash
# Check timer status
systemctl list-timers qis-bmc-collector.timer

# View collector logs
journalctl -u qis-bmc-collector.service -f

# Run collector manually
sudo systemctl start qis-bmc-collector.service

# Run collector for specific node
sudo systemctl start qis-bmc-collector@node01.service

# Check Prometheus stack status
sudo systemctl status qis-prometheus.service
```

## Configuration

The BMC collector reads configuration from `/etc/qis/bmc-collector.yml`:

```yaml
server_url: "http://localhost:3000"
api_token: "your-api-token"
prometheus_pushgateway_url: "http://localhost:9091"
log_level: "info"
```
