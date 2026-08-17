#!/usr/bin/env bash

CONFIG_DIR="${HOME}/.bmcsvr"
CONFIG_FILE="${CONFIG_DIR}/config"

mkdir -p "$CONFIG_DIR"
touch "$CONFIG_FILE"


# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

BOLD=$(tput bold)
RESET=$(tput sgr0) 

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)


BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)

# Disable colors when not a tty
[[ -t 1 ]] || { RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; RESET=''; }

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "${DIM}[$(date '+%H:%M:%S')]${RESET} $*" >&2; }
info() { echo -e "${BLUE}[INFO]${RESET}  $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*" >&2; }
hint()   { echo -e "${BOLD}[HINT]${RESET}    $*" >&2; }

die() { err "$@"; exit 1; }

require_cmd() {
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || die "Required command not found: $cmd"
    done
}

#!/bin/bash

get_environment() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        if grep -qE "(Microsoft|microsoft|WSL)" /proc/version; then
            echo "wsl"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}


#TARGET="https://10.1.9.86"
#open_url_on_top "$TARGET"


detect_bmc_type() {
    local node="$1"

    ensure_node "$node"

    local host user pass
    host=$(get_node_field "$node" host)
    user=$(get_node_field "$node" user)
    pass=$(get_node_field "$node" pass)

    local base="https://${host}/redfish/v1"

    # Get root info
    local root
    root=$(curl -sk -u "$user:$pass" "$base")

    # Detect vendor
    local vendor="unknown"

    if echo "$root" | grep -qi "iDRAC"; then
        vendor="dell"
    elif echo "$root" | grep -qi "iLO"; then
        vendor="hpe"
    elif echo "$root" | grep -qi "Supermicro"; then
        vendor="supermicro"
    elif echo "$root" | grep -qi "Lenovo"; then
        vendor="lenovo"
    elif echo "$root" | grep -qi "AMI"; then
        vendor="AMI"
    fi
    # Detect system id
    local system_id
    system_id=$(curl -sk -u "$user:$pass" "$base/Systems" | \
        jq -r '.Members[0]."@odata.id"' | awk -F/ '{print $NF}')

    # Detect manager id
    local manager_id
    manager_id=$(curl -sk -u "$user:$pass" "$base/Managers" | \
        jq -r '.Members[0]."@odata.id"' | awk -F/ '{print $NF}')

    # fallback
    [[ "$system_id" == "null" || -z "$system_id" ]] && system_id="1"
    [[ "$manager_id" == "null" || -z "$manager_id" ]] && manager_id="1"

    echo "${vendor}|${system_id}|${manager_id}"
}