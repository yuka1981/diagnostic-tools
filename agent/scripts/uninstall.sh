#!/bin/bash
#
# HPC Agent Uninstallation Script
# Removes the hpc-agent binary, service, and configuration
#
# Usage:
#   ./uninstall.sh [--keep-config]
#

set -euo pipefail

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/hpc-agent"
SERVICE_NAME="hpc-agent"
KEEP_CONFIG=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--keep-config]"
            echo "  --keep-config  Keep configuration files in $CONFIG_DIR"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Stop and disable service
log_info "Stopping $SERVICE_NAME service..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true

# Remove service file
service_file="/etc/systemd/system/${SERVICE_NAME}.service"
if [[ -f "$service_file" ]]; then
    log_info "Removing service file: $service_file"
    rm -f "$service_file"
    systemctl daemon-reload
fi

# Remove binary
binary_path="$INSTALL_DIR/hpc-agent"
if [[ -f "$binary_path" ]]; then
    log_info "Removing binary: $binary_path"
    rm -f "$binary_path"
fi

# Remove SELinux context if semanage is available
if command -v semanage >/dev/null 2>&1; then
    log_info "Removing SELinux file context..."
    semanage fcontext -d "$binary_path" 2>/dev/null || true
fi

# Remove configuration
if [[ "$KEEP_CONFIG" == "false" ]]; then
    if [[ -d "$CONFIG_DIR" ]]; then
        log_info "Removing configuration directory: $CONFIG_DIR"
        rm -rf "$CONFIG_DIR"
    fi
else
    log_info "Keeping configuration in: $CONFIG_DIR"
fi

log_info "HPC Agent uninstalled successfully"
