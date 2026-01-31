#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Salt Module Deployment - Interactive Setup Script
# ==============================================================================
# Guides beginners through configuring Ansible variables and credentials
# for the Salt master/minion deployment.
# ==============================================================================

# --- Script directory (resolve symlinks) --------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Color definitions --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Color

# --- Paths to generated files -------------------------------------------------
INVENTORY_FILE="${SCRIPT_DIR}/inventory/hosts.ini"
MASTER_VARS_FILE="${SCRIPT_DIR}/inventory/group_vars/salt_master/main.yml"
VAULT_FILE="${SCRIPT_DIR}/inventory/group_vars/salt_master/vault.yml"
VAULT_EXAMPLE="${SCRIPT_DIR}/inventory/group_vars/salt_master/vault.yml.example"
MINION_VARS_FILE="${SCRIPT_DIR}/inventory/group_vars/salt_minions.yml"
ANSIBLE_CFG="${SCRIPT_DIR}/ansible.cfg"

# --- Total steps --------------------------------------------------------------
TOTAL_STEPS=7

# ==============================================================================
# Helper functions
# ==============================================================================

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*"; }

step_header() {
    local step_num="$1"; shift
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Step ${step_num} of ${TOTAL_STEPS}: $*${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Prompt for input with a default value. Stores result in REPLY.
# Usage: prompt_with_default "Prompt text" "default_value"
prompt_with_default() {
    local prompt_text="$1"
    local default_val="${2:-}"
    local user_input

    if [[ -n "$default_val" ]]; then
        echo -en "${CYAN}  ${prompt_text} [${default_val}]: ${NC}"
    else
        echo -en "${CYAN}  ${prompt_text}: ${NC}"
    fi
    read -r user_input
    REPLY="${user_input:-$default_val}"
}

# Prompt for a secret (no echo). Stores result in REPLY.
prompt_secret() {
    local prompt_text="$1"
    local user_input

    echo -en "${CYAN}  ${prompt_text}: ${NC}"
    read -rs user_input
    echo ""
    REPLY="$user_input"
}

# Ask yes/no question. Returns 0 for yes, 1 for no.
# Usage: ask_yes_no "Question?" [default: y|n]
ask_yes_no() {
    local prompt_text="$1"
    local default="${2:-y}"
    local yn_hint

    if [[ "$default" == "y" ]]; then
        yn_hint="Y/n"
    else
        yn_hint="y/N"
    fi

    echo -en "${CYAN}  ${prompt_text} [${yn_hint}]: ${NC}"
    read -r answer
    answer="${answer:-$default}"

    case "$answer" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# Validate IP address format (basic check: four octets 0-255)
validate_ip() {
    local ip="$1"
    local IFS='.'
    local -a octets
    read -ra octets <<< "$ip"

    if [[ ${#octets[@]} -ne 4 ]]; then
        return 1
    fi

    for octet in "${octets[@]}"; do
        if ! [[ "$octet" =~ ^[0-9]+$ ]] || (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done
    return 0
}

# Prompt for an IP address with validation. Stores result in REPLY.
prompt_ip() {
    local prompt_text="$1"
    local default_val="${2:-}"

    while true; do
        prompt_with_default "$prompt_text" "$default_val"
        if [[ -z "$REPLY" ]]; then
            error "IP address is required."
            continue
        fi
        if validate_ip "$REPLY"; then
            break
        else
            error "Invalid IP address format: $REPLY (expected: x.x.x.x)"
        fi
    done
}

# Prompt for a required (non-empty) value. Stores result in REPLY.
prompt_required() {
    local prompt_text="$1"
    local default_val="${2:-}"

    while true; do
        prompt_with_default "$prompt_text" "$default_val"
        if [[ -n "$REPLY" ]]; then
            break
        fi
        error "This field is required and cannot be empty."
    done
}

# Back up a file if it exists. Returns 0 if backed up, 1 if not.
backup_file() {
    local filepath="$1"
    if [[ -f "$filepath" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d%H%M%S)"
        local backup_path="${filepath}.bak.${timestamp}"
        cp "$filepath" "$backup_path"
        info "Backed up: ${filepath} -> ${backup_path}"
        return 0
    fi
    return 1
}

# Atomically write content to a file via temp file + mv.
# Usage: atomic_write "filepath" "content"
atomic_write() {
    local filepath="$1"
    local content="$2"
    local dir
    dir="$(dirname "$filepath")"
    mkdir -p "$dir"

    local tmpfile
    tmpfile="$(mktemp "${dir}/.tmp.XXXXXX")"
    echo "$content" > "$tmpfile"
    mv "$tmpfile" "$filepath"
}

# Check if a file exists and ask whether to overwrite.
# Returns 0 if we should proceed (write), 1 if skip.
check_overwrite() {
    local filepath="$1"
    local label="${2:-$filepath}"

    if [[ -f "$filepath" ]]; then
        warn "${label} already exists."
        if ask_yes_no "Overwrite it? (existing file will be backed up)" "y"; then
            backup_file "$filepath"
            return 0
        else
            info "Skipping ${label}."
            return 1
        fi
    fi
    return 0
}

# Mask a secret string for display (show first 4 chars + asterisks).
mask_secret() {
    local secret="$1"
    if [[ ${#secret} -le 4 ]]; then
        echo "****"
    else
        echo "${secret:0:4}$(printf '*%.0s' $(seq 1 $((${#secret} - 4))))"
    fi
}

# ==============================================================================
# Banner
# ==============================================================================
show_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  +----------------------------------------------------------+"
    echo "  |                                                          |"
    echo "  |        Salt Module Deployment - Setup Wizard             |"
    echo "  |                                                          |"
    echo "  |   Configure Ansible inventory, variables, and vault      |"
    echo "  |   secrets for Salt master/minion deployment.             |"
    echo "  |                                                          |"
    echo "  +----------------------------------------------------------+"
    echo -e "${NC}"
}

# ==============================================================================
# Help
# ==============================================================================
show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Interactive setup wizard for Salt module Ansible deployment."
    echo ""
    echo "Options:"
    echo "  --help     Show this help message and exit"
    echo "  --check    Validate existing configuration without modifying anything"
    echo ""
    echo "This script guides you through configuring:"
    echo "  1. Prerequisites (ansible, ansible-vault, ssh-keygen)"
    echo "  2. SSH settings"
    echo "  3. Inventory (hosts)"
    echo "  4. Salt master variables"
    echo "  5. Salt minion variables"
    echo "  6. Vault secrets (encrypted)"
    echo "  7. Configuration verification"
    echo ""
    echo "Files created/modified (relative to ansible/):"
    echo "  inventory/hosts.ini"
    echo "  inventory/group_vars/salt_master/main.yml"
    echo "  inventory/group_vars/salt_master/vault.yml  (encrypted)"
    echo "  inventory/group_vars/salt_minions.yml"
    echo ""
}

# ==============================================================================
# Check mode: validate existing config
# ==============================================================================
run_check_mode() {
    show_banner
    echo -e "${BOLD}Running configuration check...${NC}"
    echo ""

    local issues=0

    # --- Prerequisites ---
    echo -e "${BOLD}Prerequisites:${NC}"
    for cmd in ansible ansible-vault ssh-keygen; do
        if command -v "$cmd" &>/dev/null; then
            success "$cmd found: $(command -v "$cmd")"
        else
            error "$cmd NOT found"
            (( issues++ ))
        fi
    done
    echo ""

    # --- Inventory ---
    echo -e "${BOLD}Inventory (${INVENTORY_FILE}):${NC}"
    if [[ -f "$INVENTORY_FILE" ]]; then
        success "File exists"
        if (cd "$SCRIPT_DIR" && ansible-inventory --list &>/dev/null); then
            success "Parses successfully"
        else
            error "Failed to parse inventory"
            (( issues++ ))
        fi
    else
        error "File not found"
        (( issues++ ))
    fi
    echo ""

    # --- Salt master vars ---
    echo -e "${BOLD}Salt master variables (${MASTER_VARS_FILE}):${NC}"
    if [[ -f "$MASTER_VARS_FILE" ]]; then
        success "File exists"
        local required_vars=("salt_master_address" "salt_gitfs_repo" "salt_gitfs_branch"
                             "salt_api_port" "salt_api_user" "salt_gitfs_token" "salt_api_password"
                             "rails_webhook_url")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}:" "$MASTER_VARS_FILE" 2>/dev/null; then
                success "  ${var} defined"
            else
                warn "  ${var} not found"
            fi
        done
    else
        error "File not found"
        (( issues++ ))
    fi
    echo ""

    # --- Vault ---
    echo -e "${BOLD}Vault (${VAULT_FILE}):${NC}"
    if [[ -f "$VAULT_FILE" ]]; then
        success "File exists"
        if head -1 "$VAULT_FILE" | grep -q '^\$ANSIBLE_VAULT;'; then
            success "File is encrypted"
        else
            warn "File exists but is NOT encrypted"
        fi
    else
        warn "File not found (secrets not configured)"
        (( issues++ ))
    fi
    echo ""

    # --- Minion vars ---
    echo -e "${BOLD}Salt minion variables (${MINION_VARS_FILE}):${NC}"
    if [[ -f "$MINION_VARS_FILE" ]]; then
        success "File exists"
        if grep -q "^salt_master_address:" "$MINION_VARS_FILE" 2>/dev/null; then
            success "  salt_master_address defined"
        else
            warn "  salt_master_address not found"
        fi
    else
        error "File not found"
        (( issues++ ))
    fi
    echo ""

    # --- Vault password file ---
    echo -e "${BOLD}Vault password file:${NC}"
    local vault_pass_file
    vault_pass_file="$(grep 'vault_password_file' "$ANSIBLE_CFG" 2>/dev/null | awk -F= '{print $2}' | xargs)"
    vault_pass_file="${vault_pass_file/#\~/$HOME}"
    if [[ -n "$vault_pass_file" && -f "$vault_pass_file" ]]; then
        success "Found at ${vault_pass_file}"
        local perms
        perms="$(stat -c '%a' "$vault_pass_file" 2>/dev/null || stat -f '%Lp' "$vault_pass_file" 2>/dev/null)"
        if [[ "$perms" == "600" ]]; then
            success "Permissions are correct (600)"
        else
            warn "Permissions are ${perms} (expected 600)"
        fi
    else
        warn "Not found or not configured"
    fi
    echo ""

    # --- Summary ---
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [[ $issues -eq 0 ]]; then
        success "All checks passed! Configuration looks good."
    else
        warn "${issues} issue(s) found. Run this script without --check to configure."
    fi
    echo ""
}

# ==============================================================================
# Step 1: Prerequisites check
# ==============================================================================
step_prerequisites() {
    step_header 1 "Prerequisites Check"

    info "Checking required tools..."
    echo ""

    local missing=0

    for cmd in ansible ansible-vault ssh-keygen; do
        if command -v "$cmd" &>/dev/null; then
            local version_info
            case "$cmd" in
                ansible)
                    version_info="$(ansible --version 2>/dev/null | head -1)"
                    ;;
                ansible-vault)
                    version_info="$(ansible-vault --version 2>/dev/null | head -1)"
                    ;;
                ssh-keygen)
                    version_info="$(ssh-keygen -? 2>&1 | head -1 || true)"
                    ;;
            esac
            success "${cmd} found - ${version_info}"
        else
            error "${cmd} is NOT installed"
            (( missing++ ))
        fi
    done

    # Also check openssl for password generation
    if command -v openssl &>/dev/null; then
        success "openssl found (for password generation)"
    else
        warn "openssl not found - random password generation will not be available"
    fi

    echo ""
    if [[ $missing -gt 0 ]]; then
        error "Missing ${missing} required tool(s). Please install them and re-run this script."
        exit 1
    fi

    success "All prerequisites satisfied."
}

# ==============================================================================
# Step 2: SSH configuration
# ==============================================================================
step_ssh_config() {
    step_header 2 "SSH Configuration"

    info "These settings determine how Ansible connects to your target hosts."
    echo ""

    # SSH user
    local default_ssh_user="reidlin"
    prompt_required "SSH user for connecting to target hosts" "$default_ssh_user"
    SSH_USER="$REPLY"

    # SSH private key
    local default_key_path="~/.ssh/id_ed25519"
    while true; do
        prompt_with_default "Path to SSH private key" "$default_key_path"
        SSH_KEY_PATH="$REPLY"
        # Expand tilde for validation
        local expanded_path="${SSH_KEY_PATH/#\~/$HOME}"
        if [[ -f "$expanded_path" ]]; then
            success "SSH key found: ${expanded_path}"
            break
        else
            warn "File not found: ${expanded_path}"
            if ask_yes_no "Use this path anyway? (you can create the key later)" "y"; then
                break
            fi
        fi
    done

    echo ""
    success "SSH configuration: user=${SSH_USER}, key=${SSH_KEY_PATH}"
}

# ==============================================================================
# Step 3: Inventory setup
# ==============================================================================
step_inventory() {
    step_header 3 "Inventory Setup"

    info "Define the Salt master and minion hosts."
    info "The inventory file uses INI format."
    echo ""

    # --- Salt Master ---
    echo -e "  ${BOLD}Salt Master:${NC}"
    prompt_required "  Hostname" "salt-master-01"
    MASTER_HOSTNAME="$REPLY"

    prompt_ip "  IP address" "192.168.127.128"
    MASTER_IP="$REPLY"

    echo ""
    success "Salt master: ${MASTER_HOSTNAME} (${MASTER_IP})"
    echo ""

    # --- Salt Minions ---
    echo -e "  ${BOLD}Salt Minions:${NC}"
    info "Add minion hosts one at a time. Press Enter with an empty hostname to finish."
    echo ""

    MINION_ENTRIES=()
    local minion_index=1
    while true; do
        prompt_with_default "  Minion ${minion_index} hostname (blank to finish)" ""
        local hostname="$REPLY"
        if [[ -z "$hostname" ]]; then
            break
        fi

        prompt_ip "  Minion ${minion_index} IP address" ""
        local ip="$REPLY"

        MINION_ENTRIES+=("${hostname}|${ip}")
        success "  Added minion: ${hostname} (${ip})"
        echo ""
        (( minion_index++ ))
    done

    if [[ ${#MINION_ENTRIES[@]} -eq 0 ]]; then
        warn "No minions added. You can add them manually later to ${INVENTORY_FILE}."
    else
        success "${#MINION_ENTRIES[@]} minion(s) configured."
    fi

    # --- Write inventory ---
    echo ""
    if ! check_overwrite "$INVENTORY_FILE" "Inventory file"; then
        return 0
    fi

    local inventory_content=""
    inventory_content+="[salt_master]"$'\n'
    inventory_content+="${MASTER_HOSTNAME}  ansible_host=${MASTER_IP}"$'\n'
    inventory_content+=""$'\n'
    inventory_content+="[salt_minions]"$'\n'
    for entry in "${MINION_ENTRIES[@]}"; do
        local h="${entry%%|*}"
        local i="${entry##*|}"
        # Pad hostname to align ansible_host
        inventory_content+="${h}  ansible_host=${i}"$'\n'
    done
    inventory_content+=""$'\n'
    inventory_content+="[all:vars]"$'\n'
    inventory_content+="ansible_user=${SSH_USER}"$'\n'
    inventory_content+="ansible_ssh_private_key_file=${SSH_KEY_PATH}"$'\n'

    atomic_write "$INVENTORY_FILE" "$inventory_content"
    success "Inventory written to ${INVENTORY_FILE}"

    # Optional: test SSH connectivity
    echo ""
    if ask_yes_no "Test SSH connectivity to all hosts now?" "n"; then
        info "Testing SSH connectivity..."
        if (cd "$SCRIPT_DIR" && ansible all -m ping --one-line 2>&1); then
            success "SSH connectivity test passed."
        else
            warn "Some hosts may be unreachable. You can fix connectivity and re-test later."
        fi
    fi
}

# ==============================================================================
# Step 4: Salt master variables
# ==============================================================================
step_master_vars() {
    step_header 4 "Salt Master Variables"

    info "Configure settings for the Salt master node."
    echo ""

    # salt_master_address
    local default_master_addr="${MASTER_IP:-192.168.127.128}"
    prompt_required "Salt master address (IP/hostname minions use to reach master)" "$default_master_addr"
    SALT_MASTER_ADDRESS="$REPLY"

    # salt_gitfs_repo
    prompt_required "GitFS repository URL" "https://github.com/yuka1981/diagnostic-tools.git"
    SALT_GITFS_REPO="$REPLY"

    # salt_gitfs_branch
    prompt_with_default "GitFS branch" "develop"
    SALT_GITFS_BRANCH="$REPLY"

    # salt_gitfs_user
    prompt_required "GitHub username (for HTTPS GitFS auth)" "yuka1981"
    SALT_GITFS_USER="$REPLY"

    # salt_gitfs_update_interval
    prompt_with_default "GitFS update interval in seconds" "60"
    SALT_GITFS_UPDATE_INTERVAL="$REPLY"

    # salt_api_port
    prompt_with_default "Salt API port" "8000"
    SALT_API_PORT="$REPLY"

    # salt_api_user
    prompt_with_default "Salt API user" "rails_salt_user"
    SALT_API_USER="$REPLY"

    # rails_webhook_url
    prompt_required "Rails webhook URL" "https://qis.hayashi-dev.me/api/v1/salt/events"
    RAILS_WEBHOOK_URL="$REPLY"

    # salt_version
    prompt_with_default "Salt version" "3006"
    SALT_VERSION="$REPLY"

    echo ""

    # --- Write master vars ---
    if ! check_overwrite "$MASTER_VARS_FILE" "Salt master variables file"; then
        return 0
    fi

    local master_vars_content
    read -r -d '' master_vars_content <<ENDOFVARS || true
---
# Salt Master configuration (non-secret values)
# Secrets are in group_vars/salt_master/vault.yml (Ansible Vault encrypted)

salt_version: "${SALT_VERSION}"

# GitFS configuration
salt_gitfs_user: "${SALT_GITFS_USER}"
salt_gitfs_branch: "${SALT_GITFS_BRANCH}"
salt_gitfs_repo: "${SALT_GITFS_REPO}"
salt_gitfs_update_interval: ${SALT_GITFS_UPDATE_INTERVAL}

# Salt API
salt_api_port: ${SALT_API_PORT}
salt_api_ssl_cert: "/etc/salt/pki/api/cert.crt"
salt_api_ssl_key: "/etc/salt/pki/api/key.key"

# Salt API user (PAM authentication)
salt_api_user: "${SALT_API_USER}"

# Network
salt_master_address: "${SALT_MASTER_ADDRESS}"
rails_webhook_url: "${RAILS_WEBHOOK_URL}"

# References to vault-encrypted secrets
salt_gitfs_token: "{{ vault_salt_gitfs_token }}"
salt_api_password: "{{ vault_salt_api_password }}"
ENDOFVARS

    atomic_write "$MASTER_VARS_FILE" "$master_vars_content"
    success "Salt master variables written to ${MASTER_VARS_FILE}"
}

# ==============================================================================
# Step 5: Salt minion variables
# ==============================================================================
step_minion_vars() {
    step_header 5 "Salt Minion Variables"

    info "Configure settings for Salt minion nodes."
    echo ""

    local default_addr="${SALT_MASTER_ADDRESS:-192.168.127.128}"
    prompt_required "Salt master address (for minions to connect to)" "$default_addr"
    local minion_master_addr="$REPLY"

    if ! check_overwrite "$MINION_VARS_FILE" "Salt minion variables file"; then
        return 0
    fi

    local minion_vars_content
    minion_vars_content="salt_master_address: \"${minion_master_addr}\""

    atomic_write "$MINION_VARS_FILE" "$minion_vars_content"
    success "Salt minion variables written to ${MINION_VARS_FILE}"
}

# ==============================================================================
# Step 6: Vault secrets
# ==============================================================================
step_vault_secrets() {
    step_header 6 "Vault Secrets (Encrypted)"

    info "Configure secrets that will be encrypted with Ansible Vault."
    warn "These values will be stored encrypted. Never commit unencrypted secrets."
    echo ""

    # --- GitFS token ---
    echo -e "  ${BOLD}GitHub Personal Access Token (for GitFS):${NC}"
    info "This token is used by Salt to clone your Git repository."
    info "Create one at: https://github.com/settings/tokens"
    echo ""
    prompt_secret "GitHub personal access token (vault_salt_gitfs_token)"
    VAULT_GITFS_TOKEN="$REPLY"

    while [[ -z "$VAULT_GITFS_TOKEN" ]]; do
        error "Token is required for GitFS authentication."
        prompt_secret "GitHub personal access token (vault_salt_gitfs_token)"
        VAULT_GITFS_TOKEN="$REPLY"
    done
    success "GitFS token set: $(mask_secret "$VAULT_GITFS_TOKEN")"

    echo ""

    # --- API password ---
    echo -e "  ${BOLD}Salt API Password (vault_salt_api_password):${NC}"
    if command -v openssl &>/dev/null; then
        if ask_yes_no "Generate a random password using openssl?" "y"; then
            VAULT_API_PASSWORD="$(openssl rand -base64 24)"
            success "Generated random password: $(mask_secret "$VAULT_API_PASSWORD")"
        else
            prompt_secret "Enter Salt API password"
            VAULT_API_PASSWORD="$REPLY"
            while [[ -z "$VAULT_API_PASSWORD" ]]; do
                error "Password is required."
                prompt_secret "Enter Salt API password"
                VAULT_API_PASSWORD="$REPLY"
            done
        fi
    else
        prompt_secret "Enter Salt API password"
        VAULT_API_PASSWORD="$REPLY"
        while [[ -z "$VAULT_API_PASSWORD" ]]; do
            error "Password is required."
            prompt_secret "Enter Salt API password"
            VAULT_API_PASSWORD="$REPLY"
        done
    fi

    echo ""

    # --- Write vault file ---
    if [[ -f "$VAULT_FILE" ]]; then
        # Check if already encrypted
        if head -1 "$VAULT_FILE" | grep -q '^\$ANSIBLE_VAULT;'; then
            warn "vault.yml exists and is already encrypted."
            if ! ask_yes_no "Replace it with new secrets?" "y"; then
                info "Skipping vault configuration."
                return 0
            fi
        fi
        backup_file "$VAULT_FILE"
    fi

    local vault_content
    read -r -d '' vault_content <<ENDOFVAULT || true
---
vault_salt_gitfs_token: "${VAULT_GITFS_TOKEN}"
vault_salt_api_password: "${VAULT_API_PASSWORD}"
ENDOFVAULT

    # Write the unencrypted vault file (will encrypt next)
    mkdir -p "$(dirname "$VAULT_FILE")"
    atomic_write "$VAULT_FILE" "$vault_content"
    info "Vault file written (unencrypted). Proceeding to encrypt..."

    echo ""

    # --- Vault password ---
    echo -e "  ${BOLD}Ansible Vault Password:${NC}"
    info "This password protects your encrypted secrets."
    info "You will need it whenever running Ansible playbooks."
    echo ""

    local vault_password=""
    while true; do
        prompt_secret "Enter vault password"
        vault_password="$REPLY"
        if [[ -z "$vault_password" ]]; then
            error "Vault password cannot be empty."
            continue
        fi
        if [[ ${#vault_password} -lt 8 ]]; then
            warn "Password is short (less than 8 characters)."
            if ! ask_yes_no "Use it anyway?" "n"; then
                continue
            fi
        fi
        prompt_secret "Confirm vault password"
        if [[ "$vault_password" == "$REPLY" ]]; then
            break
        else
            error "Passwords do not match. Please try again."
        fi
    done

    # Offer to save vault password BEFORE encryption to avoid duplicate vault-id.
    # ansible.cfg has vault_password_file = ~/.vault_pass. If we save the password
    # there first, ansible-vault encrypt picks it up automatically. If we don't save
    # it, we pipe the password via --vault-password-file /dev/stdin instead.
    echo ""
    local vault_pass_path="${HOME}/.vault_pass"
    local vault_pass_saved=false
    info "ansible.cfg is configured to use ${vault_pass_path} as the vault password file."

    if [[ -f "$vault_pass_path" ]]; then
        warn "${vault_pass_path} already exists."
        if ask_yes_no "Overwrite it with the new password?" "y"; then
            echo "$vault_password" > "$vault_pass_path"
            chmod 600 "$vault_pass_path"
            vault_pass_saved=true
            success "Vault password saved to ${vault_pass_path} (permissions: 600)"
        fi
    else
        if ask_yes_no "Save vault password to ${vault_pass_path}? (chmod 600)" "y"; then
            echo "$vault_password" > "$vault_pass_path"
            chmod 600 "$vault_pass_path"
            vault_pass_saved=true
            success "Vault password saved to ${vault_pass_path} (permissions: 600)"
        else
            warn "You will need to provide the vault password manually when running playbooks."
            info "Use: ansible-playbook --ask-vault-pass ..."
        fi
    fi

    echo ""

    # Encrypt the vault file.
    # If ~/.vault_pass was saved (or already existed), ansible-vault picks it up
    # from ansible.cfg — no extra flags needed. Otherwise, pipe via stdin.
    if [[ "$vault_pass_saved" == true ]] || [[ -f "$vault_pass_path" ]]; then
        ansible-vault encrypt "$VAULT_FILE"
    else
        echo "$vault_password" | ansible-vault encrypt "$VAULT_FILE" --vault-password-file /dev/stdin
    fi
    if [[ $? -eq 0 ]]; then
        success "vault.yml encrypted successfully."
    else
        error "Failed to encrypt vault.yml. You can encrypt manually with:"
        echo "  ansible-vault encrypt ${VAULT_FILE}"
        return 1
    fi
}

# ==============================================================================
# Step 7: Verify configuration
# ==============================================================================
step_verify() {
    step_header 7 "Verify Configuration"

    info "Checking that the configuration is valid..."
    echo ""

    # --- Verify inventory ---
    echo -e "  ${BOLD}Inventory parsing:${NC}"
    if (cd "$SCRIPT_DIR" && ansible-inventory --list &>/dev/null 2>&1); then
        success "Inventory parsed successfully."
        echo ""
        info "Discovered hosts:"
        (cd "$SCRIPT_DIR" && ansible-inventory --graph 2>/dev/null) | while IFS= read -r line; do
            echo "    $line"
        done
    else
        warn "Inventory parsing failed. Check ${INVENTORY_FILE} for errors."
        echo ""
        info "Attempting to show the error:"
        (cd "$SCRIPT_DIR" && ansible-inventory --list 2>&1) | while IFS= read -r line; do
            echo "    $line"
        done
    fi

    echo ""

    # --- Optional: ping test ---
    if ask_yes_no "Run ansible ping test against salt_master?" "n"; then
        info "Pinging salt_master group..."
        if (cd "$SCRIPT_DIR" && ansible salt_master -m ping --one-line 2>&1); then
            success "Ping test passed."
        else
            warn "Ping test failed. Check SSH connectivity and host availability."
        fi
    fi

    echo ""

    # --- Summary ---
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Configuration Summary${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo -e "  ${BOLD}SSH:${NC}"
    echo -e "    User:              ${SSH_USER:-N/A}"
    echo -e "    Key:               ${SSH_KEY_PATH:-N/A}"
    echo ""

    echo -e "  ${BOLD}Inventory:${NC}"
    echo -e "    Salt master:       ${MASTER_HOSTNAME:-N/A} (${MASTER_IP:-N/A})"
    if [[ ${#MINION_ENTRIES[@]} -gt 0 ]]; then
        echo -e "    Salt minions:"
        for entry in "${MINION_ENTRIES[@]}"; do
            local h="${entry%%|*}"
            local i="${entry##*|}"
            echo -e "      - ${h} (${i})"
        done
    else
        echo -e "    Salt minions:      (none configured)"
    fi
    echo ""

    echo -e "  ${BOLD}Salt Master Settings:${NC}"
    echo -e "    Master address:    ${SALT_MASTER_ADDRESS:-N/A}"
    echo -e "    GitFS repo:        ${SALT_GITFS_REPO:-N/A}"
    echo -e "    GitFS branch:      ${SALT_GITFS_BRANCH:-N/A}"
    echo -e "    GitFS user:        ${SALT_GITFS_USER:-N/A}"
    echo -e "    GitFS interval:    ${SALT_GITFS_UPDATE_INTERVAL:-60}s"
    echo -e "    API port:          ${SALT_API_PORT:-8000}"
    echo -e "    API user:          ${SALT_API_USER:-N/A}"
    echo -e "    Webhook URL:       ${RAILS_WEBHOOK_URL:-N/A}"
    echo ""

    echo -e "  ${BOLD}Secrets (masked):${NC}"
    if [[ -n "${VAULT_GITFS_TOKEN:-}" ]]; then
        echo -e "    GitFS token:       $(mask_secret "$VAULT_GITFS_TOKEN")"
    else
        echo -e "    GitFS token:       (not set in this session)"
    fi
    if [[ -n "${VAULT_API_PASSWORD:-}" ]]; then
        echo -e "    API password:      $(mask_secret "$VAULT_API_PASSWORD")"
    else
        echo -e "    API password:      (not set in this session)"
    fi
    echo ""

    echo -e "  ${BOLD}Files:${NC}"
    for f in "$INVENTORY_FILE" "$MASTER_VARS_FILE" "$MINION_VARS_FILE" "$VAULT_FILE"; do
        if [[ -f "$f" ]]; then
            echo -e "    ${GREEN}[exists]${NC} $f"
        else
            echo -e "    ${RED}[missing]${NC} $f"
        fi
    done
    echo ""

    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    success "Setup complete!"
    echo ""
    info "Next steps:"
    echo "  1. Review the generated files in ${SCRIPT_DIR}"
    echo "  2. Run the playbook:  cd ${SCRIPT_DIR} && ansible-playbook playbooks/salt.yml"
    echo "  3. If you need to edit vault secrets later:"
    echo "     ansible-vault edit ${VAULT_FILE}"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --check)
            run_check_mode
            exit 0
            ;;
        "")
            # No args, proceed with interactive setup
            ;;
        *)
            error "Unknown option: $1"
            echo "Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
    esac

    # Initialize variables that accumulate across steps
    SSH_USER=""
    SSH_KEY_PATH=""
    MASTER_HOSTNAME=""
    MASTER_IP=""
    MINION_ENTRIES=()
    SALT_MASTER_ADDRESS=""
    SALT_GITFS_REPO=""
    SALT_GITFS_BRANCH=""
    SALT_GITFS_USER=""
    SALT_GITFS_UPDATE_INTERVAL=""
    SALT_API_PORT=""
    SALT_API_USER=""
    RAILS_WEBHOOK_URL=""
    SALT_VERSION=""
    VAULT_GITFS_TOKEN=""
    VAULT_API_PASSWORD=""

    show_banner

    info "This wizard will guide you through ${TOTAL_STEPS} steps to configure"
    info "the Salt module Ansible deployment."
    echo ""
    info "Press Ctrl+C at any time to abort. No changes are made until each"
    info "step writes its output file."
    echo ""

    if ! ask_yes_no "Ready to begin?" "y"; then
        info "Aborted."
        exit 0
    fi

    step_prerequisites
    step_ssh_config
    step_inventory
    step_master_vars
    step_minion_vars
    step_vault_secrets
    step_verify
}

main "$@"
