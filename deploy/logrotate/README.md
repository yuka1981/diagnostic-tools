# QIS Logrotate Configuration

## Installation

1. Copy logrotate configuration files:
   ```bash
   sudo cp qis-bmc-collector qis-prometheus /etc/logrotate.d/
   ```

2. Set correct permissions:
   ```bash
   sudo chmod 644 /etc/logrotate.d/qis-*
   ```

3. Create log directories if they don't exist:
   ```bash
   sudo mkdir -p /var/log/qis/{bmc-collector,prometheus}
   sudo chmod 755 /var/log/qis
   sudo chmod 750 /var/log/qis/{bmc-collector,prometheus}
   ```

## Testing

Test the logrotate configuration without actually rotating:

```bash
# Test BMC collector logrotate
sudo logrotate -d /etc/logrotate.d/qis-bmc-collector

# Test Prometheus logrotate
sudo logrotate -d /etc/logrotate.d/qis-prometheus
```

Force rotation for testing:

```bash
sudo logrotate -f /etc/logrotate.d/qis-bmc-collector
```

## Configuration Details

### BMC Collector Logs
- **Location**: `/var/log/qis/bmc-collector/*.log`
- **Rotation**: Daily
- **Retention**: 14 days
- **Max Size**: 100MB
- **Compression**: gzip (delayed)

### Prometheus Logs
- **Location**: `/var/log/qis/prometheus/*.log`
- **Rotation**: Daily
- **Retention**: 30 days
- **Max Size**: 500MB
- **Compression**: gzip (delayed)

## Log Files

After rotation, log files will look like:

```
/var/log/qis/bmc-collector/
├── collector.log              # Current log
├── collector.log-20260126.gz  # Yesterday's log (compressed)
├── collector.log-20260125.gz  # Day before
└── ...

/var/log/qis/prometheus/
├── prometheus.log
├── prometheus.log-20260126.gz
└── ...
```

## Troubleshooting

Check logrotate status:
```bash
cat /var/lib/logrotate/status | grep qis
```

Check for errors:
```bash
sudo logrotate -v /etc/logrotate.d/qis-bmc-collector
```
