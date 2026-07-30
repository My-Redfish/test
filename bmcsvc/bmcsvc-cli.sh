#!/usr/bin/env bash

# =============================================================================
# bmcsvc-cli.sh — BMC Server Discovery Tool
# =============================================================================

#set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
SCRIPT_NAME="$(basename "$0")"

VERSION="1.0.0"
REDFISH_BASE="/redfish/v1"
BMC_PORT="${BMC_PORT:-443}"
BMC_USER="${BMC_USER:-admin}"
BMC_PASS="${BMC_PASS:-admin}"
CURL_OPTS=(-sk --connect-timeout 10 --max-time 30)
OUTPUT_FMT="table"   # default output format: table | json
FILTER_EXPR=""
 

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")
SCRIPT_DIR=$(dirname "$SCRIPT")
BASE_DIR="$SCRIPT_DIR"


source "$BASE_DIR/lib/core.sh"
source "$BASE_DIR/lib/help.sh"


for f in "$BASE_DIR"/plugins/*.sh; do
    source "$f"
done

########################################
# main dispatch
########################################

REPO="marktsai0316/bmcsvr"

self_update() {
  local url="https://github.com/$REPO/releases/latest/download/$APP_NAME"
  local current_path
  local tmp

  current_path="$(command -v "$APP_NAME" || true)"

  if [ -z "$current_path" ]; then
    echo "Cannot find installed $APP_NAME"
    exit 1
  fi

  tmp="$(mktemp)"

  echo "Downloading latest $APP_NAME..."
  curl -fsSL "$url" -o "$tmp"

  chmod +x "$tmp"

  echo "Replacing $current_path..."

  if [ -w "$(dirname "$current_path")" ]; then
    mv "$tmp" "$current_path"
  else
    sudo mv "$tmp" "$current_path"
  fi

  echo "Update complete."
  "$APP_NAME" --version
}



# ── Entry Point ───────────────────────────────────────────────────────────────
main() {
    [[ $# -gt 0 ]] || { cmd_help; exit 0; }

    MODULE="$1"

    case "$1" in
        node)  shift; cmd_node "$@" ;;
        cluster | group)  shift; cmd_cluster "$@" ;;
        discovery | scan )  shift; cmd_discovery "$@" ;;
        webui )  shift; cmd_webui "$@" ;;
        firmware)    shift; cmd_firmware    "$@" ;;
        biossetup )  shift; cmd_biossetup "$@" ;;
        account )  cmd_redfish "$@" ;;
        redfish )  shift; cmd_redfish "$@" ;;
        inventory )  cmd_redfish "$@" ;;
        sensors )  cmd_redfish "$@" ;;
        powerctl )  cmd_redfish "$@" ;;
        bmcreset )  cmd_redfish "$@" ;;
        ledctl )  cmd_redfish "$@" ;;
        fanctl )  cmd_redfish "$@" ;;
        logs )  cmd_redfish "$@" ;;
        session* )  cmd_redfish "$@" ;;
        version | ver | --version | -v)    echo "${SCRIPT_NAME} ${BOLD}v${VERSION}${RESET}" ;;
        help|--help|-h) cmd_help ;;
        self-update|update)
            self_update
            exit 0
            ;;
        *) err "Unknown command: $1"; cmd_help; exit 1 ;;
    esac
}

main "$@"
