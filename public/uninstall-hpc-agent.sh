#!/bin/bash
#
# HPC Agent Uninstall Script
#
# This script removes the hpc-agent from the system.
# Run with sudo or as root.
#
# Usage:
#   curl -fsSL http://your-server/uninstall-hpc-agent.sh | sudo bash
#   # or
#   wget -qO- http://your-server/uninstall-hpc-agent.sh | sudo bash
#   # or download and run:
#   chmod +x uninstall-hpc-agent.sh
#   sudo ./uninstall-hpc-agent.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
BINARY_PATH="/usr/local/bin/hpc-agent"
BACKUP_PATH="/usr/local/bin/hpc-agent.bak"
SERVICE_FILE="/etc/systemd/system/hpc-agent.service"
CONFIG_DIR="/etc/hpc-agent"
TMP_FILES="/tmp/agent_bin_install /tmp/hpc-agent.service"

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Stop and disable the service
stop_service() {
    echo_info "Stopping hpc-agent service..."
    if systemctl is-active --quiet hpc-agent 2>/dev/null; then
        systemctl stop hpc-agent || echo_warn "Failed to stop service (may already be stopped)"
    else
        echo_info "Service is not running"
    fi

    echo_info "Disabling hpc-agent service..."
    if systemctl is-enabled --quiet hpc-agent 2>/dev/null; then
        systemctl disable hpc-agent || echo_warn "Failed to disable service (may already be disabled)"
    else
        echo_info "Service is not enabled"
    fi
}

# Remove files
remove_files() {
    echo_info "Removing service file..."
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        echo_info "Removed: $SERVICE_FILE"
    else
        echo_info "Service file not found: $SERVICE_FILE"
    fi

    echo_info "Removing binary..."
    if [ -f "$BINARY_PATH" ]; then
        rm -f "$BINARY_PATH"
        echo_info "Removed: $BINARY_PATH"
    else
        echo_info "Binary not found: $BINARY_PATH"
    fi

    echo_info "Removing backup binary..."
    if [ -f "$BACKUP_PATH" ]; then
        rm -f "$BACKUP_PATH"
        echo_info "Removed: $BACKUP_PATH"
    else
        echo_info "Backup binary not found: $BACKUP_PATH"
    fi

    echo_info "Removing configuration directory..."
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        echo_info "Removed: $CONFIG_DIR"
    else
        echo_info "Config directory not found: $CONFIG_DIR"
    fi

    echo_info "Removing temporary files..."
    for tmp_file in $TMP_FILES; do
        if [ -f "$tmp_file" ]; then
            rm -f "$tmp_file"
            echo_info "Removed: $tmp_file"
        fi
    done
}

# Reload systemd
reload_systemd() {
    echo_info "Reloading systemd daemon..."
    systemctl daemon-reload
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "  HPC Agent Uninstaller"
    echo "=========================================="
    echo ""

    check_root

    # Confirmation prompt (skip if piped)
    if [ -t 0 ]; then
        echo_warn "This will remove the hpc-agent from this system."
        read -p "Are you sure you want to continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo_info "Uninstall cancelled."
            exit 0
        fi
    fi

    echo ""
    stop_service
    remove_files
    reload_systemd

    echo ""
    echo "=========================================="
    echo -e "  ${GREEN}Uninstall Complete${NC}"
    echo "=========================================="
    echo ""
    echo_info "The hpc-agent has been removed from this system."
    echo ""
}

main "$@"
