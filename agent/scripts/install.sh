#!/bin/bash
#
# HPC Agent Installation Script
# Installs the hpc-agent binary and configures systemd service
#
# Usage:
#   ./install.sh --node-uuid <uuid> --server <url> --token <token> [--binary <path>] [--heartbeat-interval <duration>]
#
# Requirements:
#   - Root privileges (sudo)
#   - systemd
#   - The agent binary (either local path or will be downloaded)
#

set -euo pipefail

# Default values
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/hpc-agent"
SERVICE_NAME="hpc-agent"
HEARTBEAT_INTERVAL="60s"
INVENTORY_INTERVAL="1h"
BINARY_PATH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Required:
  --node-uuid <uuid>          Node UUID (from server)
  --server <url>              Server URL (e.g., https://hpc.example.com)
  --token <token>             API authentication token

Optional:
  --binary <path>             Path to agent binary (default: download from server)
  --heartbeat-interval <dur>  Heartbeat interval (default: 60s)
  --inventory-interval <dur>  Inventory push interval (default: 1h, 0 to disable)
  --help                      Show this help message

Example:
  $0 --node-uuid abc123 --server https://hpc.example.com --token mytoken
EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-uuid)
                NODE_UUID="$2"
                shift 2
                ;;
            --server)
                SERVER_URL="$2"
                shift 2
                ;;
            --token)
                AGENT_TOKEN="$2"
                shift 2
                ;;
            --binary)
                BINARY_PATH="$2"
                shift 2
                ;;
            --heartbeat-interval)
                HEARTBEAT_INTERVAL="$2"
                shift 2
                ;;
            --inventory-interval)
                INVENTORY_INTERVAL="$2"
                shift 2
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${NODE_UUID:-}" ]]; then
        log_error "Missing required argument: --node-uuid"
        usage
    fi
    if [[ -z "${SERVER_URL:-}" ]]; then
        log_error "Missing required argument: --server"
        usage
    fi
    if [[ -z "${AGENT_TOKEN:-}" ]]; then
        log_error "Missing required argument: --token"
        usage
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "systemd is required but not found"
        exit 1
    fi

    log_info "Dependencies satisfied"
}

# Create configuration directory
create_config_dir() {
    log_info "Creating configuration directory: $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"
    chmod 750 "$CONFIG_DIR"
}

# Install the binary
install_binary() {
    local target_path="$INSTALL_DIR/hpc-agent"

    if [[ -n "$BINARY_PATH" ]]; then
        log_info "Installing agent binary from: $BINARY_PATH"
        if [[ ! -f "$BINARY_PATH" ]]; then
            log_error "Binary not found: $BINARY_PATH"
            exit 1
        fi
        cp "$BINARY_PATH" "$target_path"
    else
        log_error "Binary path is required. Use --binary <path>"
        exit 1
    fi

    # Set permissions
    chmod 755 "$target_path"
    chown root:root "$target_path"

    log_info "Agent binary installed to: $target_path"
}

# Handle SELinux context for both binary and service file
# IMPORTANT: This must be called AFTER install_service so the service file exists
configure_selinux() {
    local agent_path="$INSTALL_DIR/hpc-agent"
    local service_path="/etc/systemd/system/${SERVICE_NAME}.service"

    # Check if SELinux is available
    if ! command -v getenforce >/dev/null 2>&1; then
        log_info "SELinux not detected, skipping context configuration"
        return 0
    fi

    local selinux_status
    selinux_status=$(getenforce 2>/dev/null || echo "Disabled")

    if [[ "$selinux_status" == "Disabled" ]]; then
        log_info "SELinux is Disabled, skipping context configuration"
        return 0
    fi

    log_info "SELinux is $selinux_status, applying security contexts..."

    # Method 1: Try restorecon (uses system's file context database - preferred)
    if command -v restorecon >/dev/null 2>&1; then
        log_info "Using restorecon to apply default SELinux contexts"
        restorecon -v "$agent_path" 2>/dev/null || true
        restorecon -v "$service_path" 2>/dev/null || true
    fi

    # Method 2: For Enforcing mode, also try semanage for persistent rules
    if [[ "$selinux_status" == "Enforcing" ]]; then
        if command -v semanage >/dev/null 2>&1; then
            log_info "Using semanage for persistent SELinux context rules"
            # Add persistent file context rules (ignore errors if already exist)
            semanage fcontext -a -t bin_t "$agent_path" 2>/dev/null || \
                semanage fcontext -m -t bin_t "$agent_path" 2>/dev/null || true

            # Re-apply after adding rules
            if command -v restorecon >/dev/null 2>&1; then
                restorecon -v "$agent_path" 2>/dev/null || true
            fi
        fi
    fi

    # Method 3: Fallback to chcon if restorecon didn't work
    # Verify contexts are correct, fix with chcon if needed
    if command -v chcon >/dev/null 2>&1; then
        # Check if binary has correct context (bin_t or similar executable type)
        local binary_context
        binary_context=$(ls -Z "$agent_path" 2>/dev/null | awk '{print $1}' | cut -d: -f3)
        if [[ "$binary_context" != "bin_t" && "$binary_context" != "usr_t" ]]; then
            log_warn "Binary context is '$binary_context', setting to bin_t"
            chcon -t bin_t "$agent_path" 2>/dev/null || true
        fi

        # Check if service file has correct context (systemd_unit_file_t)
        local service_context
        service_context=$(ls -Z "$service_path" 2>/dev/null | awk '{print $1}' | cut -d: -f3)
        if [[ "$service_context" != "systemd_unit_file_t" ]]; then
            log_warn "Service file context is '$service_context', setting to systemd_unit_file_t"
            chcon -t systemd_unit_file_t "$service_path" 2>/dev/null || true
        fi
    fi

    log_info "SELinux context configuration completed"
}

# Create environment file
create_env_file() {
    local env_file="$CONFIG_DIR/agent.env"

    log_info "Creating environment file: $env_file"

    cat > "$env_file" << EOF
# HPC Agent Configuration
# Generated by install.sh on $(date -Iseconds)

NODE_UUID=${NODE_UUID}
SERVER_URL=${SERVER_URL}
AGENT_TOKEN=${AGENT_TOKEN}
HEARTBEAT_INTERVAL=${HEARTBEAT_INTERVAL}
INVENTORY_INTERVAL=${INVENTORY_INTERVAL}
EOF

    # Secure the file (contains sensitive token)
    chmod 600 "$env_file"
    chown root:root "$env_file"

    log_info "Environment file created"
}

# Install systemd service
install_service() {
    local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

    log_info "Installing systemd service: $service_file"

    cat > "$service_file" << EOF
[Unit]
Description=HPC Diagnostic Agent
Documentation=https://github.com/yuka1981/diagnostic-tools
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/hpc-agent start --node-uuid "${NODE_UUID}" --server "${SERVER_URL}" --token "${AGENT_TOKEN}" --heartbeat-interval ${HEARTBEAT_INTERVAL} --inventory-interval ${INVENTORY_INTERVAL}
Restart=always
RestartSec=10s
User=root

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${CONFIG_DIR}

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$service_file"

    log_info "Systemd service installed"
}

# Configure dmidecode permissions
configure_dmidecode() {
    if command -v dmidecode >/dev/null 2>&1; then
        local dmidecode_path
        dmidecode_path=$(which dmidecode)
        log_info "Setting SUID on dmidecode: $dmidecode_path"
        chmod 4755 "$dmidecode_path"
    else
        log_warn "dmidecode not found, some hardware info may be unavailable"
    fi
}

# Start and enable service
start_service() {
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload

    log_info "Enabling and starting $SERVICE_NAME service..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"

    # Check status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Service started successfully"
    else
        log_error "Service failed to start. Check: journalctl -u $SERVICE_NAME"
        exit 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "  HPC Agent Installation Complete"
    echo "=========================================="
    echo ""
    echo "  Binary:     $INSTALL_DIR/hpc-agent"
    echo "  Config:     $CONFIG_DIR/agent.env"
    echo "  Service:    $SERVICE_NAME"
    echo "  Node UUID:  $NODE_UUID"
    echo "  Server:     $SERVER_URL"
    echo ""
    echo "Useful commands:"
    echo "  systemctl status $SERVICE_NAME    # Check service status"
    echo "  journalctl -u $SERVICE_NAME -f    # View logs"
    echo "  systemctl restart $SERVICE_NAME   # Restart service"
    echo ""
}

# Main
main() {
    parse_args "$@"
    check_root
    check_dependencies
    create_config_dir
    install_binary
    create_env_file
    install_service
    configure_selinux  # Must be AFTER install_service so service file exists
    configure_dmidecode
    start_service
    print_summary
}

main "$@"
