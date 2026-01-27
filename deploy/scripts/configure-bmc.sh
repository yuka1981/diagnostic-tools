#!/bin/bash
#
# QIS BMC Configuration Script
# Interactive script to configure and test BMC connections for nodes
#
# Usage:
#   ./configure-bmc.sh              # Interactive mode
#   ./configure-bmc.sh --list       # List configured nodes
#   ./configure-bmc.sh --test       # Test API connection
#   ./configure-bmc.sh --collect    # Collect from all nodes
#   ./configure-bmc.sh --collect node01  # Collect from specific node
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
prompt() { echo -e "${CYAN}$1${NC}"; }

# Configuration
CONFIG_FILE="/etc/qis/bmc-collector.yml"
SERVER_URL=""
API_TOKEN=""

# Read configuration
read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Run install-bmc-collector.sh first"
        exit 1
    fi

    # Parse YAML (simple extraction, handles quoted values)
    SERVER_URL=$(grep -E '^\s*server_url:' "$CONFIG_FILE" | sed 's/.*server_url:\s*//' | tr -d '"' | tr -d "'" | xargs)
    API_TOKEN=$(grep -E '^\s*api_token:' "$CONFIG_FILE" | sed 's/.*api_token:\s*//' | tr -d '"' | tr -d "'" | xargs)

    if [[ -z "$SERVER_URL" ]]; then
        log_error "server_url not found in configuration"
        exit 1
    fi

    if [[ -z "$API_TOKEN" || "$API_TOKEN" == "YOUR_API_TOKEN_HERE" ]]; then
        log_error "API token not configured in $CONFIG_FILE"
        log_warn "Please set a valid api_token in the configuration file"
        exit 1
    fi
}

# Test API connection
test_api_connection() {
    log_info "Testing API connection to $SERVER_URL..."

    local response
    local http_code

    http_code=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        "$SERVER_URL/api/v1/health" 2>/dev/null) || true

    case "$http_code" in
        200|204)
            log_success "API connection successful (HTTP $http_code)"
            return 0
            ;;
        401|403)
            log_error "Authentication failed (HTTP $http_code)"
            log_warn "Check your api_token in $CONFIG_FILE"
            return 1
            ;;
        404)
            log_warn "Health endpoint not found (HTTP $http_code)"
            log_info "API may still be functional, trying nodes endpoint..."

            http_code=$(curl -s -w "%{http_code}" -o /dev/null \
                -H "Authorization: Bearer $API_TOKEN" \
                "$SERVER_URL/api/v1/bmc/nodes" 2>/dev/null) || true

            if [[ "$http_code" == "200" ]]; then
                log_success "API connection successful via nodes endpoint"
                return 0
            fi
            return 1
            ;;
        000)
            log_error "Connection failed - server unreachable"
            log_warn "Check your server_url in $CONFIG_FILE"
            return 1
            ;;
        *)
            log_error "API connection failed (HTTP $http_code)"
            return 1
            ;;
    esac
}

# List nodes
list_nodes() {
    log_info "Fetching nodes from API..."

    local response
    response=$(curl -s \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        "$SERVER_URL/api/v1/bmc/nodes" 2>/dev/null) || {
        log_error "Failed to fetch nodes"
        return 1
    }

    # Check for error response
    if echo "$response" | grep -q '"error"'; then
        log_error "API returned error: $response"
        return 1
    fi

    # Parse and display using Python for proper JSON handling
    echo "$response" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)

    if not data:
        print('No nodes with BMC configured')
        sys.exit(0)

    # Handle both list and dict with 'nodes' key
    nodes = data if isinstance(data, list) else data.get('nodes', data.get('data', []))

    if not nodes:
        print('No nodes with BMC configured')
        sys.exit(0)

    print()
    print(f\"{'ID':<8} {'Name':<20} {'BMC Address':<18} {'Protocol':<10} {'Status':<10}\")
    print('-' * 70)

    for node in nodes:
        node_id = str(node.get('id', 'N/A'))
        name = node.get('name', 'N/A')[:19]
        bmc_addr = node.get('bmc_address', 'N/A')[:17]
        protocol = node.get('bmc_protocol', 'auto')[:9]
        status = node.get('bmc_status', 'unknown')[:9]
        print(f'{node_id:<8} {name:<20} {bmc_addr:<18} {protocol:<10} {status:<10}')

    print()
    print(f'Total: {len(nodes)} node(s)')

except json.JSONDecodeError as e:
    print(f'Error parsing response: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || {
        log_error "Failed to parse node list"
        log_info "Raw response: $response"
        return 1
    }
}

# Test BMC connection for a specific node
test_bmc_connection() {
    local node_name="$1"

    if [[ -z "$node_name" ]]; then
        log_error "Node name required"
        return 1
    fi

    log_info "Testing BMC connection for $node_name..."

    if command -v qis-bmc-collector &>/dev/null; then
        if qis-bmc-collector health --node "$node_name" --config "$CONFIG_FILE"; then
            log_success "BMC connection test passed for $node_name"
            return 0
        else
            log_error "BMC connection test failed for $node_name"
            return 1
        fi
    else
        # Fall back to API test
        log_info "qis-bmc-collector not installed, using API test..."

        local response
        response=$(curl -s -X POST \
            -H "Authorization: Bearer $API_TOKEN" \
            -H "Content-Type: application/json" \
            "$SERVER_URL/api/v1/bmc/nodes/$node_name/test" 2>/dev/null) || {
            log_error "API test request failed"
            return 1
        }

        if echo "$response" | grep -q '"success":\s*true'; then
            log_success "BMC connection test passed for $node_name"
            return 0
        else
            log_error "BMC connection test failed: $response"
            return 1
        fi
    fi
}

# Run collection
run_collection() {
    local node_name="${1:-}"

    if ! command -v qis-bmc-collector &>/dev/null; then
        log_error "qis-bmc-collector not installed"
        log_info "Install using: ./install-bmc-collector.sh /path/to/binary"
        return 1
    fi

    if [[ -n "$node_name" ]]; then
        log_info "Running collection for $node_name..."
        if qis-bmc-collector inventory --node "$node_name" --config "$CONFIG_FILE"; then
            log_success "Collection completed for $node_name"
        else
            log_error "Collection failed for $node_name"
            return 1
        fi
    else
        log_info "Running collection for all nodes..."
        if qis-bmc-collector inventory --config "$CONFIG_FILE"; then
            log_success "Collection completed for all nodes"
        else
            log_error "Collection failed"
            return 1
        fi
    fi
}

# Collect sensors
run_sensor_collection() {
    local node_name="${1:-}"

    if ! command -v qis-bmc-collector &>/dev/null; then
        log_error "qis-bmc-collector not installed"
        return 1
    fi

    if [[ -n "$node_name" ]]; then
        log_info "Collecting sensors for $node_name..."
        qis-bmc-collector sensors --node "$node_name" --config "$CONFIG_FILE"
    else
        log_info "Collecting sensors for all nodes..."
        qis-bmc-collector sensors --config "$CONFIG_FILE"
    fi
}

# View configuration
view_config() {
    echo
    prompt "Configuration file: $CONFIG_FILE"
    echo "---"
    # Mask the API token for display
    sed 's/\(api_token:\s*\)"[^"]*"/\1"***MASKED***"/' "$CONFIG_FILE"
    echo "---"
}

# Edit configuration
edit_config() {
    local editor="${EDITOR:-nano}"

    if ! command -v "$editor" &>/dev/null; then
        editor="vi"
    fi

    log_info "Opening configuration in $editor..."
    "$editor" "$CONFIG_FILE"

    # Re-read configuration after edit
    read_config
    log_info "Configuration reloaded"
}

# Show service status
show_service_status() {
    echo
    prompt "Service Status"
    echo "==============="

    # Timer status
    echo
    echo "BMC Collector Timer:"
    if systemctl is-active qis-bmc-collector.timer &>/dev/null; then
        log_success "Timer is active"
        systemctl list-timers qis-bmc-collector.timer --no-pager 2>/dev/null || true
    else
        log_warn "Timer is not active"
    fi

    # Recent runs
    echo
    echo "Recent collection runs:"
    journalctl -u qis-bmc-collector.service --no-pager -n 5 2>/dev/null || \
        log_warn "No recent runs found"
}

# Interactive menu
show_menu() {
    echo
    prompt "${BOLD}QIS BMC Configuration${NC}"
    echo "======================"
    echo "1) List configured nodes"
    echo "2) Test API connection"
    echo "3) Test BMC connection for a node"
    echo "4) Run inventory collection for a node"
    echo "5) Run inventory collection for all nodes"
    echo "6) Collect sensors for a node"
    echo "7) View service status"
    echo "8) View configuration"
    echo "9) Edit configuration"
    echo "0) Exit"
    echo
}

# Main menu loop
main_menu() {
    while true; do
        show_menu
        read -p "Select option: " choice
        echo

        case $choice in
            1)
                list_nodes || true
                ;;
            2)
                test_api_connection || true
                ;;
            3)
                read -p "Enter node name: " node_name
                test_bmc_connection "$node_name" || true
                ;;
            4)
                read -p "Enter node name: " node_name
                run_collection "$node_name" || true
                ;;
            5)
                run_collection || true
                ;;
            6)
                read -p "Enter node name (or press Enter for all): " node_name
                run_sensor_collection "$node_name" || true
                ;;
            7)
                show_service_status
                ;;
            8)
                view_config
                ;;
            9)
                edit_config
                ;;
            0)
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_warn "Invalid option: $choice"
                ;;
        esac

        echo
        read -p "Press Enter to continue..." -r
    done
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --list              List configured nodes"
    echo "  --test              Test API connection"
    echo "  --collect [node]    Run collection (for specific node or all)"
    echo "  --sensors [node]    Collect sensors (for specific node or all)"
    echo "  --status            Show service status"
    echo "  --help              Show this help message"
    echo
    echo "Without options, starts interactive mode."
}

# Main
main() {
    # Parse command line arguments
    case "${1:-}" in
        --help|-h)
            show_usage
            exit 0
            ;;
        --list)
            read_config
            list_nodes
            ;;
        --test)
            read_config
            test_api_connection
            ;;
        --collect)
            read_config
            run_collection "${2:-}"
            ;;
        --sensors)
            read_config
            run_sensor_collection "${2:-}"
            ;;
        --status)
            show_service_status
            ;;
        "")
            read_config
            main_menu
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
