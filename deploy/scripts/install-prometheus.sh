#!/bin/bash
#
# QIS Prometheus Stack Installation Script
# Installs Prometheus, Pushgateway, and Grafana using Podman
#
# Usage:
#   ./install-prometheus.sh
#
# This script is idempotent and safe to run multiple times.
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
INSTALL_DIR="/opt/qis/prometheus"
LOG_DIR="/var/log/qis/prometheus"
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

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing=0

    if ! command -v podman &>/dev/null; then
        log_error "Podman is not installed"
        log_info "Install with: dnf install podman"
        ((missing++))
    else
        local podman_version
        podman_version=$(podman --version 2>/dev/null | awk '{print $3}')
        log_info "Podman version: $podman_version"
    fi

    if ! command -v podman-compose &>/dev/null; then
        log_warn "podman-compose not found"
        log_info "Attempting to install via pip..."

        if command -v pip3 &>/dev/null; then
            pip3 install podman-compose || {
                log_error "Failed to install podman-compose"
                ((missing++))
            }
        else
            log_error "pip3 not found. Install podman-compose manually."
            log_info "Install with: pip3 install podman-compose"
            ((missing++))
        fi
    else
        local compose_version
        compose_version=$(podman-compose --version 2>/dev/null | head -1)
        log_info "podman-compose: $compose_version"
    fi

    if [[ $missing -gt 0 ]]; then
        log_error "Missing $missing dependencies. Please install them and retry."
        exit 1
    fi

    log_info "All dependencies satisfied"
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

    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        log_info "Created install directory: $INSTALL_DIR"
    else
        log_info "Install directory already exists: $INSTALL_DIR"
    fi
}

# Copy Prometheus stack files
install_prometheus_stack() {
    log_info "Installing Prometheus stack configuration..."

    local prometheus_source="$DEPLOY_DIR/prometheus"

    if [[ ! -d "$prometheus_source" ]]; then
        log_error "Prometheus source directory not found: $prometheus_source"
        exit 1
    fi

    # Copy compose file and configuration directories
    cp "$prometheus_source/podman-compose.prometheus.yml" "$INSTALL_DIR/"
    cp -r "$prometheus_source/prometheus" "$INSTALL_DIR/"
    cp -r "$prometheus_source/grafana" "$INSTALL_DIR/"

    # Set permissions
    chmod 644 "$INSTALL_DIR/podman-compose.prometheus.yml"
    find "$INSTALL_DIR/prometheus" -type f -exec chmod 644 {} \;
    find "$INSTALL_DIR/prometheus" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR/grafana" -type f -exec chmod 644 {} \;
    find "$INSTALL_DIR/grafana" -type d -exec chmod 755 {} \;

    log_info "Prometheus stack files installed to $INSTALL_DIR"

    # List installed files
    log_info "Installed files:"
    find "$INSTALL_DIR" -type f | while read -r file; do
        echo "  $file"
    done
}

# Install systemd service
install_systemd() {
    log_info "Installing systemd service..."

    local systemd_source="$DEPLOY_DIR/systemd/qis-prometheus.service"

    if [[ -f "$systemd_source" ]]; then
        cp "$systemd_source" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/qis-prometheus.service"
        systemctl daemon-reload
        log_info "Systemd service installed"
    else
        log_warn "Service file not found: $systemd_source"
    fi
}

# Install logrotate configuration
install_logrotate() {
    log_info "Installing logrotate configuration..."

    local logrotate_source="$DEPLOY_DIR/logrotate/qis-prometheus"

    if [[ -f "$logrotate_source" ]]; then
        cp "$logrotate_source" "$LOGROTATE_DIR/"
        chmod 644 "$LOGROTATE_DIR/qis-prometheus"
        log_info "Logrotate configuration installed"
    else
        log_warn "Logrotate config not found: $logrotate_source"
    fi
}

# Pull container images
pull_images() {
    log_info "Pulling container images..."
    log_info "This may take several minutes on first run..."

    cd "$INSTALL_DIR"

    if podman-compose -f podman-compose.prometheus.yml pull; then
        log_info "Images pulled successfully"
    else
        log_warn "Some images may have failed to pull. Check connectivity."
    fi
}

# Enable and start services
enable_services() {
    log_info "Enabling Prometheus service..."

    if ! systemctl is-enabled qis-prometheus.service &>/dev/null; then
        systemctl enable qis-prometheus.service
        log_info "Service enabled"
    else
        log_info "Service already enabled"
    fi

    echo
    read -p "Start Prometheus stack now? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Starting Prometheus stack..."
        systemctl start qis-prometheus.service

        log_info "Waiting for services to start..."
        sleep 10

        echo
        systemctl status qis-prometheus.service --no-pager || true
    else
        log_info "Stack not started. Start manually with: systemctl start qis-prometheus.service"
    fi
}

# Check service health
check_health() {
    log_info "Checking service health..."

    local services=(
        "Prometheus:9090"
        "Pushgateway:9091"
        "Grafana:3001"
    )

    for service in "${services[@]}"; do
        local name="${service%%:*}"
        local port="${service##*:}"

        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/-/healthy" 2>/dev/null | grep -q "200\|204"; then
            log_info "$name (port $port): healthy"
        elif curl -s -o /dev/null "http://localhost:$port" 2>/dev/null; then
            log_info "$name (port $port): responding"
        else
            log_warn "$name (port $port): not responding yet"
        fi
    done
}

# Show access information
show_access_info() {
    echo
    log_info "Installation Summary"
    echo "====================="
    echo "Install dir:  $INSTALL_DIR"
    echo "Logs:         $LOG_DIR"
    echo "Systemd:      $SYSTEMD_DIR/qis-prometheus.service"
    echo "Logrotate:    $LOGROTATE_DIR/qis-prometheus"
    echo
    log_info "Access URLs:"
    echo "  Prometheus:  http://localhost:9090"
    echo "  Pushgateway: http://localhost:9091"
    echo "  Grafana:     http://localhost:3001"
    echo
    log_info "Default Grafana credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
    echo
    log_warn "IMPORTANT: Change the Grafana admin password on first login!"
    echo
    log_info "Useful commands:"
    echo "  # Check status"
    echo "  systemctl status qis-prometheus.service"
    echo
    echo "  # View logs"
    echo "  journalctl -u qis-prometheus.service -f"
    echo
    echo "  # Restart stack"
    echo "  systemctl restart qis-prometheus.service"
    echo
    echo "  # View container logs"
    echo "  podman logs qis-prometheus"
    echo "  podman logs qis-pushgateway"
    echo "  podman logs qis-grafana"
}

# Main
main() {
    log_info "QIS Prometheus Stack Installation"
    echo "===================================="
    echo

    check_root
    check_dependencies
    create_directories
    install_prometheus_stack
    install_systemd
    install_logrotate
    pull_images
    enable_services

    # Only check health if service was started
    if systemctl is-active qis-prometheus.service &>/dev/null; then
        check_health
    fi

    show_access_info

    echo
    log_info "Installation complete!"
}

main "$@"
