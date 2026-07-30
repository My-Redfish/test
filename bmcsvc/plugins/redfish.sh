# ---------------------------------------------------------------------------
# Dependency check
# ----------------------------------------------------------------------------
check_deps() {
    local missing=()
    for cmd in curl jq column; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}
 

 
# ---------------------------------------------------------------------------
# Core HTTP helpers
# ---------------------------------------------------------------------------
rf_get() {
    local path="$1"
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    #log "rf_get $url"
    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         -H "Accept: application/json" \
         -H "OData-Version: 4.0" \
         "$url"
}
 
rf_post1() {
    local path="$1"
    local body="${2:-{}}"
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -H "OData-Version: 4.0" \
         -X POST -d "$body" "$url"
}
rf_post() {
    local path="$1"
    local body="${2}"
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -H "OData-Version: 4.0" \
         -X POST -d "$body" "$url"
} 
rf_patch1() {
    local path="$1"
    local body="${2:-{}}"
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -H "OData-Version: 4.0" \
         -X PATCH -d "$body" "$url"
}
rf_patch() {
    local path="$1"
    local body="$2" #Bugs ? "${2:-{}}"
    local etag="$3"
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         -H "Content-Type: application/json" \
         -H "Accept: application/json" \
         -H "If-Match: $etag" \
         -X PATCH -d "$body" "$url"
}

rf_delete() {
    local path="$1"
    local etag="$2" # Optional: For concurrency control
    local url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}${path}"
    
    # Define headers in an array for cleanliness
    local headers=(
        -H "Accept: application/json"
    )

    # Add If-Match header only if an Etag is provided
    if [[ -n "$etag" ]]; then
        headers+=(-H "If-Match: $etag")
    fi

    curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
         "${headers[@]}" \
         -X DELETE "$url"
}
# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
parse_output_args() {
    # Sets OUTPUT_FMT and FILTER_EXPR from remaining positional args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)   OUTPUT_FMT="json"  ;;
            --table)  OUTPUT_FMT="table" ;;
            --filter) shift; FILTER_EXPR="${1:-}" ;;
            *) warn "Unknown option: $1" ;;
        esac
        shift
    done
}
 
emit_json() {
    local data="$1"
    if [[ -n "$FILTER_EXPR" ]]; then
        echo "$data" | jq "$FILTER_EXPR"
    else
        echo "$data" | jq .
    fi
}
 
# Print a simple key-value table from a jq filter producing {"key":"val",...}
emit_table_kv() {
    local data="$1"
    local filter="${2:-.}"
    if [[ -n "$FILTER_EXPR" ]]; then filter="$FILTER_EXPR"; fi
    echo "$data" | jq -r "$filter | to_entries[] | [.key, (.value|tostring)] | @tsv" \
        | column -t -s $'\t'
}
 
# Print a table from a jq array filter
emit_table_array() {
    local data="$1"
    local filter="${2:-.[]}"
    local headers="${3:-}"
    if [[ -n "$FILTER_EXPR" ]]; then filter="$FILTER_EXPR"; fi
    if [[ -n "$headers" ]]; then echo -e "$headers"; fi
    echo "$data" | jq -r "$filter"
}
 
# ---------------------------------------------------------------------------
# ─────────────────────────────  POWER  ─────────────────────────────────────
# ---------------------------------------------------------------------------
cmd_power() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish power <node>"
 
    local section="${2:-status}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    # Find system ID (first member)
    local sys_col
    sys_col="$(rf_get "/Systems")" || die "Cannot reach BMC at $BMC_HOST"
    local sys_path
    sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')" \
        || die "No Systems found"


    case "$section" in
    PowerOn | On | on)
        #Power On
        info "Sending PowerOn to $node …"
        set_power On
        ;;
    AcpiOff | acpioff | Off | off)  
        #ACPI Shutdown
        info "Sending GracefulShutdown to $node …"
        set_power GracefulShutdown
        ;;
    PowerOff |  poweroff |ForceOff | forceoff) 
        #Power Off 
        info "Sending ForceOff to $node  …"
        set_power ForceOff
        ;;
    #Restart | restart) 
    #    #GracefulRestart 
    #    info "Sending GracefulRestart to $node  …"
    #    set_power GracefulRestart
    #    ;;

    PowerCycle | powercycle) 
        #Power Cycle   
        info "Sending PowerCycle to $node  …"
        set_power PowerCycle
        ;;
    HardReset | ForceRestart | forcerestart)  
        #Hard Reset
        info "Sending ForceRestart to $node  …"
        set_power ForceRestart
        ;;
    status) 
        get_power ;;    
    *)  die "Unknown power action: $action  (use: status | on | off | restart | forceoff | forcerestart)"
    esac
    get_power_resettype
}
cmd_power1() {
    local name="${1:-}"; local action="${2:-status}"
    shift 2 2>/dev/null || true
    parse_output_args "$@"
 
    resolve_bmc "$name"
 
    # Find system ID (first member)
    local sys_col
    sys_col="$(rf_get "/Systems")" || die "Cannot reach BMC at $BMC_HOST"
    local sys_path
    sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')" \
        || die "No Systems found"
 
    case "$action" in
    status)
        local sys
        sys="$(rf_get "${sys_path#$REDFISH_BASE}")"
        if [[ "$OUTPUT_FMT" == "json" ]]; then
            emit_json "$sys" 
        else
            local data
            data="$(echo "$sys" | jq '{
                "Name":         .Name,
                "PowerState":   .PowerState,
                "Health":       .Status.Health,
                "HealthRollup": .Status.HealthRollup,
                "BIOSVersion":  .BiosVersion,
                "Manufacturer": .Manufacturer,
                "Model":        .Model,
                "SerialNumber": .SerialNumber
            }')"
            echo -e "${BOLD}Power Status — $name${RESET}"
            emit_table_kv "$data"
        fi
        ;;
    on)
        info "Sending PowerOn to $name …"
        local resp
        resp="$(rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"On"}')"
        _check_action_resp "$resp" "PowerOn"
        ;;
    off)
        info "Sending GracefulShutdown to $name …"
        local resp
        resp="$(rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"GracefulShutdown"}')"
        _check_action_resp "$resp" "GracefulShutdown"
        ;;
    forceoff)
        info "Sending ForceOff to $name …"
        local resp
        resp="$(rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"ForceOff"}')"
        _check_action_resp "$resp" "ForceOff"
        ;;
    restart)
        info "Sending GracefulRestart to $name …"
        local resp
        resp="$(rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"GracefulRestart"}')"
        _check_action_resp "$resp" "GracefulRestart"
        ;;
    forcerestart)
        info "Sending ForceRestart to $name …"
        local resp
        resp="$(rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"ForceRestart"}')"
        _check_action_resp "$resp" "ForceRestart"
        ;;
    *)
        die "Unknown power action: $action  (use: status | on | off | restart | forceoff | forcerestart)"
        ;;
    esac
}
 
_check_action_resp() {
    local resp="$1" label="$2"
    local code
    code="$(echo "$resp" | jq -r '.error.code // empty' 2>/dev/null)"
    if [[ -n "$code" ]]; then
        local msg
        msg="$(echo "$resp" | jq -r '.error.message // "unknown error"')"
        die "$label failed: $code — $msg"
    fi
    ok "$label accepted"
}
get_power_resettype() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { 
        warn "System path not found"; 
        return; 
    }
    
    # 2. Fetch the System data
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}")

    # 3. Define the Default Values (as a JSON array)
#    local default_values='["On", "ForceOff", "GracefulShutdown", "PowerCycle", "ForceRestart", "Nmi", "PushPowerButton"]'
    local default_values='["On", "ForceOff", "GracefulShutdown", "PowerCycle", "ForceRestart"]'

    # 4. Attempt to extract AllowableValues from the Action
    # We look for the common Redfish keys used by different vendors
    local allowable_values
    allowable_values=$(echo "$data" | jq -c '
        .Actions["#ComputerSystem.Reset"]["ResetType@Redfish.AllowableValues"] // 
        .Actions["#ComputerSystem.Reset"].allowableValues // 
        empty
    ')

    # 5. Check if we got a value; if not, use the fallback
    local final_list
    local source
    if [[ -n "$allowable_values" && "$allowable_values" != "null" ]]; then
        final_list="$allowable_values"
        source="BMC Provided"
    else
        final_list="$default_values"
        source="Default Fallback"
    fi

    # 6. Output Formatting
    local DATA_TYPE='Allowable Power Reset Types'
    local display_list
    display_list=$(echo "$final_list" | jq -r 'join(", ")')

    echo -e "Host: ${BOLD}${BMC_HOST}${RESET}"
    echo -e "Category: ${BOLD}${DATA_TYPE}${RESET} (${source})"
    echo -e "--------------------------------------------------"
    echo -e "Values: ${SUCCESS}${display_list}${RESET}"
    #echo "Usage: set_power [On|ForceOff|Off|GracefulRestart|ForceRestart]"   
    echo "Usage: set_power [On|ForceOff|Off|PowerCycle|ForceRestart]"   
    # Return raw JSON for other scripts to consume
    #echo "$final_list"
}
set_power() {
    local reset_type="$1" # Expected: On, ForceOff, GracefulShutdown, ForceRestart, etc.
    
    if [[ -z "$reset_type" ]]; then
        #echo "Usage: set_power [On|ForceOff|GracefulShutdown|GracefulRestart|ForceRestart]"
        echo "Usage: set_power [On|ForceOff|Off|GracefulRestart|ForceRestart]"
        return 1
    fi

    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { return; }

    # 2. Identify the Reset Action URI
    # Typically: /redfish/v1/Systems/Self/Actions/ComputerSystem.Reset
    local action_uri="${system_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset"

    echo -e "Sending Power Action: ${BOLD}${reset_type}${RESET} to ${BMC_HOST}..."

    # 3. Perform the POST request
    # Payload format: {"ResetType": "Value"}
    local payload="{\"ResetType\": \"$reset_type\"}"
    echo $payload
    echo $action_uri
    #exit
    
    #rf_post "$action_uri" "$payload" 2> /dev/null && {
    #    echo -e "Power Action ${SUCCESS}${reset_type}${RESET} executed successfully."
    #} || {
    #    echo -e "Error: Failed to execute power action."
    #    return 1
    #}
  
    local resp
    resp=$(rf_post "$action_uri" "$payload")
    _check_action_resp "$resp" "$reset_type"
}
get_power() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { 
        warn "System path not found"; 
        return; 
    }
    # 2. Fetch the PowerState property
    local power_data
    power_status=$(rf_get "${system_path#$REDFISH_BASE}" | jq -r '.PowerState // "Unknown"')

    # 3. Aggregate and Format Output
    local DATA_TYPE='PowerState'
    local jsondata
    jsondata=$(echo "{}" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        --arg STATUS "$power_status" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: [{ ID: "Systems", Status: $STATUS }], Count: 1 }')

    # 4. Prepare Table Data
    local tsvdata
    tsvdata=$(echo "$jsondata" | jq -r '(["ID", "PowerState"] | @tsv), (.Data[] | [.ID, .Status] | @tsv)')

    # 5. Display Output
    local host type
    read -r host type < <(echo "$jsondata" | jq -r '[.Host, .Type] | join(" ")')
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    
    export TABLE_FMT="fancy_grid"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
}
# ---------------------------------------------------------------------------
# ─────────────────────────────  LED  ─────────────────────────────────
# ---------------------------------------------------------------------------

# 執行 BMC 重啟函數
# 參數 $1: cold 或 warm (預設為 warm)
reset_bmc() {
    local reset_type="${1:-warm}"
    
    # 驗證輸入參數是否合法
    if [[ "$reset_type" != "cold" && "$reset_type" != "warm" ]]; then
        warn "Invalid reset type: $reset_type. Must be 'cold' or 'warm'."
        return 1
    fi

    # 檢查必要的連線變數是否存在
    if [[ -z "$BMC_HOST" || -z "$BMC_USER" || -z "$BMC_PASS" ]]; then
        warn "IPMI credentials or host not set (IPMI_HOST, IPMI_USER, IPMI_PASS)"
        return 1
    fi

    echo "Sending BMC $reset_type reset command to $BMC_HOST..." >&2

    # 執行 ipmitool 指令並加入錯誤攔截
    ipmitool -I lanplus -H "$BMC_HOST" -U "$BMC_USER" -P "$BMC_PASS" bmc reset "$reset_type" >/dev/null 2>&1 || {
        warn "Failed to execute BMC $reset_type reset on $IPMI_HOST"
        return 1
    }

    echo "BMC $reset_type reset command sent successfully." >&2
    echo "Note: BMC will be unreachable for a few minutes while restarting." >&2
}

cmd_bmcctl() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish bmcctl <node>"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass) 

    local section="${2:-warm}"
    case "${section,,}" in
    warm)
        reset_bmc warm;;
    cold)  
        reset_bmc cold;;  
 
    *)  die "Unknown led section: $section  (status | lit | off | blinking)" ;;
    esac


}


# ---------------------------------------------------------------------------
# ─────────────────────────────  LED  ─────────────────────────────────
# ---------------------------------------------------------------------------
cmd_led() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish led <node>"
 
    local section="${2:-status}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

   # Find system ID (first member)
    local sys_col
    sys_col="$(rf_get "/Systems")" || die "Cannot reach BMC at $BMC_HOST"
    local sys_path
    sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')" \
        || die "No Systems found"

    case "$section" in
    lit | Lit)
        set_led Lit;;
    Off | off)  
        set_led Off;;  
    Blinking | blinking | blink)  
        set_led Blinking;; 
    status) ;;    
    *)  die "Unknown led section: $section  (status | lit | off | blinking)" ;;
    esac

    get_led 
    get_led_types  
}

set_led() {
    local state=$1  # Acceptable: Lit, Blinking, Off
    
    if [[ ! "$state" =~ ^(Lit|Blinking|Off)$ ]]; then
        err "Usage: set_led [Lit|Blinking|Off]"
        return 1
    fi

    # 1. Discover Systems path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || return 1

    # 2. Get ETag for the Systems resource
    local etag
    etag=$(rf_get "${chassis_path#$REDFISH_BASE}" | jq -r '."@odata.etag"')

    # 3. Perform PATCH with If-Match header
    echo "Setting IndicatorLED to: $state..."
    data=$(rf_patch "${chassis_path#$REDFISH_BASE}" "{\"IndicatorLED\": \"$state\"}" "$etag" )
    msg=$(echo $data | jq -r '.error.message // empty' )

    [[ -n "$msg" ]] && warn "$msg"
    
}

get_led() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || {
        warn "Chassis path not found"; return 1;
    }

    # 2. Fetch LED status
    local data
    data=$(rf_get "${chassis_path#$REDFISH_BASE}")
    
    local led_status
    led_status=$(echo "$data" | jq -r '.IndicatorLED // "N/A"')

    # 3. Aggregate and Format Output
    local DATA_TYPE='IndicatorLED Status'
    local jsondata
    jsondata=$(echo "{}" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        --arg STATUS "$led_status" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: [{ ID: "Chassis", Status: $STATUS }], Count: 1 }')

    # 4. Prepare Table Data
    local tsvdata
    tsvdata=$(echo "$jsondata" | jq -r '(["ID", "IndicatorLED Status"] | @tsv), (.Data[] | [.ID, .Status] | @tsv)')

    # 5. Display Output
    local host type
    read -r host type < <(echo "$jsondata" | jq -r '[.Host, .Type] | join(" ")')
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    
    export TABLE_FMT="fancy_grid"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
}
get_led_types() {
    local DATA_TYPE='IndicatorLED Actions'
    
    local jsondata
    jsondata=$(echo "{}" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ 
            Host: $BMC_HOST, 
            Type: $DATA_TYPE, 
            Data: [
                { Type: "Lit", Description: "Identify: LED is continuously on" },
                { Type: "Blinking", Description: "Locate: LED is blinking" },
                { Type: "Off", Description: "LED is turned off" }
            ], 
            Count: 3 
        }')

    # Prepare and Display
    local tsvdata
    tsvdata=$(echo "$jsondata" | jq -r '(["Action", "Description"] | @tsv), (.Data[] | [.Type, .Description] | @tsv)')

    local host type
    read -r host type < <(echo "$jsondata" | jq -r '[.Host, .Type] | join(" ")')
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    
    export TABLE_FMT="fancy_grid"
    echo "$tsvdata" | eval "$run_python" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
} 
# ---------------------------------------------------------------------------
# ─────────────────────────────  ACCOUNT  ───────────────────────────────────
# ---------------------------------------------------------------------------
cmd_account() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish sensors <node>"
 
    local section="${2:-all}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    sys_col="$(rf_get "/Systems")"
    [ -z "$sys_col" ] && die "$node:$BMC_HOST:$BMC_USER connection fail!"
 
    case "$section" in
    user)
        local accts
        accts="$(rf_get "/AccountService/Accounts")"
        if [[ "$OUTPUT_FMT" == "json" ]]; then
            local detail=()
            while IFS= read -r m; do
                detail+=("$(rf_get "${m#$REDFISH_BASE}")")
            done < <(echo "$accts" | jq -r '.Members[]."@odata.id"')
            printf '%s\n' "${detail[@]}" | jq -s .
        else
            echo -e "${BOLD}── Accounts ─────────────────────────────────────────────${RESET}"
            printf "%-4s %-20s %-8s %-12s %-20s\n" "ID" "UserName" "Enabled" "RoleId" "AccountTypes"
            printf '%0.s─' {1..70}; echo
            while IFS= read -r m; do
                rf_get "${m#$REDFISH_BASE}" | jq -r '[
                    (.Id//"?"),
                    (.UserName//"?"),
                    ((.Enabled//false)|tostring),
                    (.RoleId//"?"),
                    ((.AccountTypes//[])|join(","))
                ] | @tsv' | awk -F'\t' '{printf "%-4s %-20s %-8s %-12s %-20s\n",$1,$2,$3,$4,$5}'
            done < <(echo "$accts" | jq -r '.Members[]."@odata.id"')
        fi
        ;;
    role)
        local roles
        roles="$(rf_get "/AccountService/Roles")"
        if [[ "$OUTPUT_FMT" == "json" ]]; then
            emit_json "$roles"
        else
            echo -e "${BOLD}── Roles ────────────────────────────────────────────────${RESET}"
            printf "%-15s %-12s %-40s\n" "RoleId" "IsPredefined" "AssignedPrivileges"
            printf '%0.s─' {1..70}; echo
            while IFS= read -r m; do
                rf_get "${m#$REDFISH_BASE}" | jq -r '[
                    (.Id//"?"),
                    ((.IsPredefined//false)|tostring),
                    ((.AssignedPrivileges//[])|join(","))
                ] | @tsv' | awk -F'\t' '{printf "%-15s %-12s %-40s\n",$1,$2,$3}'
            done < <(echo "$roles" | jq -r '.Members[]."@odata.id"')
        fi
        ;;
    *)
        die "Unknown account section: $section  (user | role)"
        ;;
    esac
}
_inv_roles() {
    # 1. Define the Roles collection path
    # Standard Redfish path: /redfish/v1/AccountService/Roles
    local roles_collection_uri="/AccountService/Accounts"
    # Correcting standard path for roles:
    local roles_uri="/AccountService/Roles"
    
    local data
    data=$(rf_get "$roles_uri" 2>/dev/null) || { 
        warn "Role Service not available at $roles_uri"; 
        return; 
    }

    # 2. Get total count of roles
    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        echo "No roles found."
        return
    fi

    local DATA_TYPE='Role'
    local current=0
    echo "Fetching Roles... Total: $total" >&2

    # 3. Extract detailed information for each role
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r role_uri; do
        ((current++))
        printf "\rProcessing Role: [%d/%d]...   " "$current" "$total" >&2
        
        rf_get "${role_uri#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            IsPredefined: .IsPredefined,
            AssignedPrivileges: (.AssignedPrivileges | join(", ")),
            OemPrivileges: (if .OemPrivileges != null then .OemPrivileges | join(", ") else "N/A" end),   
            RoleId: .RoleId
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. Integrate structured data
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV data for formatting
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Role ID", "Predefined", "Privileges","OemPrivileges"] | @tsv), 
        (.Data[] | [.RoleId, .IsPredefined, .AssignedPrivileges, .OemPrivileges] | @tsv)
    ')

    # 6. Formatted Output
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total ${type} Entities: ${BOLD}${count}${RESET}"
}
_inv_users() {
    # 1. Define the User Accounts path
    # Standard Redfish path: /redfish/v1/AccountService/Accounts
    local user_collection_uri="/AccountService/Accounts"
    local data
    data=$(rf_get "$user_collection_uri" 2>/dev/null) || { 
        warn "Account Service not available at $user_collection_uri"; 
        return; 
    }

    # 2. Get total count
    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        echo "No user accounts found."
        return
    fi

    local DATA_TYPE='User'
    local current=0
    echo "Fetching User Accounts... Total: $total" >&2

    # 3. Extract detailed information for each user
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r user_uri; do
        ((current++))
        printf "\rProcessing User: [%d/%d]...   " "$current" "$total" >&2
        
        # Strip REDFISH_BASE if necessary to use rf_get
        rf_get "${user_uri#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            UserName: .UserName,
            RoleId: .RoleId,
            Enabled: .Enabled,
            Locked: .Locked,
            AccountTypes: (if .AccountTypes != null then .AccountTypes | join(", ") else "N/A" end),
            PasswordExpiration: (.PasswordExpiration // "N/A")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. Integrate structured data
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV data for formatting
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "UserName", "Role", "Enabled", "Locked", "AccountTypes", "PasswordExpiration"] | @tsv), 
        (.Data[] | [.Id, .UserName, .RoleId, .Enabled, .Locked, .AccountTypes, .PasswordExpiration] | @tsv)
    ')

    # 6. Formatted Output
    export TABLE_FMT="fancy_grid"
 
    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total ${type} Entities: ${BOLD}${count}${RESET}"

}


# 2. Create Account
# Usage: create_account <username> <password> <role_id>
# Example: create_account "operator1" "Password123" "Operator"
create_account() {
    local username=$1
    local password=$2
    local role=$3

    if [[ -z "$username" || -z "$password" || -z "$role" ]]; then
        echo "Usage: create_account <username> <password> <role_id>"
        return 1
    fi

    # Create compact JSON payload
    local payload=$(jq -nc \
        --arg un "$username" \
        --arg pw "$password" \
        --arg rl "$role" \
        '{"UserName": $un, "Password": $pw, "RoleId": $rl}')

    echo "Creating account: $username..."
    rf_post "$ACCOUNTS_URI" "$payload"
}

# 3. Delete Account
# Usage: delete_account <account_id>
delete_account() {
    local account_id=$1
    if [[ -z "$account_id" ]]; then
        echo "Usage: delete_account <account_id>"
        return 1
    fi

    local uri="$ACCOUNTS_URI/$account_id"
    echo "Deleting account: $account_id..."
    rf_delete "$uri"
}

# 4. Modify Account (Helper for PATCH operations)
# Handles ETag/If-Match for safe updates
_modify_account() {
    local account_id=$1
    local property=$2
    local value=$3
    local uri="$ACCOUNTS_URI/$account_id"

    # Get current ETag to ensure atomicity
    local account_data=$(rf_get "$uri")
    local etag=$(echo "$account_data" | jq -r '."@odata.etag"')

    # Build compressed JSON payload
    local payload=$(jq -nc --argjson val "$value" "{\"$property\": \$val}")

    echo "Updating $property for $account_id..."
    rf_patch "$uri" "$payload" "$etag"
}

# 5. Enable Account
# Usage: enable_account <account_id>
enable_account() {
    _modify_account "$1" "Enabled" true
}

# 6. Disable Account
# Usage: disable_account <account_id>
disable_account() {
    _modify_account "$1" "Enabled" false
}

# 7. Unlock Account
# Usage: unlock_account <account_id>
# Note: Redfish allows unlocking by setting "Locked" to false.
unlock_account() {
    _modify_account "$1" "Locked" false
}
# ---------------------------------------------------------------------------
# ─────────────────────────────  sensors  ───────────────────────────────────
# ---------------------------------------------------------------------------
cmd_sensors() {
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish sensors <node>"
 
    local section="${2:-none}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    sys_col="$(rf_get "/Systems")"
    [ -z "$sys_col" ] && die "$node:$BMC_HOST:$BMC_USER connection fail!"

 
    case "$section" in
    #all) 
    #    _inv_fan
    #    _inv_temp
    #    _inv_voltage
    #   _inv_sensor;;

    fan* )
        _inv_fan;;

    temp*)
        _inv_temp;;
    
    volt*)
        _inv_voltage;;    
    
    sens*)
        _inv_sensor;;      

    thermal)  
        _inv_fan
        _inv_temp
         ;;   
    *)
        die "Unknown sensors section: $section  (fan | temp | volt | sensor | thermal)"
        ;;
    esac
}
# ---------------------------------------------------------------------------
# ─────────────────────────────  SESSIONS  ─────────────────────────────────
# ---------------------------------------------------------------------------
cmd_session() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish sessions <node>"
 
    local section="${2:-list}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    case "$section" in
    list)
        list_sessions;;
    del)  
        del_sessions $3;;

    *)    die "Unknown session section: $section  (list | clear)" ;;
    esac
}
del_sessions() {
    local target_id="$1"

    if [[ -z "$target_id" ]]; then
        echo "Usage: del [SessionID | all]"
        return 1
    fi

    # 1. Define the sessions Collection path
    local sessions_uri="/SessionService/Sessions"
    # 2. Handle "all" logic
    if [[ "$target_id" == "all" ]]; then
        echo -e "Attempting to delete all removable sessions on ${BOLD}${BMC_HOST}${RESET}..."
        
        local sessions
        sessions=$(rf_get "$sessions_uri" | jq -r '.Members[]."@odata.id"' 2>/dev/null)
        
        if [[ -z "$sessions" ]]; then
            info "No sessions found to delete."
            return 0
        fi

        for session_uri in $sessions; do
            local id="${session_uri##*/}"
            printf "Deleting Session ID: %s... " "$id"
            rf_delete "${session_uri#$REDFISH_BASE}" && echo -e "${SUCCESS}Done${RESET}" || echo -e "${ERROR}Failed${RESET}"
        done
    else
        # 3. Handle specific Session ID
        local session_uri="${sessions_uri}/${target_id}"
        echo -e "Deleting Session ID: ${BOLD}${target_id}${RESET}..."
        
        rf_delete "$session_uri" && {
            echo -e "session ${SUCCESS}${target_id}${RESET} deleted successfully."
        } || {
            err -e "Error: Could not delete session ${target_id}. (It might still be running or protected)"
            return 1
        }
    fi
}

list_sessions() {
    #rf_get "/" | jq '"RedfishVersion=\(.RedfishVersion)"'
   #rf_get "/SessionService" | jq '\(.SessionTimeout)'  #fail
   #  rf_get "/SessionService" | jq '"\(.SessionTimeout)"'  #"30"
   # rf_get "/SessionService" | jq '.SessionTimeout'       #30
   # rf_get "/SessionService" | jq '"SessionTimeout=\(.SessionTimeout)"' 
    rf_get "/SessionService" | jq -r '"SessionTimeout=\(.SessionTimeout)"'
   # rf_get "/SessionService" | jq -r '"\"SessionTimeout\"=\(.SessionTimeout)"'
    # 1. Define the Sessions collection path
    # Standard Redfish path: /redfish/v1/SessionService/Sessions
    local sessions_uri="/SessionService/Sessions"
    
    local data
    data=$(rf_get "$sessions_uri" 2>/dev/null) || { 
        warn "Session Service not available at $sessions_uri"; 
        return; 
    }

    # 2. Get total count of active sessions
    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        info "No active sessions found."
        return
    fi

    local DATA_TYPE='Active Session Inventory'
    local current=0
    echo "Fetching Active Sessions... Total: $total" >&2

    # 3. Extract detailed information for each session
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r session_uri; do
        ((current++))
        printf "\rProcessing Session: [%d/%d]...   " "$current" "$total" >&2
        
        # Note: Some BMCs may restrict viewing details of sessions other than your own
        rf_get "${session_uri#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            UserName: .UserName,
            ClientOriginIPAddress: (.ClientOriginIPAddress // "N/A"),
            SessionType: (.SessionType // "N/A")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. Integrate structured data
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV data for formatting
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Session ID", "User", "Source IP", "Type"] | @tsv), 
        (.Data[] | [.Id, .UserName, .ClientOriginIPAddress, .SessionType] | @tsv)
    ')

    # 6. Formatted Output
    export TABLE_FMT="fancy_grid"
 
    local host type count
    read -r host type < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total ${type} Entities: ${BOLD}${count}${RESET}"

}

# ---------------------------------------------------------------------------
# ─────────────────────────────  TASKS  ─────────────────────────────────
# ---------------------------------------------------------------------------
cmd_task() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish tasks <node>"
 
    local section="${2:-list}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    case "$section" in
    list)
        list_tasks;;
    del)  
        del_tasks $3;;

    *)    die "Unknown task section: $section  (list | del )" ;;
    esac
}

del_tasks() {
    local target_id="$1"

    if [[ -z "$target_id" ]]; then
        echo "Usage: del [TaskID | all]"
        return 1
    fi

    # 1. Define the Task Collection path
    local task_collection_uri="/TaskService/Tasks"

    # 2. Handle "all" logic
    if [[ "$target_id" == "all" ]]; then
        echo -e "Attempting to delete all removable tasks on ${BOLD}${BMC_HOST}${RESET}..."
        
        local tasks
        tasks=$(rf_get "$task_collection_uri" | jq -r '.Members[]."@odata.id"' 2>/dev/null)
        
        if [[ -z "$tasks" ]]; then
            echo "No tasks found to delete."
            return 0
        fi

        for task_uri in $tasks; do
            local id="${task_uri##*/}"
            printf "Deleting Task ID: %s... " "$id"
            rf_delete "${task_uri#$REDFISH_BASE}" && echo -e "${SUCCESS}Done${RESET}" || echo -e "${ERROR}Failed${RESET}"
        done
    else
        # 3. Handle specific Task ID
        local task_uri="${task_collection_uri}/${target_id}"
        echo -e "Deleting Task ID: ${BOLD}${target_id}${RESET}..."
        
        rf_delete "$task_uri" && {
            echo -e "Task ${SUCCESS}${target_id}${RESET} deleted successfully."
        } || {
            err -e "Error: Could not delete task ${target_id}. (It might still be running or protected)"
            return 1
        }
    fi
}
list_tasks() {
    # 1. Define the Task Collection path
    # Standard Redfish path: /redfish/v1/TaskService/Tasks
    local task_collection_uri="/TaskService/Tasks"
    local data
    data=$(rf_get "$task_collection_uri" 2>/dev/null) || { 
        warn "Task Service not available at $task_collection_uri"; 
        return; 
    }

    # 2. Get total count of tasks
    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No tasks found in TaskService."
        return
    fi

    local DATA_TYPE='Tasks'
    local current=0
    echo "Fetching Tasks... Total: $total" >&2

    # 3. Extract detailed information for each task
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r task_uri; do
        ((current++))
        printf "\rProcessing Task: [%d/%d]...   " "$current" "$total" >&2
        
        rf_get "${task_uri#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            Name: .Name,
            TaskState: .TaskState,
            TaskStatus: .TaskStatus,
            PercentComplete: (if .PercentComplete != null then (.PercentComplete | tostring + "%") else "N/A" end),
            # This cleans 2026-05-06T10:34:04+08:00 -> 2026-05-06 10:34:04
            StartTime: (.StartTime | sub("T"; " ") | sub("\\+.*"; "")) ,
            EndTime: (.EndTime | sub("T"; " ") | sub("\\+.*"; "") // "In Progress")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. Integrate structured data
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV data for formatting
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "State", "Status", "Progress", "Start Time", "End Time"] | @tsv), 
        (.Data[] | [.Id, .Name, .TaskState, .TaskStatus, .PercentComplete, .StartTime, .EndTime] | @tsv)
    ')

    # 6. Formatted Output
    export TABLE_FMT="fancy_grid"

    local host type count 
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')


    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Tasks Entities: ${BOLD}${count}${RESET}"
}

# ---------------------------------------------------------------------------
# ─────────────────────────────  INVENTORY  ─────────────────────────────────
# ---------------------------------------------------------------------------
cmd_inventory() {
 
    local node="$1"
    [[ -z "$node" ]] && die "Usage: $SCRIPT_NAME redfish inventory <node>"
 
    local section="${2:-none}"

    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

    sys_col="$(rf_get "/Systems")"
    [ -z "$sys_col" ] && die "$node:$BMC_HOST:$BMC_USER connection fail!"



    local sys_path
    sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')"
    local sys_rel="${sys_path#$REDFISH_BASE}"

    chassis_col="$(rf_get "/Chassis")"
    [ -z "$chassis_col" ] && die "$node:$BMC_HOST:$BMC_USER connection fail!"
  
    local chassis_path
    chassis_path="$(echo "$chassis_col" | jq -re '.Members[0]["@odata.id"]')"
    local chassis_rel="${chassis_path#$REDFISH_BASE}"


    #log "$sys_path"
    #log "$BMC_HOST"
    case "$section" in

 #   all)
 #       _inv_manager
 #       _inv_firmware
 #       _inv_system
 #       _inv_cpu  
 #       _inv_gpu  
 #       _inv_mem  
 #       _inv_pci
 #       _inv_psu
 #       ;;
          
    role)  _inv_roles ;;      
    user)  _inv_users ;;
    license)  _inv_license ;;   
    bmc | manager)  _inv_manager ;;   
    fw | firmware)  _inv_firmware ;;
    nic) _inv_nics_bmc
        _inv_nics_host ;;

    sys*)  _inv_system ;;
    cha*)  _inv_chassis ;;
    fru)  _inv_fru ;;
    cpu)  _inv_cpu ;;
    gpu)  _inv_gpu ;;
    mem)  _inv_mem ;;
    pci)  _inv_pci ;;
    psu)  _inv_psu ;;
    storage)  _inv_storage ;;
    test) _inv_test;;


    *)    die "Unknown inventory section: $section  (system | chassis | fru | bmc | cpu | gpu | mem | pci | psu | storage )" ;;
    esac
}
_inv_test() {
#get_power_resettype  
_inv_tasks
exit
  rf_get "/" | jq '"RedfishVersion=\(.RedfishVersion)"'
   #rf_get "/SessionService" | jq '\(.SessionTimeout)'  #fail
     rf_get "/SessionService" | jq '"\(.SessionTimeout)"'  #"30"
    rf_get "/SessionService" | jq '.SessionTimeout'       #30
    rf_get "/SessionService" | jq '"SessionTimeout=\(.SessionTimeout)"' 
    rf_get "/SessionService" | jq -r '"SessionTimeout=\(.SessionTimeout)"'
    rf_get "/SessionService" | jq -r '"\"SessionTimeout\"=\(.SessionTimeout)"'

    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    rf_get "${system_path#$REDFISH_BASE}" 2>/dev/null | jq -r '.PowerState' 

     info "Sending PowerOn to $name …"
        local resp
        rf_post "${sys_path#$REDFISH_BASE}/Actions/ComputerSystem.Reset" \
                        '{"ResetType":"On"}' | jq
    rf_get "${system_path#$REDFISH_BASE}" 2>/dev/null | jq -r '.PowerState'  
    curl -k -u test:gigabyte@123 -X POST "https://10.1.9.86/redfish/v1/Systems/Self/Actions/ComputerSystem.Reset" -H "Content-Type: application/json" -d '{\"ResetType\": \"on\"}'  | jq 
}

_inv_nics_host() {
    # 1. Discover the System path
    local system_path
    #for ASUS
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/EthernetInterfaces" 2>/dev/null) || { warn "NIC collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    local current=0 
    local DATA_TYPE='System_LAN'

    # 2. Collect individual NIC data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r nic; do
            ((current++))
            printf "\rProcessing: [%d/%d] %s...   " "$current" "$total" "${nic##*/}" >&2
            
            rf_get "${nic#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Status: (.Status.State // "Unknown"),
                LinkStatus: (.LinkStatus // "NoLink"),
                Speed: (if .SpeedMbps != null then (.SpeedMbps | tostring) + " Mbps" else "N/A" end),
                MAC: (.MACAddress // "N/A"),
                IPv4Addresses: .IPv4Addresses[0].Address,
                VLAN: (if .VLAN != null then "Enabled" else "Disabled" end)
            }'
        done | jq -s '.'
    )
    printf "\n" >&2

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "MAC Address", "Speed", "Link", "IPv4Addresses","Status"] | @tsv), 
        (.Data[] | [.Id, .Name, .MAC, .Speed, .LinkStatus, .IPv4Addresses,.Status] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"
 

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Interfaces: ${BOLD}${count}${RESET}"
}
_inv_nics_bmc() {
    # 1. Discover the System path
    local system_path
    #for ASUS
    system_path=$(rf_get "/Managers" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/EthernetInterfaces" 2>/dev/null) || { warn "NIC collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    local current=0 
    local DATA_TYPE='BMC_LAN'

    # 2. Collect individual NIC data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r nic; do
            ((current++))
            printf "\rProcessing: [%d/%d] %s...   " "$current" "$total" "${nic##*/}" >&2
            
            rf_get "${nic#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Status: (.Status.State // "Unknown"),
                LinkStatus: (.LinkStatus // "NoLink"),
                Speed: (if .SpeedMbps != null then (.SpeedMbps | tostring) + " Mbps" else "N/A" end),
                MAC: (.MACAddress // "N/A"),
                IPv4Addresses: .IPv4Addresses[0].Address,
                VLAN: (if .VLAN != null then "Enabled" else "Disabled" end)
            }'
        done | jq -s '.'
    )
    printf "\n" >&2

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "MAC Address", "Speed", "Link", "IPv4Addresses", "Status"] | @tsv), 
        (.Data[] | [.Id, .Name, .MAC, .Speed, .LinkStatus, .IPv4Addresses, .Status] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"
    local run_python='python3 -c "
import sys, os
try:
    from tabulate import tabulate
    data = [line.strip().split(\"\t\") for line in sys.stdin if line.strip()]
    if data:
        headers = data.pop(0)
        fmt = os.getenv(\"TABLE_FMT\", \"fancy_grid\")
        print(tabulate(data, headers=headers, tablefmt=fmt))
except ImportError:
    sys.exit(1)
"'

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$run_python" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Interfaces: ${BOLD}${count}${RESET}"
}

_inv_firmware() {
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    # Fetch the core System resource data [cite: 121, 122]
    BiosVersion=$(rf_get "${system_path#$REDFISH_BASE}" 2>/dev/null | jq -r '.BiosVersion' ) || { warn "System data not available"; return; }

    # 1. Discover the Firmware Inventory collection
    local data
    data=$(rf_get "/UpdateService/FirmwareInventory" 2>/dev/null) || { 
        warn "Firmware Inventory not available"; 
        return; 
    }

    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No firmware entries found"
        return
    fi

    local current=0 
    local DATA_TYPE='Firmware'

    # 2. Collect individual Firmware data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r fw_uri; do
            ((current++))
            printf "\rProcessing Firmware: [%d/%d] %s...   " "$current" "$total" "${fw_uri##*/}" >&2
            
            # 取得個別元件的韌體詳細資訊
            rf_get "${fw_uri#$REDFISH_BASE}" | jq -c --arg biosver "$BiosVersion" '{
                Id: .Id,
                Name: .Name,
                Version: (.Version // $biosver// "N/A"),
                Updateable: (.Updateable // "Unknown"),
                Status: (.Status.State // "Enabled"),
                Health: (.Status.Health // "OK")
            }'
        done | jq -s '.'
    )
    printf "\n" >&2
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "Version", "Updateable", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Version, .Updateable, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Firmware Entities: ${BOLD}${count}${RESET}"
}

_inv_license() {
    # 1. Discover the License collection
    local data
    data=$(rf_get "/LicenseService/Licenses" 2>/dev/null) || { 
        warn "License Service not available or no licenses found"; 
        return; 
    }
    if echo "$data" | jq -e '.error' >/dev/null 2>&1 ; then
        warn "License Service not available or no licenses found"; 
        return; 
    fi

    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        ok "No active licenses detected."
        return
    fi

    local current=0 
    local DATA_TYPE='License'

    # 2. Collect individual License data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r lic_uri; do
            ((current++))
            printf "\rProcessing License: [%d/%d]...   " "$current" "$total" >&2
            
            rf_get "${lic_uri#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                LicenseType: (.LicenseType // "N/A"),
                AuthorizationScope: (.AuthorizationScope // "N/A"),
                EntitlementId: (.EntitlementId // "N/A"),
                Status: (.Status.Health // "OK"),
                ExpirationDate: (.ExpirationDate // "Never")
            }'
        done | jq -s '.'
    )
    printf "\n" >&2
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "Type", "Scope", "Expiration", "Status"] | @tsv), 
        (.Data[] | [.Id, .Name, .LicenseType, .AuthorizationScope, .ExpirationDate, .Status] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
}

_inv_manager() {
    # 1. Discover the Managers collection
    local data
    data=$(rf_get "/Managers" 2>/dev/null) || { warn "Managers collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No managers found"
        return
    fi

    local current=0 
    local DATA_TYPE='Manager Inventory'

    # 2. Collect individual Manager data
    # We iterate through the collection to support systems with multiple management controllers
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r manager_uri; do
            ((current++))
            printf "\rProcessing Manager: [%d/%d] %s...   " "$current" "$total" "${manager_uri##*/}" >&2
            
            rf_get "${manager_uri#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Type: (.ManagerType // "N/A"),
                Firmware: (.FirmwareVersion // "N/A"),
                Model: (.Model // "N/A"),
                DateTime: (.DateTime // "N/A"),
                DateTimeLocalOffset,
                UUID,
                Health: (.Status.Health // "OK"),
                State: (.Status.State // "Enabled")
            }'
        done | jq -s '.'
    )
    printf "\n" >&2
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Type", "Firmware", "Model", "DateTime", "UUID", "Health"] | @tsv), 
        (.Data[] | [.Id, .Type, .Firmware, .Model, .DateTime, .UUID, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
}  
_inv_system() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    # Fetch the core System resource data [cite: 121, 122]
    data=$(rf_get "${system_path#$REDFISH_BASE}" 2>/dev/null) || { warn "System data not available"; return; }

    local DATA_TYPE='System'

    # 2. Collect System-level data (Adding UUID and LED Indicator)
    local jsondata
    jsondata=$(echo "$data" | jq -c '[{
        Id: (.Id // "N/A"),
        Name: (.Name // "N/A"),
        Description,
        PowerState: (.PowerState // "Unknown"),
        Health: (.Status.Health // "OK"),
        Model: (.Model // "N/A"),
        PartNumber,
        SerialNumber: (.SerialNumber // "N/A"),
        AssetTag,
        Manufacturer,
        SystemType,
        SKU,
        UUID: (.UUID // "N/A"),
        # Fetch LED status; check LocationIndicatorActive if IndicatorLED is null [cite: 2, 7]
        LED: (.IndicatorLED // (if .LocationIndicatorActive == true then "Blinking (Active)" elif .LocationIndicatorActive == false then "Off" else "N/A" end)),
        BiosVersion: (.BiosVersion // "N/A")
    }]')
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Model", "SerialNumber", "AssetTag","UUID", "Power State", "BIOS Version","LED State","SystemType", "Manufacturer","Health"] | @tsv), 
        (.Data[] | [.Model, .SerialNumber, .AssetTag, .UUID, .PowerState, .BiosVersion, .LED, .SystemType, .Manufacturer, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total ${type} Entities: ${BOLD}${count}${RESET}"
}
_inv_chassis() {
    # 1. Discover the Chassis collection
    local data
    data=$(rf_get "/Chassis" 2>/dev/null) || { warn "Chassis collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No chassis members found"
        return
    fi

    local current=0 
    local DATA_TYPE='Chassis'

    # 2. Collect individual Chassis data
    # We iterate through the collection because systems may have multiple chassis (e.g., sleds in a drawer)
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r chassis_uri; do
            ((current++))
            printf "\rProcessing Chassis: [%d/%d] %s...   " "$current" "$total" "${chassis_uri##*/}" >&2
            
            rf_get "${chassis_uri#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Type: (.ChassisType // "N/A"),
                Manufacturer: (.Manufacturer // "N/A"),
                Model: (.Model // "N/A"),
                SerialNumber: (.SerialNumber // "N/A"),
                Health: (.Status.Health // "OK"),
                State: (.Status.State // "Enabled")
            }'
        done | jq -s '.'
    )
    printf "\n" >&2
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')
    #dbg echo $jsondata1 | jq
    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Type", "Manufacturer", "Model", "Serial Number", "Health"] | @tsv), 
        (.Data[] | [.Id, .Type, .Manufacturer, .Model, .SerialNumber, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')
    

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total ${type} Entities: ${BOLD}${count}${RESET}"
}
_inv_fru() {
    # 檢查是否有必要的 IPMI 連線變數，若無則報錯退出 (沿用您的工具鏈風格)
    if [ -z "$BMC_HOST" ] || [ -z "$BMC_USER" ] || [ -z "$BMC_PASS" ]; then
        warn "IPMI credentials not set. Cannot fetch FRU info."
        return 1
    fi

    local fru_data
    printf "Fetching FRU information via ipmitool... \r" >&2

    # 執行 ipmitool 獲取原始資料
    fru_data=$(ipmitool -I lanplus -H "$BMC_HOST" -U "$BMC_USER" -P "$BMC_PASS" fru print 2>/dev/null)
    
    if [ -z "$fru_data" ]; then
        warn "Failed to retrieve FRU data or FRU is empty."
        return 1
    fi

    # 清除 "Processing..." 提示字元
    printf "                                            \r" >&2

    # 直接輸出完整 FRU 資訊
    echo "$fru_data"
}

_inv_fru_asus() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }

    # 2. Access the dedicated Fru sub-resource
    # Priority: /Chassis/{Id}/Fru -> Fallback: /Chassis/{Id}
    local fru_data
    fru_path=$(rf_get "${chassis_path#$REDFISH_BASE}" | jq -re '.Fru["@odata.id"]') || { warn "Dedicated Fru resource not found, falling back to base Chassis data..."; return; }
 
    fru_data=$(rf_get "${fru_path#$REDFISH_BASE}" ) || { 
        warn "Dedicated Fru resource not found, falling back to base Chassis data...";
        fru_data=$(rf_get "${chassis_path#$REDFISH_BASE}" 2>/dev/null); 
    }
    local DATA_TYPE='FRU'
    #dbg echo "$fru_data" | jq
    # 3. Extract FRU data
    local jsondata
    jsondata=$(echo "$fru_data" | jq -c '[{
        Manufacturer: (.FruInfo.Board.BoardManufacturer // "N/A"),
        Model: (.FruInfo.Board.BoardProduct // "N/A"),
        PartNumber: (.FruInfo.Chassis.ChassisPartNumber // "N/A"),
        SerialNumber: (.FruInfo.Board.BoardSerial // "N/A"),
        AssetTag: (.AssetTag // "N/A")
    }]')

    # 4. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Manufacturer", "Model", "Serial Number", "Part Number", "Asset Tag"] | @tsv), 
        (.Data[] | [.Manufacturer, .Model, .SerialNumber, .PartNumber, .AssetTag] | @tsv)
    ')

    # 6. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type
    read -r host type < <(echo "$jsondata1" | jq -r '[.Host, .Type] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
}
_inv_cpu() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/Processors" 2>/dev/null) || { warn "Processor collection not available"; return; } 

    local total=$(echo "$data" | jq '.Members | length')
    local current=0 
    local DATA_TYPE='CPU'

    # 2. Collect individual CPU data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r proc; do
            ((current++))
            printf "\rProcessing: [%d/%d] %s...   " "$current" "$total" "${proc##*/}" >&2

            # Fetch details and filter specifically for CPUs
            local details
            details=$(rf_get "${proc#$REDFISH_BASE}" 2>/dev/null)
            # Only process if ProcessorType is CPU
            if echo "$details" | jq -e '.ProcessorType == "CPU"' >/dev/null 2>&1; then
                echo "$details" | jq -c '{
                    Id,
                    Socket: .Socket,
                    Model: (.Model | gsub("\\s*,.*$"; "") ), 
                    Architecture: .ProcessorArchitecture,
                    Cores: .TotalCores,
                    Threads: .TotalThreads,
                    OperatingSpeed: (if .OperatingSpeedMHz != null then (.OperatingSpeedMHz | tostring) + " MHz" else "N/A" end),
                    MaxSpeed: (if .MaxSpeedMHz != null then (.MaxSpeedMHz | tostring) + " MHz" else "N/A" end),
                    ProcessorType,
                    Status: (.Status.State // .Status // "Unknown"),
                    Health: (.Status.Health // "OK")
                }'
            fi
       done | jq -s '.'
    )
    printf "\n" >&2

    ok "$DATA_TYPE collection complete!"

    # Model: (.Model | split(",")[0] | if length > 40 then .[0:37] + "..." else . end), .ProcessorId.EffectiveFamily
    # Model: (.Model | sub(", "; ",\n") 
    #Model: (.Model | [scan(".{1,30}")] | join("@@")),
    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Socket", "Model",  "Arch","Cores", "Threads","OperatingSpeed","MaxSpeed", "ProcessorType","Status","Health"] | @tsv), 
        (.Data[] | [.Id, .Socket, .Model, .Architecture, .Cores, .Threads, .OperatingSpeed, .MaxSpeed, .ProcessorType, .Status, .Health] | @tsv)
    ')
    #echo "$tsvdata" | od -t x1
    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total CPUs: ${BOLD}${count}${RESET}"
}
_inv_gpu() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/Processors" 2>/dev/null) || { warn "Processor collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    local current=0 
    local DATA_TYPE='GPU Inventory'

    # 2. Collect individual GPU data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r proc; do
            ((current++))
            printf "\rScanning Processors: [%d/%d] %s...   " "$current" "$total" "${proc##*/}" >&2
            
            # Fetch details and filter specifically for GPUs
            local details
            details=$(rf_get "${proc#$REDFISH_BASE}" 2>/dev/null)
            
            # Only process if ProcessorType is GPU
            if echo "$details" | jq -e '.ProcessorType == "GPU"' >/dev/null 2>&1; then
                echo "$details" | jq -c '{
                    Id: .Id,
                    Name: .Name,
                    Model: .Model,
                    Manufacturer: .Manufacturer,
                    Cores: (.TotalCores // "N/A"),
                    Status: (.Status.State // "Unknown"),
                    Health: (.Status.Health // "OK")
                }'
            fi
        done | jq -s '.'
    )Systems
    printf "\n" >&2
  
    # Check if any GPUs were actually found
    local count=$(echo "$jsondata" | jq 'length')
    if [ "$count" -eq 0 ]; then
        warn "No GPUs detected in Processor collection"
        return
    fi
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Name", "Manufacturer", "Model", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Manufacturer, .Model, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type
    read -r host type < <(echo "$jsondata1" | jq -r '.Host, .Type')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total GPUs Found: ${BOLD}${count}${RESET}"
}

_inv_mem() {
    # 1. Discover the System path (Memory is usually under /Systems)
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/Memory" 2>/dev/null) || { warn "Memory collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length')
    local current=0 
    local DATA_TYPE='Memory'

    # 2. Collect individual DIMM data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r dimm; do
            ((current++))
            printf "\rProcessing: [%d/%d] %s...   " "$current" "$total" "${dimm##*/}" >&2
            
            rf_get "${dimm#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Manufacturer: .Manufacturer,
                PartNumber,
                SerialNumber,
                ErrorCorrection: (.ErrorCorrection//"N/A"),
                BaseModuleType,
                Socket: .DeviceLocator,
                Type: .MemoryDeviceType,
                Size: (((.CapacityMiB // 0) / 1024 | tostring) + " GB"),
                Speed: ((.OperatingSpeedMhz | tostring) + " MHz"),
                Status: (.Status.State // .Status // "Unknown"),
                Health: (.Status.Health //  "Unknown")
            }'
        done | jq -s '.'
        printf "\n" >&2

    )
    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Manufacturer","PartNumber",
                "SerialNumber","ErrorCorrection","Locator", "Type", "BaseModuleType", "Size", "Speed", "Status", "Health"] | @tsv), 
        (.Data[] | [.Id, .Manufacturer, .PartNumber,
                .SerialNumber, .ErrorCorrection, .Socket, .Type, .BaseModuleType, .Size, .Speed, .Status, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total DIMMs: ${BOLD}${count}${RESET}"
}


_inv_pcieslot() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    local data
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/PCIeSlots" 2>/dev/null) || { warn "PCIeSlots collection not available"; return; }

    local total=$(echo "$data" | jq '.Slots | length')
    local current=0 
    local DATA_TYPE='PCIeSlots'

    # 2. Extract Slot Data
    # Note: PCIeSlots is often a single resource containing an array of 'Slots' 
    # rather than a collection of members. We handle both possibilities.
    local jsondata
    jsondata=$(
        echo "$data" | jq -c '.Slots[]' | while read -r slot; do
            ((current++))
            printf "\rProcessing Slot: [%d/%d]..." "$current" "$total" >&2
            
            echo "$slot" | jq -c '{
                Slot: .Id,
                Type: .SlotType,
                Lanes: .Lanes,
                Generation: .Generation,
                Status: (.Status.State // "Unknown")
            }'
        done | jq -s '.'
        printf "\n" >&2

    )

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Slot", "Type", "Lanes", "Generation", "Status"] | @tsv), 
        (.Data[] | [.Slot, .Type, .Lanes, .Generation, .Status] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Slots: ${BOLD}${count}${RESET}"
}
_inv_pci() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    # 2. Access the PCIeDevices collection
    local pcie_data
    pcie_data=$(rf_get "${chassis_path#$REDFISH_BASE}/PCIeDevices" 2>/dev/null) || { 
        warn "PCIe Devices collection not available"; 
        return; 
    }

    local total_devices=$(echo "$pcie_data" | jq '.Members | length // 0')
    if [ "$total_devices" -eq 0 ]; then
        warn "No PCIe devices detected."
        return
    fi

    local current=0 
    local DATA_TYPE='PCIe'

    # 3. Iterate through Devices to get Functions
    local jsondata
    jsondata=$(
        echo "$pcie_data" | jq -r '.Members[]."@odata.id"' | while read -r device_uri; do
            #$(rf_get "${device_uri#$REDFISH_BASE} | jq '{DeviceType,MultiFunction,Id,Name}'
            deviceBD=$(rf_get "${device_uri#$REDFISH_BASE}" | jq -r '.Id' )
            DeviceType=$(rf_get "${device_uri#$REDFISH_BASE}" | jq -r '.DeviceType' )
            
            # Get the Function collection for each device
            local functions_data
            functions_data=$(rf_get "${device_uri#$REDFISH_BASE}/PCIeFunctions" 2>/dev/null)
            if [[ -n "$functions_data" ]]; then
                echo "$functions_data" | jq -r '.Members[]."@odata.id"' | while read -r func_uri; do
                    ((current++))
                    printf "\rProcessing PCIe Function: [%s][%d]...   " "$deviceBD" "$current" >&2
                    
                    rf_get "${func_uri#$REDFISH_BASE}" | jq -c  --arg dev "$deviceBD" --arg type "$DeviceType" '{
                        Device: $dev,
                        DeviceType: $type,
                        Id: .Id,
                        Name: .Name,
                        FunctionId: (.FunctionId // "0"),
                        FunctionType: (.FunctionType // "N/A"),
                        DeviceClass: (.DeviceClass // "N/A"),
                        VendorId: (.VendorId // "N/A"),
                        DeviceId: (.DeviceId // "N/A"),
                        SubsystemVendorId: (.SubsystemVendorId // "N/A"),
                        Status: (.Status.State),
                        Health: (.Status.Health)
                    }' || warn "$func_uri"
                done
            fi
        done | jq -s '.'
    )
    printf "\n" >&2

    # 4. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["BusDev","TYPE", "ID", "Class", "Type", "Vendor ID", "DeviceID", "FunctionID","Status", "Health"] | @tsv), 
        (.Data[] | [.Device, .DeviceType, .Id, .DeviceClass, .FunctionType, .VendorId, .DeviceId, .FunctionId, .Status, .Health] | @tsv)
    ')

    # 6. Output Formatting
    export TABLE_FMT="fancy_grid"
 
    local host type
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')


    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Count: ${BOLD}${count}${RESET}"
}

_inv_psu() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    # 2. Try the modern PowerSubsystem first, fallback to legacy Power resource
    local data
    local DATA_TYPE='PowerSupplies'
    
    # Try modern schema
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/PowerSubsystem/PowerSupplies" 2>/dev/null)
    # Check if the response contains an error or is missing
    # We check if 'data' is empty OR if it contains the "error" key from Redfish
    if echo "$data" | jq -e '.error' >/dev/null 2>&1 || [[ -z "$data" ]]; then
        # Fallback to legacy Power resource and extract PowerSupplies array
        data=$(rf_get "${chassis_path#$REDFISH_BASE}/Power" 2>/dev/null | jq -c '{Members: .PowerSupplies}')
    fi

    [[ -z "$data" || "$data" == "null" ]] && { warn "PSU information not available"; return; }
    #echo "ddddddddddddddddddddddddddddddddd"
    #echo $data | jq
    #local total=$(echo "$data" | jq '.Members | length // 0')
    #local current=0 
    #dbg echo "$data" | jq '.Members'
    # 3. Collect individual PSU data
    local jsondata
    jsondata=$(
         echo "$data" | jq -c  '.Members[] | {
                Id: .MemberId,
                Name,
                Manufacturer,
                Capacity: (((.PowerCapacityWatts | tostring) // "0") + " W"),
                Firmware: .FirmwareVersion,
                SerialNumber: .SerialNumber,
                PowerInputWatts,
                PowerOutputWatts,
                PowerSupplyType,
                State: (.Status.State // .Status // "Unknown"),
                Health: (.Status.Health // "--")
            }' | jq -s
    )    
    #printf "\n" >&2 # Move to new line after progress bar
    #dbg echo $jsondata | jq -c
     # Check if any $DATA_TYPE were actually found
    local count=$(echo "$jsondata" | jq 'length')
    if [ "$count" -eq 0 ]; then
        warn "No $DATA_TYPE detected in Chassis collection"
        return
    fi
  
    ok "$DATA_TYPE collection complete!"

    # 4. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Name", "Manufacturer", "Capacity", "Firmware", "SerialNumber", "PowerSupplyType", "State" ,"Health"] | @tsv), 
        (.Data[] | [ .Id, .Name , .Manufacturer, .Capacity, .Firmware, .SerialNumber, .PowerSupplyType, .State, .Health] | @tsv)
    ')

    # 6. Output Formatting
    export TABLE_FMT="fancy_grid"

     local host type count
    #ok read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count' | tr '\n' ' ')
    #fail IFS=$'\n' read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count')
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")') #ok
    #fail read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count')
    #read -r host type count < <(echo -e "1\n2\n3" | tr '\n' ' ')
    #echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")'
#echo "Host: $host"
#echo "Type: $type"
#echo "Count: $count"
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total PSUs: ${BOLD}${count}${RESET}"
} 

_inv_storage() {
    # 1. Discover the System path
    local system_path
    system_path=$(rf_get "/Systems" | jq -re '.Members[0]["@odata.id"]') || { warn "System path not found"; return; }
    
    local data
    data=$(rf_get "${system_path#$REDFISH_BASE}/Storage" 2>/dev/null) || { warn "Storage collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length')
    local current=0 
    local DATA_TYPE='Storage'

    # 2. Collect individual Storage Controller data
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r ctrl; do
            ((current++))
            printf "\rProcessing: [%d/%d] %s...   " "$current" "$total" "${ctrl##*/}" >&2
            
            # Fetching Controller details
            # Note: We also extract the drive count if available in the summary
            rf_get "${ctrl#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Model: (.StorageControllers[0].Model // "N/A"),
                Protocols: (.StorageControllers[0].SupportedDeviceProtocols | join(", ") // "Unknown"),
                Status: (.Status.State // .Status // "Unknown"),
                Drives: (.Drives | length // 0)
            }'
        done | jq -s '.'
    )
    printf "\n" >&2

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Name", "Model", "Protocols", "Drives", "Status"] | @tsv), 
        (.Data[] | [.Id, .Name, .Model, .Protocols, .Drives, .Status] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Controllers: ${BOLD}${count}${RESET}"
}
_inv_fan() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    local data
    # Fans are standardly found under the Thermal resource
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/Thermal" 2>/dev/null) || { warn "Thermal data not available"; return; }

    local total=$(echo "$data" | jq '.Fans | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No fans detected in Thermal resource"
        return
    fi

    local current=0 
    local DATA_TYPE='Fans'

    # 2. Collect Fan data
    local jsondata
    printf "Processing: Found %d fans...\n" "$total" >&2
    
    jsondata=$(echo "$data" | jq -c '.Fans[] | {
        Id: (.MemberId // .Name),
        Name: .Name,
        Status: (.Status.State // "Unknown"),
        Health: (.Status.Health // "--"),
        # Null-safe reading logic
        Reading: (if .Reading != null then (.Reading | tostring) + (if .ReadingUnits == "Percent" then "%" else " RPM" end) else "N/A" end),
        LowerThreshold: (if .LowerThresholdCritical != null then (.LowerThresholdCritical | tostring) + " RPM" else "N/A" end)
    }')
    
    jsondata=$(echo "$jsondata" | jq -s '.')

    ok "$DATA_TYPE collection complete!"

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Fan Name", "Reading", "LowerThreshold","Status", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Reading, .LowerThreshold, .Status, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Fans: ${BOLD}${count}${RESET}"
}
_inv_voltage() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    local data
    # Voltages are standardly found under the Power resource
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/Power" 2>/dev/null) || { warn "Power data not available"; return; }

    local total=$(echo "$data" | jq '.Voltages | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No voltage sensors detected in Power resource"
        return
    fi

    local current=0 
    local DATA_TYPE='Voltages'

    # 2. Collect Voltage Sensor data
    local jsondata
    printf "Processing: Found %d voltage sensors...\n" "$total" >&2
    
    jsondata=$(echo "$data" | jq -c '.Voltages[] | {
        Id: (.MemberId // .Name),
        Name: .Name,
        Status: (.Status.State // "Unknown"),
        Health: (.Status.Health // "--"),
        Reading: (if .ReadingVolts != null then (.ReadingVolts | tostring) + " V" else "N/A" end),
        UpperThreshold: (if .UpperThresholdCritical != null then (.UpperThresholdCritical | tostring) + " V" else "N/A" end),
        LowerThreshold: (if .LowerThresholdCritical != null then (.LowerThresholdCritical | tostring) + " V" else "N/A" end)
    }')
    
    jsondata=$(echo "$jsondata" | jq -s '.')

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Sensor Name", "Reading", "UpperThreshold", "LowerThreshold","Status", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Reading, .UpperThreshold, .LowerThreshold, .Status, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Voltage Sensors: ${BOLD}${count}${RESET}"
}
_inv_sensor() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    local data
    # Target the unified Sensors collection
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/Sensors" 2>/dev/null) || { warn "Sensor collection not available"; return; }

    local total=$(echo "$data" | jq '.Members | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No sensors found in the collection"
        return
    fi

    local current=0 
    local DATA_TYPE='Sensors'

    # 2. Collect Individual Sensor Data
    # Note: Sensors often require individual fetches from the collection members
    local jsondata
    jsondata=$(
        echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r sensor_uri; do
            ((current++))
            printf "\rProcessing Sensors: [%d/%d] %s...   " "$current" "$total" "${sensor_uri##*/}" >&2
            
            rf_get "${sensor_uri#$REDFISH_BASE}" | jq -c '{
                Id: .Id,
                Name: .Name,
                Type: .ReadingType,
                #Reading: ((.Reading | tostring) + " " + (.ReadingUnits // "")),
                Reading: (if .Reading == null then "N/A" else ((.Reading | tostring) + " " + (.ReadingUnits // "")) end),
                Status: (.Status.State // "Unknown"),
                Health: (.Status.Health // "--")
            }'
        done | jq -s '.'
    )
    printf "\n" >&2

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Sensor Name", "Type", "Reading", "Status", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Type, .Reading, .Status, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Sensors: ${BOLD}${count}${RESET}"
}
_inv_temp() {
    # 1. Discover the Chassis path
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || { warn "Chassis path not found"; return; }
    
    local data
    # Temperatures are located under the Thermal resource
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/Thermal" 2>/dev/null) || { warn "Thermal data not available"; return; }

    local total=$(echo "$data" | jq '.Temperatures | length // 0')
    if [ "$total" -eq 0 ]; then
        warn "No temperature sensors detected"
        return
    fi

    local current=0 
    local DATA_TYPE='Temperature'

    # 2. Collect Temperature data
    local jsondata
    printf "Processing: Found %d temperature sensors...\n" "$total" >&2
    
    jsondata=$(echo "$data" | jq -c '.Temperatures[] | {
        Id: (.MemberId // .Name),
        Name: .Name,
        Status: (.Status.State // "Unknown"),
        Health: (.Status.Health // "--"),
        Reading: (if .ReadingCelsius != null then (.ReadingCelsius | tostring) + "°C" else "N/A" end),
        UpperThreshold: (if .UpperThresholdCritical != null then (.UpperThresholdCritical | tostring) + "°C" else "N/A" end)
    }')
    
    jsondata=$(echo "$jsondata" | jq -s '.')

    # 3. Aggregate into structured object
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 4. Prepare TSV for table
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["ID", "Sensor Name", "Reading", "Upper Critical","Status", "Health"] | @tsv), 
        (.Data[] | [.Id, .Name, .Reading, .UpperThreshold, .Status, .Health] | @tsv)
    ')

    # 5. Output Formatting
    export TABLE_FMT="fancy_grid"


    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '[.Host, .Type, .Count] | join(" ")')

    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    echo "$tsvdata" | eval "$display_table " 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo -e "Total Temperature Sensors: ${BOLD}${count}${RESET}"
}

 
_inv_auditlog() {
    # 1. 自動探索或定義 System 路徑（亦可視環境改為 /Managers 路徑）
    local system_path
    system_path=$(rf_get "/Managers" | jq -re '.Members[0]["@odata.id"]') || {
        warn "System path not found"; return;
    }
    # 2. 獲取 AuditLog Entries 集合
    local entries_path="${system_path#$REDFISH_BASE}/LogServices/AuditLog/Entries"
    local data
    echo $entries_path
    data=$(rf_get "$entries_path" 2>/dev/null) || {
        warn "AuditLog collection not available at $entries_path"; return;
    }

    local total=$(echo "$data" | jq '.Members | length')
    local current=0
    local DATA_TYPE='AuditLog'

    if [ "$total" -eq 0 ]; then
        echo "No audit log entries found."
        return
    fi

    # 3. 逐一讀取各個日誌條目的詳細資料 (Id, Message, Created, Severity)
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r entry; do
        ((current++))
        printf "\rProcessing: [%d/%d] Fetching log instance...   " "$current" "$total" >&2

        rf_get "${entry#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            Created: .Created,
            Severity: (.Severity // "Unknown"),
            Message: (.Message // "N/A")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. 聚合為結構化物件
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. 轉換為 TSV 格式以供表格渲染
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Created Time", "Severity", "Message"] | @tsv),
        (.Data[] | [.Id, .Created, .Severity, .Message] | @tsv)
    ')

    # 6. 輸出表格格式化 (支援 Python tabulate / column)
    export TABLE_FMT="fancy_grid"
    local run_python='python3 -c "
import sys, os
try:
    from tabulate import tabulate
    data = [line.strip().split(\"\t\") for line in sys.stdin if line.strip()]
    if data:
        headers = data.pop(0)
        fmt = os.getenv(\"TABLE_FMT\", \"fancy_grid\")
        print(tabulate(data, headers=headers, tablefmt=fmt))
except ImportError:
    sys.exit(1)
"'

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count')
    
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    #echo "$tsvdata" | eval "$run_python" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo "$tsvdata"
    echo -e "Total Log Entries: ${BOLD}${count}${RESET}"
}
_inv_eventlog() {
    # 1. 自動探索或定義 System 路徑（亦可視環境改為 /Managers 路徑）
    local system_path
    system_path=$(rf_get "/Managers" | jq -re '.Members[0]["@odata.id"]') || {
        warn "System path not found"; return;
    }
    # 2. 獲取 AuditLog Entries 集合
    local entries_path="${system_path#$REDFISH_BASE}/LogServices/EventLog/Entries"
    local data
    echo $entries_path
    data=$(rf_get "$entries_path" 2>/dev/null) || {
        warn "AuditLog collection not available at $entries_path"; return;
    }

    local total=$(echo "$data" | jq '.Members | length')
    local current=0
    local DATA_TYPE='AuditLog'

    if [ "$total" -eq 0 ]; then
        echo "No audit log entries found."
        return
    fi

    # 3. 逐一讀取各個日誌條目的詳細資料 (Id, Message, Created, Severity)
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r entry; do
        ((current++))
        printf "\rProcessing: [%d/%d] Fetching log instance...   " "$current" "$total" >&2

        rf_get "${entry#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            Created: .Created,
            Severity: (.Severity // "Unknown"),
            Message: (.Message // "N/A")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. 聚合為結構化物件
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. 轉換為 TSV 格式以供表格渲染
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Created Time", "Severity", "Message"] | @tsv),
        (.Data[] | [.Id, .Created, .Severity, .Message] | @tsv)
    ')

    # 6. 輸出表格格式化 (支援 Python tabulate / column)
    export TABLE_FMT="fancy_grid"
    local run_python='python3 -c "
import sys, os
try:
    from tabulate import tabulate
    data = [line.strip().split(\"\t\") for line in sys.stdin if line.strip()]
    if data:
        headers = data.pop(0)
        fmt = os.getenv(\"TABLE_FMT\", \"fancy_grid\")
        print(tabulate(data, headers=headers, tablefmt=fmt))
except ImportError:
    sys.exit(1)
"'

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count')
    
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    #echo "$tsvdata" | eval "$run_python" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo "$tsvdata"
    echo -e "Total Log Entries: ${BOLD}${count}${RESET}"
} 
_inv_sellog() {
    # 1. 自動探索或定義 System 路徑（亦可視環境改為 /Managers 路徑）
    local system_path
    system_path=$(rf_get "/Managers" | jq -re '.Members[0]["@odata.id"]') || {
        warn "System path not found"; return;
    }
    # 2. 獲取 AuditLog Entries 集合
    local entries_path="${system_path#$REDFISH_BASE}/LogServices/SEL/Entries"
    local data
    echo $entries_path
    data=$(rf_get "$entries_path" 2>/dev/null) || {
        warn "AuditLog collection not available at $entries_path"; return;
    }

    local total=$(echo "$data" | jq '.Members | length')
    local current=0
    local DATA_TYPE='AuditLog'

    if [ "$total" -eq 0 ]; then
        echo "No audit log entries found."
        return
    fi

    # 3. 逐一讀取各個日誌條目的詳細資料 (Id, Message, Created, Severity)
    local jsondata
    jsondata=$(echo "$data" | jq -r '.Members[]."@odata.id"' | while read -r entry; do
        ((current++))
        printf "\rProcessing: [%d/%d] Fetching log instance...   " "$current" "$total" >&2

        rf_get "${entry#$REDFISH_BASE}" | jq -c '{
            Id: .Id,
            Created: .Created,
            Severity: (.Severity // "Unknown"),
            Message: (.Message // "N/A")
        }'
    done | jq -s '.')
    printf "\n" >&2

    # 4. 聚合為結構化物件
    local jsondata1
    jsondata1=$(echo "$jsondata" | jq -c \
        --arg BMC_HOST "$BMC_HOST" \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Host: $BMC_HOST, Type: $DATA_TYPE, Data: ., Count: length }')

    # 5. 轉換為 TSV 格式以供表格渲染
    local tsvdata
    tsvdata=$(echo "$jsondata1" | jq -r '
        (["Id", "Created Time", "Severity", "Message"] | @tsv),
        (.Data[] | [.Id, .Created, .Severity, .Message] | @tsv)
    ')

    # 6. 輸出表格格式化 (支援 Python tabulate / column)
    export TABLE_FMT="fancy_grid"
    local run_python='python3 -c "
import sys, os
try:
    from tabulate import tabulate
    data = [line.strip().split(\"\t\") for line in sys.stdin if line.strip()]
    if data:
        headers = data.pop(0)
        fmt = os.getenv(\"TABLE_FMT\", \"fancy_grid\")
        print(tabulate(data, headers=headers, tablefmt=fmt))
except ImportError:
    sys.exit(1)
"'

    local host type count
    read -r host type count < <(echo "$jsondata1" | jq -r '.Host, .Type, .Count')
    
    echo -e "Host: ${BOLD}${host}${RESET} | Type: ${BOLD}${type}${RESET}"
    #echo "$tsvdata" | eval "$run_python" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
    echo "$tsvdata"
    echo -e "Total Log Entries: ${BOLD}${count}${RESET}"
} 

# ---------------------------------------------------------------------------
# ─────────────────────────────  LOGS  ──────────────────────────────────────
# ---------------------------------------------------------------------------
cmd_logs() {
 local node="${1:-}";local logtype="${2:-audit}"
 log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

   # _inv_sellog
   # return
   
    local log_svc
    log_svc="$(rf_get "/Managers")"
    local mgr_path
    mgr_path="$(echo "$log_svc" | jq -re '.Members[0]["@odata.id"]')"
    local mgr_rel="${mgr_path#$REDFISH_BASE}"
 
    # Available log services
    local logs_coll
    logs_coll="$(rf_get "${mgr_rel}/LogServices")"
 
    local log_rel=""
    case "${logtype,,}" in
    system|sys)
        # Try Systems first
        local sys_col sys_path
        sys_col="$(rf_get "/Systems")"
        sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')"
        log_rel="${sys_path#$REDFISH_BASE}/LogServices/Log"
        ;;
    sel|bmc)
        log_rel="${mgr_rel}/LogServices/SEL"
        ;;
    audit)
        log_rel="${mgr_rel}/LogServices/AuditLog"
        ;;
    event)
        log_rel="${mgr_rel}/LogServices/EventLog"
        ;;    
    *)
        # Try as a direct log service name under manager
        log_rel="${mgr_rel}/LogServices/${logtype}"
        ;;
    esac
 
    local entries
    entries="$(rf_get "${log_rel}/Entries" 2>/dev/null)" \
        || die "Log service '${logtype}' not found or not accessible"
 
    if [[ "$OUTPUT_FMT" == "json" ]]; then
        emit_json "$entries"
    else
        echo -e "${BOLD}── Log: ${logtype} ────────────────────────────────────────${RESET}"
        printf "%-5s %-24s %-10s %-10s %s\n" "ID" "Created" "Severity" "EntryType" "Message"
        printf '%0.s─' {1..100}; echo
        echo "$entries" | jq -r '.Members[]? | [
            (.Id//"?"),
            (.Created//"?"),
            (.Severity//"?"),
            (.EntryType//"?"),
            (.Message//"?")
        ] | @tsv' | awk -F'\t' '{printf "%-5s %-24s %-10s %-10s %s\n",$1,$2,$3,$4,$5}'
    fi
}
# ---------------------------------------------------------------------------
# ─────────────────────────────  Fan Control  ──────────────────────────────
# ---------------------------------------------------------------------------
get_fan_mode() {
    # 1. 探索第一個 Chassis 路徑
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || {
        warn "Chassis path not found"; return;
    }

    # 2. 獲取 Thermal 資訊
    local data
    data=$(rf_get "${chassis_path#$REDFISH_BASE}/ThermalSubsystem/Fans" 2>/dev/null) || {
        warn "Thermal Fan data not available"; return;
    }
    #echo "$data" | jq -r '.Oem.Ami.FanMode '
    #echo "$data" | jq -r '.Oem.Ami."FanMode@Redfish.AllowableValues"[] '
    #echo "$data" | jq
   
    # 3. 解析 Fan Control Mode (相容標準與 OEM 常見路徑)
    # 許多廠商將其放在 Oem.VendorName.ThermalConfiguration 或相似位置
    local current_mode
    current_mode=$(echo "$data" | jq -r '.Oem.Ami.FanMode ')
    
    echo -e "Host: ${BOLD}${BMC_HOST}${RESET} | Fan Control Mode: ${BOLD}${current_mode}${RESET}"
} 

set_fan_mode() {
    local target_mode="$1"
    if [[ -z "$target_mode" ]]; then
        warn "Usage: set_fan_mode [Normal|Silent|FullSpeed]"; return;
    fi

    # 1. 探索第一個 Chassis 的 Thermal 路徑
    local chassis_path
    chassis_path=$(rf_get "/Chassis" | jq -re '.Members[0]["@odata.id"]') || {
        warn "Chassis path not found"; return;
    }
    local thermal_uri="${chassis_path#$REDFISH_BASE}/ThermalSubsystem/Fans"

    # 2. 獲取當前 ETag 進行安全防護 (If-Match)
    local raw_res etag
    raw_res=$(rf_get "$thermal_uri") || { warn "Failed to fetch Thermal ETag"; return; }
    etag=$(echo "$raw_res" | jq -r '."@odata.etag" // empty')

    # 3. 根據廠商實際欄位構建 Payload (以下以常見 Oem 欄位封裝為例)
    # 請依您實際伺服器廠牌 (Dell/HPE/Supermicro/Inspur等) 的 json 結構微調欄位名稱
    local payload
    payload=$(jq -nc --arg mode "$target_mode" '
        {
            "Oem": {
                "Ami": {
                    "FanMode": $mode
                }
            }
        }
    ')

    # 4. 發送 PATCH 修改設定
    printf "Changing fan control mode to [%s]...\n" "$target_mode" >&2
    if [[ -n "$etag" ]]; then
        rf_patch "$thermal_uri" "$payload" "$etag" || { warn "Failed to update fan mode"; return; }
    else
        rf_patch "$thermal_uri" "$payload" || { warn "Failed to update fan mode"; return; }
    fi

    echo "Fan control mode updated successfully."
}

cmd_fanctrl() {
    local node="${1:-}"
    local action="${2:-status}"
    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)
    #echo $action
    case "${action,,}" in
 
    silent )
        set_fan_mode Silent
        ;;
    fullspeed )
        set_fan_mode FullSpeed
        ;;
    normal )
        set_fan_mode Normal
        ;;
    status )
        info "Silent | Normal | FullSpeed"
        ;;
    esac
   

    get_fan_mode
}
# ---------------------------------------------------------------------------
# ─────────────────────────────  BIOS SETTING  ──────────────────────────────
# ---------------------------------------------------------------------------
cmd_biossetting() {
    local name="${1:-}"; shift 1 2>/dev/null || true
 
    resolve_bmc "$name"
 
    local sys_col sys_path
    sys_col="$(rf_get "/Systems")"
    sys_path="$(echo "$sys_col" | jq -re '.Members[0]["@odata.id"]')"
    local sys_rel="${sys_path#$REDFISH_BASE}"
 
    local bios
    bios="$(rf_get "${sys_rel}/Bios")"
 
    local key="${1:-}"
    local val="${2:-}"
 
    if [[ -z "$key" ]]; then
        # Display all BIOS attributes
        echo -e "${BOLD}── BIOS Settings — $name ───────────────────────────────${RESET}"
        echo "$bios" | jq -r '.Attributes // {} | to_entries[] | [.key, (.value|tostring)] | @tsv' \
            | column -t -s $'\t'
    elif [[ -z "$val" ]]; then
        # Read single attribute
        echo "$bios" | jq -r --arg k "$key" '.Attributes[$k] // "Attribute not found"'
    else
        # Write single attribute (PendingSettings)
        info "Setting BIOS attribute $key=$val (takes effect after reboot)"
        local resp
        resp="$(rf_patch "${sys_rel}/Bios/Settings" \
                         "{\"Attributes\":{\"${key}\":\"${val}\"}}")"
        _check_action_resp "$resp" "BiosSetting"
    fi
}
 
# ---------------------------------------------------------------------------
# ─────────────────────────────  BMC SETTING  ───────────────────────────────
# ---------------------------------------------------------------------------
set_timezone_offset() {
    # 優先使用傳入的第一個參數，若無則動態取得當前系統時區（例如 +08:00）
    local offset="${1:-$(date +%:z)}"
    local bmc_item="Managers"
    
    # 1. 動態探索取得第一個 Manager 的相對路徑 (例如: /redfish/v1/Managers/bmc)
    local mgr_path
    mgr_path=$(_rf_get_first_member_uri "/redfish/v1/${bmc_item}") || { warn "無法取得 Manager 路徑"; return 1; }

    # 2. 取得該路徑的 ETag 以滿足安全機制
    local etag
    etag=$(_rf_get_etag "${mgr_path}") || { warn "無法取得 ${mgr_path} 的 ETag"; return 1; }

    # 3. 建立 JSON Payload (使用 jq -nc 確保格式正確)
    local payload
    payload=$(jq -nc --arg offset "${offset}" '{"DateTimeLocalOffset": $offset}')

    echo "正在將 ${mgr_path} 的時區偏移量修改為: ${offset}..."

    # 4. 發送 PATCH 請求並進行錯誤攔截
    _rf_raw_request "PATCH" "${mgr_path}" "${payload}" "${etag}" || {
        warn "修改時區失敗，請檢查該 BMC 是否支援手動修改時區，或是否與 NTP 設定衝突。"
        return 1;
    }

    echo "時區修改成功！"
}
set_bmc_datetime() {
    # 1. 動態取得當前系統時間（ISO 8601 格式，如 2026-06-24T16:30:00+08:00）
    # 如果使用者有傳入參數 $1，則優先使用使用者的輸入
    local target_time="${1:-$(date +%Y-%m-%dT%H:%M:%S%:z)}"
    
    # 2. 自動探索第一個 Manager 路徑
    local mgr_path
    mgr_path=$(rf_get "/Managers" | jq -re '.Members[0]["@odata.id"]') || { 
        warn "Manager path not found"; return 1; 
    }
    
    # 3. 取得目前 ETag 以滿足 If-Match 樂觀鎖機制
    local etag
    etag=$(rf_get "${mgr_path#$REDFISH_BASE}" | jq -r '."@odata.etag"')
    
    # 4. 建立最小化（Compressed）的 JSON Payload
    local payload
    payload=$(jq -nc --arg dt "$target_time" '{ DateTime: $dt }')
    
    # 5. 發送 PATCH 請求
    printf "Synchronizing BMC time to: %s...\n" "$target_time" >&2
    rf_patch "${mgr_path#$REDFISH_BASE}" "$payload" "$etag" || { 
        warn "Failed to set BMC datetime"; return 1; 
    }
    
    echo "BMC datetime updated successfully."
}
cmd_bmcsetting() {
    #local name="${1:-}"; shift 1 2>/dev/null || true
 
    local node="${1:-}"
    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

 
    local mgr_col mgr_path
    mgr_col="$(rf_get "/Managers")"
    mgr_path="$(echo "$mgr_col" | jq -re '.Members[0]["@odata.id"]')"
    local mgr_rel="${mgr_path#$REDFISH_BASE}"
 
    local mgr
    mgr="$(rf_get "$mgr_rel")"
 
    local key="${2:-}"
    local val="${3:-}"
 
    if [[ -z "$key" ]]; then
        echo -e "${BOLD}── BMC Manager Settings — $node ────────────────────────${RESET}"
        echo "$mgr" | jq '{
            "Id":              .Id,
            "FirmwareVersion": .FirmwareVersion,
            "ManagerType":     .ManagerType,
            "UUID":            .UUID,
            "State":           .Status.State,
            "Health":          .Status.Health,
            "DateTime":        .DateTime,
            "DateTimeOffset":  .DateTimeLocalOffset
        }' | jq -r 'to_entries[] | [.key, (.value//"")] | @tsv' | column -t -s $'\t'
    else
        # PATCH manager (e.g. DateTime)
        info "Setting BMC $key=$val"
        local resp
        resp="$(rf_patch "$mgr_rel" "{\"${key}\":\"${val}\"}")"
        _check_action_resp "$resp" "BmcSetting"
    fi
}
 
# ---------------------------------------------------------------------------
# ─────────────────────────────  WEB UI  ────────────────────────────────────
# ---------------------------------------------------------------------------
cmd_webui_1() {
    local name="${1:-}"
    resolve_bmc "$name"
    echo $1
    return
    echo "''''''''''''''''''''''''''''''''"
    local url="https://${BMC_HOST}:${BMC_PORT}"
    echo -e "${BOLD}BMC Web UI for $name:${RESET}  $url"
    # Try to open in browser (works on macOS/Linux desktop)
    if command -v xdg-open &>/dev/null; then
        xdg-open "$url" 2>/dev/null &
    elif command -v open &>/dev/null; then
        open "$url" 2>/dev/null &
    else
        info "Open your browser and navigate to: $url"
    fi
}
 
# ---------------------------------------------------------------------------
# ─────────────────────────────  FIRMWARE  ──────────────────────────────────
# ---------------------------------------------------------------------------
cmd_firmware() {
    local node="${1:-}"
    local action="${2:-list}"
    log "Loading config for node: $node"
    ensure_node "$node"

    BMC_HOST=$(get_node_field "$node" host)
    BMC_USER=$(get_node_field "$node" user)
    BMC_PASS=$(get_node_field "$node" pass)

 
    local fw_inv
    fw_inv="$(rf_get "/UpdateService/FirmwareInventory")"
 
    case "$action" in
    list)
        if [[ "$OUTPUT_FMT" == "json" ]]; then
            local details=()
            while IFS= read -r m; do
                details+=("$(rf_get "${m#$REDFISH_BASE}")")
            done < <(echo "$fw_inv" | jq -r '.Members[]."@odata.id"')
            printf '%s\n' "${details[@]}" | jq -s .
        else
            echo -e "${BOLD}── Firmware Inventory — $name ──────────────────────────${RESET}"
            printf "%-20s %-30s %-20s %-10s\n" "Id" "Name" "Version" "Updateable"
            printf '%0.s─' {1..82}; echo
            while IFS= read -r m; do
                rf_get "${m#$REDFISH_BASE}" | jq -r '[
                    (.Id//"?"),
                    (.Name//"?"),
                    (.Version//"?"),
                    ((.Updateable//false)|tostring)
                ] | @tsv' | awk -F'\t' '{printf "%-20s %-30s %-20s %-10s\n",$1,$2,$3,$4}'
            done < <(echo "$fw_inv" | jq -r '.Members[]."@odata.id"')
        fi
        ;;
    update)
        local fw_file="${3:-}"
        [[ -f "$fw_file" ]] || die "Firmware file not found: $fw_file"
        info "Uploading firmware: $fw_file"
       # local upd_url="https://${BMC_HOST}:${BMC_PORT}${REDFISH_BASE}/UpdateService"
       # curl "${CURL_OPTS[@]}" -u "${BMC_USER}:${BMC_PASS}" \
       #      -X POST "${upd_url}/upload" \
       #      -H "Content-Type: application/octet-stream" \
       #      --data-binary "@${fw_file}" | jq .
         echo "Y" | ./Yafuflash -nw -ip $BMC_HOST -u $BMC_USER -p $BMC_PASS $fw_file
        ;;
    *)
        die "Unknown firmware action: $action  (list | upload <file>)"
        ;;
    esac
}


# ---------------------------------------------------------------------------
# ─────────────────────────────  HELP  ──────────────────────────────────────
# ---------------------------------------------------------------------------
cmd_redfish_help() {
    cat <<EOF
${BOLD}Usage:${RESET}
  $SCRIPT_NAME redfish <subcommand> [args…]
 
${BOLD}Subcommands:${RESET}
 
  ${CYAN}power${RESET}      <node> <status|on|off|restart|forceoff|forcerestart>
                [--json | --table | --filter <jq-expr>]
               Query or change server power state.
 
  ${CYAN}inventory${RESET}  <node> <all|cpu|mem|pci|psu>
               Show hardware inventory details.
 
  ${CYAN}thermal${RESET}    <node> <fan|temp>
                [--json | --table | --filter <jq-expr>]
               Show fan speeds and temperature readings.
 
  ${CYAN}account${RESET}    <node> <all|user|role>
                [--json | --table | --filter <jq-expr>]
               List BMC accounts and roles.
 
  ${CYAN}logs${RESET}       <node> <system|SEL|…>
                [--json | --table | --filter <jq-expr>]
               Retrieve event/system log entries.
 
  ${CYAN}biossetting${RESET} <node> [<key> [<value>]]
               Show all BIOS attributes, read or write a single one.
 
  ${CYAN}bmcsetting${RESET}  <node> [<key> [<value>]]
               Show BMC manager info or set a specific field.
 
  ${CYAN}webui${RESET}      <node>
               Print (and open) the BMC web UI URL.
 
  ${CYAN}firmware${RESET}   <node> <list|upload <file>>
                [--json | --table | --filter <jq-expr>]
               List firmware inventory or upload new firmware.
 
  ${CYAN}help${RESET}       Show this help message.
 
${BOLD}Environment:${RESET}
  BMC_USER    BMC username  (default: admin)
  BMC_PASS    BMC password  (default: admin)
  BMC_PORT    BMC HTTPS port (default: 443)
 
${BOLD}Host file:${RESET}  ~/.bmcsvr/hosts
  Format: <name>  <host/IP>  [user]  [pass]
  Example:
    node01   192.168.1.10  admin  Password1!
    node02   bmc.myhost.example.com
 
${BOLD}Examples:${RESET}
  $SCRIPT_NAME redfish power node01 status
  $SCRIPT_NAME redfish power node01 restart
  $SCRIPT_NAME redfish inventory node01 all
  $SCRIPT_NAME redfish thermal node01 temp --json
  $SCRIPT_NAME redfish logs node01 SEL --filter '.Members[-10:]'
  $SCRIPT_NAME redfish biossetting node01
  $SCRIPT_NAME redfish biossetting node1 NumaNodesPerSocket 1
  $SCRIPT_NAME redfish firmware node01 list
  $SCRIPT_NAME redfish firmware node01 upload ./bmc_v2.0.bin
EOF
}


cmd_redfish() {
    [[ $# -lt 1 ]] && { cmd_redfish_help; exit 0; }
    local sub="$1"; shift
    case "$sub" in
    powerctl)    cmd_power       "$@" ;;
    inv*)        cmd_inventory   "$@" ;;
    bmcreset)    cmd_bmcctl      "$@" ;;
    ledctl)      cmd_led         "$@" ;;
    fanctl)      cmd_fanctrl     "$@" ;;
    sensors)     cmd_sensors     "$@" ;;
    account)     cmd_account     "$@" ;; 
    session*)    cmd_session     "$@" ;; 
    task*)       cmd_task        "$@" ;; 
    logs)        cmd_logs        "$@" ;;
    biossetting) cmd_biossetting "$@" ;;
    bmcsetting)  cmd_bmcsetting  "$@" ;;
    webui)       cmd_webui       "$@" ;;
    biossetup)   cmd_amisetup    "$@" ;;
    firmware)    cmd_firmware    "$@" ;;
    help|--help|-h) cmd_redfish_help ;;
    *) die "Unknown redfish subcommand: $sub  (run '$SCRIPT_NAME redfish help')" ;;
    esac

}
