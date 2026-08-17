


#!/usr/bin/env bash
# bmcsvr-cli.sh — BMC Server CLI
# Usage: bmcsvr-cli.sh redfish webui open <nodename>
#
# Auto-login strategy:
#   1. Read credentials from ~/.bmcsvr.conf
#   2. POST to Redfish /redfish/v1/SessionService/Sessions → get X-Auth-Token + Location
#   3. Detect BMC firmware type (AMI MegaRAC / OpenBMC / iDRAC / iLO)
#   4. Build auto-login URL and open in browser
 
CURL_OPTS=(-sk --connect-timeout 10 --max-time 30)


# Cross-platform browser open
open_browser() {
    local url="$1"
    log "Opening: $url"
    if command -v xdg-open &>/dev/null; then
        xdg-open "$url" &
    elif command -v open &>/dev/null; then          # macOS
        open "$url"
    elif command -v wslview &>/dev/null; then        # WSL
        wslview "$url"
    elif command -v cmd.exe &>/dev/null; then        # Windows Git Bash
        cmd.exe /c start "" "$url"
    elif command -v python3 &>/dev/null; then
        python3 -c "import webbrowser; webbrowser.open('$url')"
    elspythone
        die "Cannot find a browser launcher. Please open manually: $url"
    fi
}

open_url_on_top() {
    local url=$1
    local env=$(get_environment)

    case $env in
        "macos")
            # -a specifies the application; 'open' usually brings it to front.
            # Using AppleScript ensures it becomes the active process.
            echo "Opening $url on macOS..."
            open "$url"
            osascript -e "tell application \"Browser\" to activate" 2>/dev/null || \
            osascript -e "tell application \"Safari\" to activate"
            ;;
            
        "wsl")
            # In WSL, Windows handles window focus. 
            # explorer.exe usually forces the window to the front.
            echo "Opening $url on WSL..."
            #example1: explorer.exe "$url"
            #example2: wslview "$url"
            powershell.exe -Command "Start-Process "$url"; \
                \$wshell = New-Object -ComObject WScript.Shell; \
                sleep 1; \
                \$wshell.AppActivate('Chrome')" # 
            ;;
            
        "linux")
            echo "Opening $url on Linux..."
            xdg-open "$url"
            # If 'wmctrl' is installed, we can force the window to the front.
            if command -v wmctrl &> /dev/null; then
                sleep 0.5 # Wait for window to initialize
                # Search for window by common browser names and bring to front
                wmctrl -a "Chrome" || wmctrl -a "Firefox" || wmctrl -a "Browser"
            fi
            ;;
            
        *)
            echo "Error: Unknown environment."
            return 1
            ;;
    esac
}
TARGET="https://10.1.9.86"
#open_url_on_top "$TARGET"



# ─────────────────────────────────────────────
# Redfish session creation
# ─────────────────────────────────────────────
create_redfish_session() {

    local base_url="$1"
    local user="$2"
    local pass="$3"
 
    local session_url="${base_url}/redfish/v1/SessionService/Sessions"
    local payload="{\"UserName\":\"${user}\",\"Password\":\"${pass}\"}"
 
    # Capture headers + body
    local tmpfile
    tmpfile=$(mktemp)
 
    local http_code
    http_code=$(curl "${CURL_OPTS[@]}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "OData-Version: 4.0" \
        -d "$payload" \
        -D "$tmpfile" \
        -o "${tmpfile}.body" \
        -w "%{http_code}" \
        "$session_url" 2>/dev/null) || true
    
    if [[ "$http_code" != "200" && "$http_code" != "201" ]]; then
        rm -f "$tmpfile" "${tmpfile}.body"
        die "Redfish session creation failed (HTTP $http_code). Check credentials or host."
    fi
 
    # Extract X-Auth-Token from response headers
    SESSION_TOKEN=$(grep -i "^X-Auth-Token:" "$tmpfile" | tr -d '\r' | awk '{print $2}')
    # Extract session Location (used by some BMCs)
    SESSION_LOCATION=$(grep -i "^Location:" "$tmpfile" | tr -d '\r' | awk '{print $2}')
 
    rm -f "$tmpfile" "${tmpfile}.body"
 
    [[ -z "$SESSION_TOKEN" ]] && die "No X-Auth-Token in response. BMC may not support token auth."
    log "Session token obtained: ${SESSION_TOKEN:0:8}…"
}

 
# ─────────────────────────────────────────────
# Detect BMC firmware type
# ─────────────────────────────────────────────
detect_bmc_type() {
    local base_url="$1"
    local info
 
    info=$(curl "${CURL_OPTS[@]}" \
        -H "X-Auth-Token: ${SESSION_TOKEN}" \
        "${base_url}/redfish/v1/" 2>/dev/null) || true
 
    if echo "$info" | grep -qi "megarac\|ami\|MegaRAC"; then
        BMC_TYPE="ami"
    elif echo "$info" | grep -qi "idrac\|dell"; then
        BMC_TYPE="idrac"
    elif echo "$info" | grep -qi "ilo\|hewlett\|hpe"; then
        BMC_TYPE="ilo"
    elif echo "$info" | grep -qi "openbmc"; then
        BMC_TYPE="openbmc"
    else
        # Fallback: check /redfish/v1/Managers for product name
        local mgr
        mgr=$(curl "${CURL_OPTS[@]}" \
            -H "X-Auth-Token: ${SESSION_TOKEN}" \
            "${base_url}/redfish/v1/Managers" 2>/dev/null) || true
        if echo "$mgr" | grep -qi "iDRAC"; then
            BMC_TYPE="idrac"
        else
            BMC_TYPE="generic"
        fi
    fi
    log "Detected BMC type: $BMC_TYPE"
}
 
# ─────────────────────────────────────────────
# Build auto-login URL per firmware type
# ─────────────────────────────────────────────
build_autologin_url() {
    local base_url="$1"
 
    case "$BMC_TYPE" in
        ami)
            # AMI MegaRAC / Supermicro: POST form with token, or use token param
            # Many AMI WebUI support: /index.html?token=<X-Auth-Token>
            AUTOLOGIN_URL="${base_url}/index.html?token=${SESSION_TOKEN}"
            ;;
        idrac)
            # Dell iDRAC: login via session redirect
            # iDRAC8/9 supports: /sysmgmt/2015/bmc/session with token in header
            # Simplest reliable method: open login page with pre-filled form via JS redirect
            AUTOLOGIN_URL="${base_url}/restgui/start.html?token=${SESSION_TOKEN}"
            ;;
        ilo)
            # HPE iLO: /json/login_session → redirect
            AUTOLOGIN_URL="${base_url}/ui/#/login?token=${SESSION_TOKEN}"
            ;;
        openbmc)
            # OpenBMC: /login with session cookie
            # The token can be passed as query param or cookie
            AUTOLOGIN_URL="${base_url}/#/?token=${SESSION_TOKEN}"
            ;;
        *)
            # Generic fallback: try common token URL patterns
            AUTOLOGIN_URL="${base_url}/index.html?token=${SESSION_TOKEN}"
            ;;
    esac
}
 
# ─────────────────────────────────────────────
# Generate a self-submitting HTML login page
# (fallback for BMCs that don't support ?token=)
# ─────────────────────────────────────────────
generate_autologin_html() {
    local base_url="$1"
    local user="$2"
    local pass="$3"
    local tmphtml
 
    tmphtml=$(mktemp /tmp/bmc-autologin-XXXXXX.html)
 
    cat > "$tmphtml" <<HTML
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>BMC Auto Login…</title>
</head>
<body onload="document.forms[0].submit()">
  <p>Logging in to BMC, please wait…</p>
  <form method="POST" action="${base_url}/redfish/v1/SessionService/Sessions">
    <input type="hidden" name="UserName" value="${user}">
    <input type="hidden" name="Password" value="${pass}">
  </form>
  <script>
    // After session POST, redirect to WebUI root with token injected via cookie
    // Fallback: standard WebUI login
    fetch('${base_url}/redfish/v1/SessionService/Sessions', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({UserName:'${user}',Password:'${pass}'}),
      credentials: 'include'
    }).then(r => {
      const tok = r.headers.get('X-Auth-Token');
      if (tok) {
        document.cookie = 'token=' + tok + '; path=/';
        window.location.replace('${base_url}/');
      } else {
        window.location.replace('${base_url}/');
      }
    }).catch(() => window.location.replace('${base_url}/'));
  </script>
</body>
</html>
HTML
 
    echo "$tmphtml"
}

# ─────────────────────────────────────────────
# Main: redfish webui open <nodename>
# ─────────────────────────────────────────────
cmd_redfish_webui_open() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: bmcsvr-cli.sh redfish webui open <nodename>"
 
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
    local base_url="https://${CFG_HOST}:${CFG_PORT}"
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

cmd_webui_open() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME webui open <node>"
 
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
    local base_url="https://${CFG_HOST}"
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
cmd_biossetup_open() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME webui open <node>"
 
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

cmd_webui_help() {
    case "$1" in
          *)
            cat <<EOF
$SCRIPT_NAME webui - bmc webui operation

${BOLD}Usage${RESET}:
  $SCRIPT_NAME webui <command> [options]

${BOLD}Commands${RESET}:
  open      Open BMC webui URL auto-login
  url       Get node field
  record    record webui
  help      Show help

${BOLD}Examples${RESET}:
  $SCRIPT_NAME webui open node01 

${BOLD}Use${RESET}:
  $SCRIPT_NAME webui help <command>

EOF
            ;;
    esac
}

cmd_webui() {
#    case "$1" in
#        open) shift; cmd_webui_open "$@";;
#        *) cmd_webui_help ;;
#    esac
    cmd_webui_open "$@"
}

cmd_biossetup() {
#    case "$1" in
#        open) shift; cmd_webui_open "$@";;
#        *) cmd_webui_help ;;
#    esac
    cmd_biossetup_open "$@"
}

#cmd_redfish_webui_open "pc1"
#ret=$(curl -sk -c cookies.txt -X POST https://10.1.9.86/ \
#  -d "user=test&password=gigabyte@123")


#login fail : Basic Auth https://test:gigabyte@10.1.9.117
#login fail : cookie https://10.1.9.86 
#login fail : X-Auth-Token https://10.1.9.86.token
TARGET="https://10.1.9.117"
#open_url_on_top "$TARGET"


#Chrome extension（AutoFill / Password Manager）


