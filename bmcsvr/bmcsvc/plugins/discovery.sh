
#!/usr/bin/env bash

#set -euo pipefail

CACHE_DIR="${HOME}/.cache/bmcsvr-cli"
CACHE_FILE="${CACHE_DIR}/discovery.cache"
CACHE_TTL=3600  # seconds

# BMC default ports to probe
#BMC_PORTS=(623 443 80 22 5900)
BMC_PORTS=(443)
# IPMI port 623/UDP, HTTPS 443, HTTP 80, SSH 22, VNC 5900


#── CIDR → IP list ────────────────────────────────────────────────────────────
# Expand a CIDR block into individual IPs (pure bash, no external deps)
cidr_to_ips() {
    local cidr="$1"
    local ip prefix

    # Validate format
    if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        err "Invalid CIDR: $cidr"
        return 1
    fi

    ip="${cidr%/*}"
    prefix="${cidr#*/}"

    # Validate prefix
    (( prefix >= 0 && prefix <= 32 )) || { err "Invalid prefix /$prefix"; return 1; }

    # Convert IP to 32-bit integer
    local IFS='.'
    read -ra octets <<< "$ip"
    for o in "${octets[@]}"; do
        (( o >= 0 && o <= 255 )) || { err "Invalid IP octet: $o in $cidr"; return 1; }
    done

    local ip_int=$(( (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3] ))
    local mask=$(( 0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF ))

    local net=$(( ip_int & mask ))
    local broadcast=$(( net | (~mask & 0xFFFFFFFF) ))
    local count=$(( broadcast - net + 1 ))

    # Skip network/broadcast for /31 and larger
    local start=$net
    local end=$broadcast
    if (( prefix <= 30 )); then
        start=$(( net + 1 ))
        end=$(( broadcast - 1 ))
    fi

    for (( i = start; i <= end; i++ )); do
        printf '%d.%d.%d.%d\n' \
            $(( (i >> 24) & 255 )) \
            $(( (i >> 16) & 255 )) \
            $(( (i >>  8) & 255 )) \
            $((  i        & 255 ))
    done
}


#
# ── BMC Detection ─────────────────────────────────────────────────────────────
# Returns: "ip|port|type|latency_ms"
probe_host() {
    local ip="$1"
    local timeout="$2"

    for port in "${BMC_PORTS[@]}"; do
        local proto="tcp"
        [[ "$port" == "623" ]] && proto="udp"

        local start_ms end_ms latency result=""
        start_ms=$(date +%s%3N 2>/dev/null || echo 0)

        if [[ "$proto" == "tcp" ]]; then
            # TCP connect probe
            if timeout "$timeout" bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
                end_ms=$(date +%s%3N 2>/dev/null || echo 0)
                latency=$(( end_ms - start_ms ))
                result="$ip|$port|tcp|${latency}ms"
            fi
        else
            # UDP probe via nc (best-effort)
            if command -v nc &>/dev/null; then
                if echo -n "" | timeout "$timeout" nc -u -w "$timeout" "$ip" "$port" 2>/dev/null; then
                    end_ms=$(date +%s%3N 2>/dev/null || echo 0)
                    latency=$(( end_ms - start_ms ))
                    result="$ip|$port|udp|${latency}ms"
                fi
            fi
        fi

        if [[ -n "$result" ]]; then
            # Attempt to fingerprint BMC type
            local bmc_type="Unknown BMC"
            case "$port" in
                623) bmc_type="IPMI/BMC" ;;
                443) bmc_type=$(detect_bmc_https_rf "$ip" "$timeout") ;;
                80)  bmc_type=$(detect_bmc_http  "$ip" "$timeout") ;;
                22)  bmc_type=$(detect_bmc_ssh   "$ip" "$timeout") ;;
                5900) bmc_type="VNC Console" ;;
            esac
            if [ -n "$bmc_type" ]; then
                echo "${ip}|${port}|${proto}|${bmc_type}|${latency}ms"
            return 0
            fi
            
        fi
    done
    return 1
}

detect_bmc_https() {
    local ip="$1" timeout="$2"
    if command -v curl &>/dev/null; then
        local hdr
        hdr=$(timeout "$timeout" curl -sk -I --max-time "$timeout" "https://${ip}/" 2>/dev/null | head -5 || true)
        echo $hdr
        case "$hdr" in
            *iDRAC*)    echo "Dell iDRAC" ;;
            *iLO*)      echo "HPE iLO" ;;
            *ATEN*)     echo "ATEN IPMI" ;;
            *Supermicro*) echo "Supermicro IPMI" ;;
            *AMI*)      echo "AMI MegaRAC" ;;
            *)          echo "HTTPS BMC" ;;
        esac
    else
        echo "HTTPS BMC"
    fi
}
detect_bmc_https_rf() {
    local ip="$1" timeout="$2"
    if command -v curl &>/dev/null; then
        local hdr
        hdr=$(timeout "$timeout" curl -sk --max-time "$timeout" "https://${ip}/redfish/v1" 2>/dev/null  || true)
        #if echo "$hdr" | jq -e '.RedfishVersion' >/dev/null 2>&1; then
        vendor=$(echo "${hdr}" | jq -r '.Vendor // "Unknown"')
        uuid=$(echo "${hdr}" | jq -r '.UUID // "N/A"')
        redfishver=$(echo "${hdr}" | jq -r '.RedfishVersion // "N/A"')
        if [[ -n "$vendor" && "$vendor" != "Unknown" ]]; then
            echo "$vendor|$uuid|$redfishver"
        fi
        #fi
    else
        echo "Unknown BMC"
    fi
}

detect_bmc_http() {
    local ip="$1" timeout="$2"
    if command -v curl &>/dev/null; then
        local body
        body=$(timeout "$timeout" curl -s --max-time "$timeout" "http://${ip}/" 2>/dev/null | head -c 512 || true)
        case "$body" in
            *iDRAC*)    echo "Dell iDRAC" ;;
            *iLO*)      echo "HPE iLO" ;;
            *Supermicro*) echo "Supermicro IPMI" ;;
            *ATEN*)     echo "ATEN IPMI" ;;
            *AMI*)      echo "AMI MegaRAC" ;;
            *Redfish*)  echo "Redfish BMC" ;;
            *)          echo "HTTP BMC" ;;
        esac
    else
        echo "HTTP BMC"
    fi
}

detect_bmc_ssh() {
    local ip="$1" timeout="$2"
    if command -v ssh &>/dev/null; then
        local banner
        banner=$(timeout "$timeout" ssh -o StrictHostKeyChecking=no \
                     -o ConnectTimeout="$timeout" \
                     -o BatchMode=yes \
                     "${ip}" true 2>&1 | head -1 || true)
        case "$banner" in
            *iDRAC*)  echo "Dell iDRAC SSH" ;;
            *iLO*)    echo "HPE iLO SSH" ;;
            *)        echo "SSH BMC" ;;
        esac
    else
        echo "SSH BMC"
    fi
}

# ── Cache ─────────────────────────────────────────────────────────────────────
cache_key() {
    echo "$*" | md5sum 2>/dev/null | cut -c1-16 || echo "nocache"
}

cache_get() {
    local key="$1"
    local file="${CACHE_DIR}/${key}.cache"
    [[ -f "$file" ]] || return 1
    local mtime now age
    mtime=$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( now - mtime ))
    (( age < CACHE_TTL )) || return 1
    cat "$file"
}

cache_set() {
    local key="$1"
    shift
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "$@" > "${CACHE_DIR}/${key}.cache"
}

# ── Output Formatters ─────────────────────────────────────────────────────────
output_table() {
    local -a results=("$@")
    local sep="+-----------------+-------+-------+-----------------+--------------------------------------+-----------+-----------+"
#    local header="| IP Address      | Port  | Proto | BMC Type            | Latency   |"
    local header="| IP Address      | Port  | Proto | BMC Vendor      | BMC UUID                             | BMC RFVER | Latency   |"

    echo -e "${BOLD}${sep}${RESET}"
    echo -e "${BOLD}${header}${RESET}"
    echo -e "${BOLD}${sep}${RESET}"

    for entry in "${results[@]}"; do
#        IFS='|' read -r ip port proto bmc_type latency <<< "$entry"
#        printf "| %-15s | %-5s | %-5s | %-19s | %-9s |\n" \
#               "$ip" "$port" "$proto" "$bmc_type" "$latency"
        IFS='|' read -r ip port proto bmc_vendor bmc_uuid bmc_rfver latency <<< "$entry"
        printf "| %-15s | %-5s | %-5s | %-15s | %-19s | %-9s | %-9s |\n" \
               "$ip" "$port" "$proto" "$bmc_vendor" "$bmc_uuid" "$bmc_rfver" "$latency"
    done

    echo -e "${sep}"
    echo -e "${DIM}  Total: ${#results[@]} BMC host(s) found${RESET}"
}

output_json() {
    local -a results=("$@")
    local count=${#results[@]}
    local i=0

    echo "{"
    echo "  \"version\": \"${VERSION}\","
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"count\": ${count},"
    echo "  \"hosts\": ["

    for entry in "${results[@]}"; do
#        IFS='|' read -r ip port proto bmc_type latency <<< "$entry"
        IFS='|' read -r ip port proto bmc_vendor bmc_uuid bmc_rfver latency <<< "$entry"
        i=$(( i + 1 ))
        local comma=","
        (( i == count )) && comma=""
#        cat <<-JSON
#		    {
#		      "ip": "${ip}",
#		      "port": ${port},
#		      "protocol": "${proto}",
#		      "bmc_type": "${bmc_type}",
#		      "latency": "${latency}"
#		    }${comma}
#		JSON
        cat <<-JSON
		    {
		      "ip": "${ip}",
		      "port": ${port},
		      "protocol": "${proto}",
		      "bmc_vendor": "${bmc_vendor}",
		      "bmc_uuid": "${bmc_uuid}",
		      "bmc_rfver": "${bmc_rfver}",
		      "latency": "${latency}"
		    }${comma}
		JSON
    done

    echo "  ]"
    echo "}"
}

output_plain() {
    local -a results=("$@")
    for entry in "${results[@]}"; do
#        IFS='|' read -r ip port proto bmc_type latency <<< "$entry"
#        echo "${ip}  ${port}/${proto}  ${bmc_type}  ${latency}"
        IFS='|' read -r ip port proto bmc_vendor bmc_uuid bmc_rfver latency <<< "$entry"
        echo "${ip}  ${port}/${proto}  ${bmc_vendor} ${bmc_uuid} ${bmc_rfver} ${latency}"
    done
}


render_results() {
    local fmt="$1"; shift
    local -a results=("$@")
    case "$fmt" in
        table) output_table "${results[@]}" ;;
        json)  output_json  "${results[@]}" ;;
        *)     output_plain "${results[@]}" ;;
    esac
}

# ── Usage ─────────────────────────────────────────────────────────────────────
cmd_discovery_help() {
    cat <<EOF
${BOLD}USAGE${RESET}
    $SCRIPT_NAME discovery <CIDR> [CIDR...] [OPTIONS]

${BOLD}ARGUMENTS${RESET}
    CIDR              One or more CIDR blocks to scan (e.g. 192.168.1.0/24)

${BOLD}OPTIONS${RESET}
    --timeout  <sec>  TCP connect timeout per host (default: 1)
    --parallel <n>    Max concurrent probes         (default: 50)
    --cache           Cache and reuse results        (TTL: ${CACHE_TTL}s)
    --table           Output as ASCII table
    --json            Output as JSON
    -h, --help        Show this help

${BOLD}EXAMPLES${RESET}
    $SCRIPT_NAME discovery 192.168.1.0/24
    $SCRIPT_NAME discovery 10.0.0.0/8 --timeout 2 --parallel 100 --table
    $SCRIPT_NAME discovery 172.16.0.0/16 192.168.0.0/24 --json
    $SCRIPT_NAME discovery 192.168.1.0/24 --cache --table

${BOLD}DETECTED BMC TYPES${RESET}
    Dell iDRAC     port 443/TCP  — Dell Remote Access Controller
    HPE iLO        port 443/TCP  — HPE Integrated Lights-Out
    Supermicro     port 443/TCP  — Supermicro Redfish
    ASUS           port 443/TCP  — ASUS Redfish
    GCT            port 443/TCP  — GCT Redfish
    AMI MegaRAC    port 443/TCP  — AMI BMC Redfish

${BOLD}CACHE${RESET}
    Cache stored in: ${CACHE_DIR}/
    TTL: ${CACHE_TTL} seconds
EOF
#    IPMI/BMC       port 623/UDP  — Generic IPMI
#    Dell iDRAC     port 443/TCP  — Dell Remote Access Controller
#    HPE iLO        port 443/TCP  — HPE Integrated Lights-Out
#    Supermicro     port 443/TCP  — Supermicro IPMI
#    AMI MegaRAC    port 443/TCP  — AMI BMC
#    Redfish BMC    port 80/TCP   — DMTF Redfish API
#    SSH BMC        port 22/TCP   — SSH-accessible BMC
#    VNC Console    port 5900/TCP — KVM/VNC remote console

}

usage() {
    cat <<EOF
${BOLD}bmcsvr-cli.sh${RESET} v${VERSION} — BMC Server Discovery Tool

${BOLD}USAGE${RESET}
    $SCRIPT_NAME <command> [args...]

${BOLD}COMMANDS${RESET}
    discovery   Scan CIDR range(s) for BMC hosts
    version     Show version
    help        Show this help

Run ${BOLD}$SCRIPT_NAME <command> --help${RESET} for command-specific help.
EOF
}


# ── Discovery ─────────────────────────────────────────────────────────────────
cmd_discovery() {
    local -a cidrs=()
    local timeout=1
    local parallel=50
    local use_cache=false
    local fmt="table" # plain

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout)   shift; timeout="${1:?--timeout requires a value}"; shift ;;
            --timeout=*) timeout="${1#*=}"; shift ;;
            --parallel)  shift; parallel="${1:?--parallel requires a value}"; shift ;;
            --parallel=*)parallel="${1#*=}"; shift ;;
            --cache)     use_cache=true; shift ;;
            --table)     fmt="table"; shift ;;
            --json)      fmt="json"; shift ;;
            help | --help|-h)    exit 0 ;;
            -*)          die "Unknown option: $1" ;;
            *)           cidrs+=("$1"); shift ;;
        esac
    done

    [[ ${#cidrs[@]} -gt 0 ]] ||   die "At least one CIDR is required.\nUsage: $SCRIPT_NAME discovery <CIDR> [CIDR...]" 

    # Validate numeric args
    [[ "$timeout"  =~ ^[0-9]+$ ]] || die "--timeout must be a positive integer"
    [[ "$parallel" =~ ^[0-9]+$ ]] || die "--parallel must be a positive integer"

    # Cache lookup
    local cache_key_val
    cache_key_val=$(cache_key "${cidrs[*]}" "$timeout")
    if $use_cache; then
        if cached=$(cache_get "$cache_key_val" 2>/dev/null); then
            info "Serving results from cache (TTL ${CACHE_TTL}s)"
            mapfile -t results <<< "$cached"
            render_results "$fmt" "${results[@]}"
            return 0
        fi
    fi

    # Expand all CIDRs into IP list
    local -a all_ips=()
    for cidr in "${cidrs[@]}"; do
        mapfile -t ips < <(cidr_to_ips "$cidr") || die "Failed to expand CIDR: $cidr"
        all_ips+=("${ips[@]}")
    done

    local total=${#all_ips[@]}
    info "Scanning ${BOLD}${total}${RESET} hosts across ${#cidrs[@]} CIDR(s) — timeout=${timeout}s parallel=${parallel}"

    # Temp file for results
    local tmpfile
    tmpfile=$(mktemp /tmp/bmcsvr_XXXXXX)
    trap 'rm -f "$tmpfile"' EXIT

    # Progress counter (atomic via file)
    local progress_file
    progress_file=$(mktemp /tmp/bmcsvr_prog_XXXXXX)
    echo "0" > "$progress_file"

    # Parallel scanning with job control
    local -a pids=()
    local slot=0

    scan_ip() {
        local ip="$1"
        if result=$(probe_host "$ip" "$timeout" 2>/dev/null); then
            echo "$result" >> "$tmpfile"
        fi
        # Increment progress
        local n
        n=$(cat "$progress_file" 2>/dev/null || echo 0)
        echo $(( n + 1 )) > "$progress_file"
    }

    # Launch scans with parallelism limit
    for ip in "${all_ips[@]}"; do
        scan_ip "$ip" &
        pids+=($!)

        # Throttle to --parallel limit
        if (( ${#pids[@]} >= parallel )); then
            wait "${pids[0]}" 2>/dev/null || true
            pids=("${pids[@]:1}")
        fi

        # Progress bar (every 50 hosts)
        local done_count
        done_count=$(cat "$progress_file" 2>/dev/null || echo 0)
        if (( done_count % 50 == 0 && done_count > 0 )); then
            local pct=$(( done_count * 100 / total ))
            printf "\r${DIM}  Progress: %d/%d (%d%%)${RESET}" \
                   "$done_count" "$total" "$pct" >&2
        fi
    done

    # Wait remaining
    wait "${pids[@]}" 2>/dev/null || true
    printf "\r%*s\r" 60 "" >&2  # clear progress line

    # Collect & sort results
    local -a results=()
    if [[ -s "$tmpfile" ]]; then
        mapfile -t results < <(sort -t'.' -k1,1n -k2,2n -k3,3n -k4,4n "$tmpfile")
    fi
    rm -f "$progress_file"

    local found=${#results[@]}
    ok "Scan complete — ${BOLD}${found}${RESET} BMC host(s) found out of ${total} scanned"

    if (( found == 0 )); then
        warn "No BMC hosts detected in the specified range(s)."
        exit 0
    fi

    # Cache results
    if $use_cache; then
        cache_set "$cache_key_val" "${results[@]}"
        info "Results cached (key: ${cache_key_val})"
    fi

    render_results "$fmt" "${results[@]}"
}
