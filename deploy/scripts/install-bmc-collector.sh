#!/bin/bash
#
# QIS BMC Collector Installation Script
# Installs the BMC collector binary, configuration, and systemd services
#
# Usage:
#   ./install-bmc-collector.sh [path-to-binary]
#
# This script is idempotent and safe to run multiple times.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/qis"
LOG_DIR="/var/log/qis/bmc-collector"
SYSTEMD_DIR="/etc/systemd/system"
LOGROTATE_DIR="/etc/logrotate.d"

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Create directories
create_directories() {
    log_info "Creating directories..."

    if [[ ! -d /var/log/qis ]]; then
        mkdir -p /var/log/qis
        chmod 755 /var/log/qis
    fi

    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chmod 750 "$LOG_DIR"
        log_info "Created log directory: $LOG_DIR"
    else
        log_info "Log directory already exists: $LOG_DIR"
    fi

    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        chmod 755 "$CONFIG_DIR"
        log_info "Created config directory: $CONFIG_DIR"
    else
        log_info "Config directory already exists: $CONFIG_DIR"
    fi
}

# Install binary
install_binary() {
    local binary_path="${1:-./qis-bmc-collector}"

    if [[ ! -f "$binary_path" ]]; then
        log_error "Binary not found: $binary_path"
        log_info "Usage: $0 [path-to-binary]"
        log_info ""
        log_info "Example:"
        log_info "  $0 /path/to/qis-bmc-collector"
        exit 1
    fi

    log_info "Installing binary to $INSTALL_DIR..."
    cp "$binary_path" "$INSTALL_DIR/qis-bmc-collector"
    chmod 755 "$INSTALL_DIR/qis-bmc-collector"

    # Verify installation
    if "$INSTALL_DIR/qis-bmc-collector" --version &>/dev/null; then
        local version
        version=$("$INSTALL_DIR/qis-bmc-collector" --version 2>/dev/null || echo "unknown")
        log_info "Binary installed successfully (version: $version)"
    else
        log_warn "Binary installed but version check failed"
    fi
}

# Install configuration
install_config() {
    local config_file="$CONFIG_DIR/bmc-collector.yml"

    if [[ -f "$config_file" ]]; then
        log_warn "Configuration file already exists: $config_file"
        log_info "Skipping configuration installation. Edit manually if needed."
        return
    fi

    log_info "Creating default configuration..."
    cat > "$config_file" << 'EOF'
# QIS BMC Collector Configuration
# Edit this file to match your environment

# QIS Server URL
server_url: "http://localhost:3000"

# API Token for authentication
# Generate this token in the QIS web interface
api_token: "YOUR_API_TOKEN_HERE"

# Prometheus Pushgateway URL
prometheus_pushgateway_url: "http://localhost:9091"

# Log level: debug, info, warn, error
log_level: "info"

# Collection timeout in seconds
timeout: 60

# Verify SSL certificates for BMC connections
# Set to false for self-signed certificates
verify_ssl: true

# Concurrent collections (number of nodes to collect in parallel)
concurrency: 5

# Retry settings
retry_count: 3
retry_delay: 5
EOF

    chmod 600 "$config_file"
    log_info "Configuration created: $config_file"
    log_warn "IMPORTANT: Edit $config_file and set your API token"
}

# Install systemd services
install_systemd() {
    log_info "Installing systemd services..."

    local systemd_source="$DEPLOY_DIR/systemd"
    local installed=0

    # Copy service files
    for file in qis-bmc-collector.service qis-bmc-collector.timer "qis-bmc-collector@.service"; do
        if [[ -f "$systemd_source/$file" ]]; then
            cp "$systemd_source/$file" "$SYSTEMD_DIR/"
            chmod 644 "$SYSTEMD_DIR/$file"
            log_info "Installed: $file"
            ((installed++))
        else
            log_warn "Service file not found: $systemd_source/$file"
        fi
    done

    if [[ $installed -gt 0 ]]; then
        # Reload systemd
        systemctl daemon-reload
        log_info "Systemd daemon reloaded"
    else
        log_error "No systemd files were installed"
    fi
}

# Install logrotate configuration
install_logrotate() {
    log_info "Installing logrotate configuration..."

    local logrotate_source="$DEPLOY_DIR/logrotate/qis-bmc-collector"

    if [[ -f "$logrotate_source" ]]; then
        cp "$logrotate_source" "$LOGROTATE_DIR/"
        chmod 644 "$LOGROTATE_DIR/qis-bmc-collector"
        log_info "Logrotate configuration installed"
    else
        log_warn "Logrotate config not found: $logrotate_source"
    fi
}

# Enable and start services
enable_services() {
    log_info "Enabling BMC collector timer..."

    if ! systemctl is-enabled qis-bmc-collector.timer &>/dev/null; then
        systemctl enable qis-bmc-collector.timer
        log_info "Timer enabled"
    else
        log_info "Timer already enabled"
    fi

    echo
    read -p "Start the timer now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl start qis-bmc-collector.timer
        log_info "Timer started"
        echo
        systemctl status qis-bmc-collector.timer --no-pager || true
    else
        log_info "Timer not started. Start manually with: systemctl start qis-bmc-collector.timer"
    fi
}

# Show status information
show_status() {
    echo
    log_info "Installation Summary"
    echo "====================="
    echo "Binary:       $INSTALL_DIR/qis-bmc-collector"
    echo "Config:       $CONFIG_DIR/bmc-collector.yml"
    echo "Logs:         $LOG_DIR/"
    echo "Systemd:      $SYSTEMD_DIR/qis-bmc-collector.*"
    echo "Logrotate:    $LOGROTATE_DIR/qis-bmc-collector"
    echo
    log_info "Useful commands:"
    echo "  # Check timer status"
    echo "  systemctl list-timers qis-bmc-collector.timer"
    echo
    echo "  # Run collection manually"
    echo "  qis-bmc-collector inventory --config $CONFIG_DIR/bmc-collector.yml"
    echo
    echo "  # Run for specific node"
    echo "  systemctl start qis-bmc-collector@node01.service"
    echo
    echo "  # View logs"
    echo "  tail -f $LOG_DIR/collector.log"
}

# Main
main() {
    log_info "QIS BMC Collector Installation"
    echo "================================"
    echo

    check_root
    create_directories
    install_binary "${1:-./qis-bmc-collector}"
    install_config
    install_systemd
    install_logrotate
    enable_services
    show_status

    echo
    log_info "Installation complete!"
    echo
    log_warn "Next steps:"
    echo "  1. Edit $CONFIG_DIR/bmc-collector.yml with your API token"
    echo "  2. Configure BMC credentials in the QIS web interface"
    echo "  3. Verify timer: systemctl list-timers qis-bmc-collector.timer"
}

main "$@"
