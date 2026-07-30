#!/usr/bin/env bash

# ─────────────────────────────────────────────
# Main: redfish webui open <nodename>
# ─────────────────────────────────────────────
cmd_redfish_amisetup_open() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: bmcsvr-cli.sh redfish biossetup open <nodename>"
 
    log "Loading config for node: $node"
    ensure_node "$node"

    local host user pass
    host=$(get_node_field "$node" host)
    user=$(get_node_field "$node" user)
    pass=$(get_node_field "$node" pass)

    CFG_HOST="$host"
    CFG_USER="$user"
    CFG_PASS="$pass"
    CFG_PORT="443"
    local base_url="https://${CFG_HOST}:${CFG_PORT}/bios/Index.html"
    
    log "Target BMC: $base_url (user: $CFG_USER)"
 
    # Step 1: Create Redfish session
    create_redfish_session "$base_url" "$CFG_USER" "$CFG_PASS"
 
    # Step 2: Detect firmware
    detect_bmc_type "$base_url"
    
    # Step 3: Build auto-login URL
    build_autologin_url "$base_url"
 
    # Step 4: Open browser
    # Try token URL first; if BMC doesn't support it, fall back to HTML bridge
    log "BMC type: $BMC_TYPE → auto-login URL ready"
 
    if [[ "$BMC_TYPE" == "generic" ]]; then
        log "Unknown BMC type — using HTML bridge login page"
        local htmlfile
        htmlfile=$(generate_autologin_html "$base_url" "$CFG_USER" "$CFG_PASS")
        log "Generated: $htmlfile"
        open_browser "file://${htmlfile}"
    else
        open_browser "$AUTOLOGIN_URL"
    fi
 
    echo ""
    echo "  Node    : $node"
    echo "  Host    : $CFG_USER:$CFG_PORT"
    echo "  BMC type: $BMC_TYPE"
    echo "  Token   : ${SESSION_TOKEN:0:8}…"
    echo "  URL     : $AUTOLOGIN_URL"
}

cmd_amisetup_open() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME biossetup open <node>"
 
    log "Loading config for node: $node"
    ensure_node "$node"

    local host user pass
    host=$(get_node_field "$node" host)
    user=$(get_node_field "$node" user)
    pass=$(get_node_field "$node" pass)

    CFG_HOST="$host"
    CFG_USER="$user"
    CFG_PASS="$pass"
    CFG_PORT="443"
    local base_url="https://${CFG_HOST}/bios/Index.html"
    log "Target BMC: $base_url (user: $CFG_USER)"
  
    open_url_on_top "$base_url"
    return



    # Step 1: Create Redfish session
    create_redfish_session "$base_url" "$CFG_USER" "$CFG_PASS"
 
    # Step 2: Detect firmware
    detect_bmc_type "$base_url"
    
    # Step 3: Build auto-login URL
    build_autologin_url "$base_url"
 
    # Step 4: Open browser
    # Try token URL first; if BMC doesn't support it, fall back to HTML bridge
    log "BMC type: $BMC_TYPE → auto-login URL ready"
 
    if [[ "$BMC_TYPE" == "generic" ]]; then
        log "Unknown BMC type — using HTML bridge login page"
        local htmlfile
        htmlfile=$(generate_autologin_html "$base_url" "$CFG_USER" "$CFG_PASS")
        log "Generated: $htmlfile"
        open_browser "file://${htmlfile}"
    else
        #open_browser "$AUTOLOGIN_URL"
        open_url_on_top "$AUTOLOGIN_URL"
    fi
 
    echo ""
    echo "  Node    : $node"
    echo "  Host    : $CFG_USER:$CFG_PORT"
    echo "  BMC type: $BMC_TYPE"
    echo "  Token   : ${SESSION_TOKEN:0:8}…"
    echo "  URL     : $AUTOLOGIN_URL"
}

#cmd_redfish_webui_open "pc1"
#ret=$(curl -sk -c cookies.txt -X POST https://10.1.9.86/ \
#  -d "user=test&password=gigabyte@123")


#login fail : Basic Auth https://test:gigabyte@10.1.9.117
#login fail : cookie https://10.1.9.86 
#login fail : X-Auth-Token https://10.1.9.86.token


#######################################
# help system
########################################

cmd_amisetup_help() {
    case "$1" in
          *)
            cat <<EOF
$SCRIPT_NAME biossetup - bios setup operation

${BOLD}Usage${RESET}:
  $SCRIPT_NAME biossetup <command> [options]

${BOLD}Commands${RESET}:
  open      Open BMC biossetup URL auto-login
  url       Get node field
  record    record biossetup
  help      Show help

${BOLD}Examples${RESET}:
  $SCRIPT_NAME biossetup open node01 

${BOLD}Use${RESET}:
  $SCRIPT_NAME biossetup help <command>

EOF
            ;;
    esac
}

cmd_amisetup() {
    case "$1" in
        open) shift; cmd_amisetup_open "$@";;
        *) cmd_amisetup_help ;;
    esac
}


#cmd_redfish_webui_open "pc1"
#ret=$(curl -sk -c cookies.txt -X POST https://10.1.9.86/ \
#  -d "user=test&password=gigabyte@123")


#login fail : Basic Auth https://test:gigabyte@10.1.9.117
#login fail : cookie https://10.1.9.86 
#login fail : X-Auth-Token https://10.1.9.86.token
#TARGET="https://10.1.9.117"
#open_url_on_top "$TARGET"


#Chrome extension（AutoFill / Password Manager）


