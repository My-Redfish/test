#!/usr/bin/env bash

#BMC_IP="${BMC_IP:-10.1.9.86}"
#USER="${USER:-test}"
#PASS="${PASS:-gigabyte}"
#USER=test
#PASS=gigabyte
CREDS_SOURCE=env
#BASE="https://$BMC_IP"

#echo  $USER:$PASS 

# ===== 基本 function =====
CONFIG_FILE="${REDFISH_CONFIG:-$HOME/.config/redfish-skill/config}"
CREDS_FILE="$HOME/.redfish-credentials"


# Load configuration
load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config not found at $CONFIG_FILE" >&2
    echo "Create it with:" >&2
    echo
    echo "mkdir -p ~/.config/redfish-skill" >&2
    echo "cat > ~/.config/redfish-skill/config <<EOF" >&2
    echo 'BMC_IP="<your-BMC-ip>"' >&2
    echo 'CREDS_SOURCE="file"  # or "1password" or "env"' >&2
    echo "EOF" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"

  if [ -z "${BMC_IP:-}" ]; then
    echo "Error: BMC_IP not set in $CONFIG_FILE" >&2
    exit 1
  fi

  BMC_BASE="https://${BMC_IP}"
  CREDS_SOURCE="${CREDS_SOURCE:-file}"
}

# Hydrate credentials based on configured source
hydrate_creds() {
  case "${CREDS_SOURCE}" in
    1password)
      if [ ! -f "$CREDS_FILE" ]; then
        local op_item="${OP_ITEM:?OP_ITEM not set in config}"
        echo "Hydrating credentials from 1Password ($op_item)..." >&2
        op item get "$op_item" --fields username,password --format json | \
          jq -r '"\(.[0].value):\(.[1].value)"' > "$CREDS_FILE"
        chmod 600 "$CREDS_FILE"
      fi
      ;;
    env)
      if [ -z "${USER:-}" ] || [ -z "${PASS:-}" ]; then
        echo "Error: USER and PASS must be set for CREDS_SOURCE=env" >&2
        exit 1
      fi
      # Write ephemeral creds file for curl
      echo "${USER}:${PASS}" > "$CREDS_FILE"
      chmod 600 "$CREDS_FILE"
      ;;
    file)
      if [ ! -f "$CREDS_FILE" ]; then
        echo "Error: Credentials file not found at $CREDS_FILE" >&2
        echo "Create it: echo 'username:password' > $CREDS_FILE && chmod 600 $CREDS_FILE" >&2
        exit 1
      fi
      ;;
    *)
      echo "Error: Unknown CREDS_SOURCE '$CREDS_SOURCE' (use: 1password, file, env)" >&2
      exit 1
      ;;
  esac
}

# 定義一個紀錄 Log 的 function
log_event() {
  local level=$1
  local message=$2
  
  # 使用 --arg 安全地傳入變數
  jq -n \
    --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg lvl "$level" \
    --arg msg "$message" \
    '{timestamp: $time, level: $lvl, message: $msg}' >> app.log.json
}
#log_event "INFO" "腳本啟動"
#log_event "ERROR" "資料庫連線失敗！"

# API call wrapper
# ===== 掃描網段 =====
rf_scan1() {
  SUBNET="$1"   # 例如 10.1.9
  echo "Scanning $SUBNET.0/24 ..."

  for i in {1..254}; do
    IP="$SUBNET.$i"

    (
      # 1️⃣ ping 檢查
      ping -c 1 -W 1 $IP > /dev/null 2>&1 || exit

      # 2️⃣ 試 Redfish
      RESP=$(curl -sk --connect-timeout 2 https://$IP/redfish/v1)
        #echo $RESP
      if echo "$RESP" | jq -e '.RedfishVersion' >/dev/null 2>&1; then
        VENDOR=$(echo "$RESP" | jq -r '.Vendor')
        UUID=$(echo "$RESP" | jq -r '.UUID')
        if [ -n "$VENDOR" ]; then
           echo "[FOUND] $IP | Vendor=$VENDOR | UUID=$UUID"
        fi   
      fi
    ) &

  done

  wait
}
rf_scan2() {
  local CIDR="${1:-}"
  local PARALLEL=50

  if [[ -z "$CIDR" ]]; then
    echo "Usage: $0 scan <CIDR>"
    echo "Example: $0 scan 10.1.9.0/24"
    return 1
  fi

  log_event "INFO" "Scanning (ping mode): $CIDR"

  # 👉 CIDR → IP list（只支援 /24，夠用）
  gen_ips() {
    local base=$(echo "$CIDR" | cut -d/ -f1)
    local prefix=$(echo "$base" | awk -F. '{print $1"."$2"."$3}')

    for i in $(seq 1 254); do
      echo "$prefix.$i"
    done
  }

  # 👉 ping 檢查
  is_alive() {
    local ip="$1"
    ping -c 1 -W 1 "$ip" >/dev/null 2>&1
  }

  # 👉 Redfish 檢測
  scan_ip() {
    local ip="$1"

    # 1️⃣ ping 過濾
    is_alive "$ip" || return

    # 2️⃣ port 443 檢查（加速）
    timeout 1 bash -c "</dev/tcp/$ip/443" 2>/dev/null || return

    # 3️⃣ Redfish probe
    local resp
    resp=$(curl -sk --connect-timeout 2 --max-time 4 \
      -u "$USER:$PASS" \
      https://$ip/redfish/v1 2>/dev/null || true)

    if echo "$resp" | jq -e '.RedfishVersion' >/dev/null 2>&1; then
      local vendor model uuid

      vendor=$(echo "$resp" | jq -r '.Vendor // "Unknown"')
      uuid=$(echo "$resp" | jq -r '.UUID // "N/A"')

      model=$(curl -sk -u "$USER:$PASS" \
        https://$ip/redfish/v1/Systems \
        | jq -r '.Members[0]."@odata.id"' \
        | xargs -I{} curl -sk -u "$USER:$PASS" https://$ip{} \
        | jq -r '.Model // "Unknown"' 2>/dev/null)

      echo "{\"ip\":\"$ip\",\"vendor\":\"$vendor\",\"model\":\"$model\",\"uuid\":\"$uuid\"}"
    fi
  }

  export -f scan_ip is_alive
  export USER PASS

  gen_ips | xargs -I{} -P $PARALLEL bash -c 'scan_ip "$@"' _ {}
}
rf_scan() {
  local RANGE="${1:-}"
  local PARALLEL=20

  if [[ -z "$RANGE" ]]; then
    echo "Usage: $0 scan <CIDR | IP range>"
    echo "Example:"
    echo "  $0 scan 10.1.9.0/24"
    return 1
  fi

  log_event "INFO" "Scanning: $RANGE"

  # 👉 產生 IP 清單（支援 CIDR）
  gen_ips() {
    if [[ "$RANGE" == */* ]]; then
      # CIDR
      nmap -n -p 443 "$RANGE" | awk '/Nmap scan report/{print $NF}'
    else
      # 單 IP 或 range（簡化版）
      echo "$RANGE"
    fi
  }

  scan_ip() {
    local ip="$1"
    local resp
    resp=$(curl -sk --connect-timeout 2 --max-time 4 \
      -u "$USER:$PASS" \
      https://$ip/redfish/v1 2>/dev/null || true)

    # 👉 判斷是否 Redfish
    if echo "$resp" | jq -e '.RedfishVersion' >/dev/null 2>&1; then
      local vendor model uuid
      vendor=$(echo "$resp" | jq -r '.Vendor // "Unknown"')
      uuid=$(echo "$resp" | jq -r '.UUID // "N/A"')

      # 嘗試抓 Model
      #model=$(curl -sk -u "$USER:$PASS" \
      #  https://$ip/redfish/v1/Systems \
      #  | jq -r '.Members[0]."@odata.id"' \
      #  | xargs -I{} curl -sk -u "$USER:$PASS" https://$ip{} \
      #  | jq -r '.Model // "Unknown"' 2>/dev/null)

      if [[ -n "$vendor" && "$vendor" != "Unknown" ]]; then
         echo "{\"ip\":\"$ip\",\"vendor\":\"$vendor\",\"uuid\":\"$uuid\"}"
      fi 
    fi
  }

  export -f scan_ip
  export USER PASS

  gen_ips | xargs -I{} -P $PARALLEL bash -c 'scan_ip "$@"' _ {} | jq -c
}
rf_get() {
  local endpoint="$1"
  hydrate_creds
  curl -k -s -u "$(cat "$CREDS_FILE")" "${BMC_BASE}${endpoint}"
}

#rf_get() {
#  curl -sk -u "$USER:$PASS" "$BASE$1"
#}

rf_post() {
  curl -sk -u "$USER:$PASS" -X POST -H "Content-Type: application/json" -d "$2" "$BASE$1"
}

rf_patch() {
  curl -sk -u "$USER:$PASS" -X PATCH -H "Content-Type: application/json" -d "$2" "$BASE$1"
}

# ===== 自動抓 System =====
rf_system() {
  rf_get /redfish/v1/Systems | jq -r '.Members[0]["@odata.id"]'
}

# ===== 基本資訊 =====
rf_info() {
  SYS=$(rf_system)
  rf_get "$SYS" | jq '{
      Model,
      Manufacturer,
      ServiceTag: .SKU,
      PowerState,
      Health: .Status.Health,
      State: .Status.State,
      BiosVersion,
      Processors: .ProcessorSummary.Count,
      LogicalProcessors: .ProcessorSummary.LogicalProcessorCount,
      MemoryGB: .MemorySummary.TotalSystemMemoryGiB
    }'
}

# ===== 快速欄位 =====
rf_power() {
  SYS=$(rf_system)
  rf_get "$SYS" | jq -r '.PowerState'
}

rf_health() {
  SYS=$(rf_system)
  rf_get "$SYS" | jq -r '
      "Overall Health: \(.Status.Health)",
      "State: \(.Status.State)",
      "Power: \(.PowerState)"
    '
}

rf_model() {
  SYS=$(rf_system)
  rf_get "$SYS" | jq -r '.Model'
}

# ===== 開關機控制 =====
rf_reset() {
  SYS=$(rf_system)
  ACTION="$1"

  rf_post "$SYS/Actions/ComputerSystem.Reset" "{
    \"ResetType\": \"$ACTION\"
  }" | jq
}

# 常用 reset type:
# On / ForceOff / GracefulShutdown / GracefulRestart / ForceRestart

# ===== CPU / Memory =====
rf_cpu() {
  SYS=$(rf_system)
  CPU_LIST=$(rf_get "$SYS/Processors" | jq -r '.Members[]."@odata.id"')
  for cpu in $CPU_LIST; do
    #echo "---- $mcpu ----"
    rf_get "$cpu" | jq '{
      Id,
      Model,
      Manufacturer,
      TotalCores,
      TotalThreads,
      MaxSpeedMHz,
      ProcessorArchitecture,
      InstructionSet,
      Status
    }'
  done

}

rf_mem() {
  SYS=$(rf_system)
  MEM_LIST=$(rf_get "$SYS/Memory" | jq -r '.Members[]."@odata.id"')
  for mem in $MEM_LIST; do
    #echo "---- $mem ----"
    rf_get "$mem" | jq '{
      Id,
      Manufacturer,
      MemoryDeviceType,
      BaseModuleType,
      BusWidthBits,
      CacheSizeMiB,
      CapacityMiB,
      DataWidthBits,
      DeviceLocator,
      FirmwareRevision,
      MemoryType,
      ModuleManufacturerID,
      ModuleProductID,
      OperatingSpeedMhz,
      PartNumber,
      SerialNumber,
      Status: .Status.State
    }'
  done
}
rf_nic() {
  SYS=$(rf_system)
  NIC_LIST=$(rf_get "$SYS/EthernetInterfaces" | jq -r '.Members[]."@odata.id"')
  for nic in $NIC_LIST; do
    #echo "---- $mem ----"
    rf_get "$nic" | jq '{
      Id,
      Name,
      MACAddress,
      SpeedMbps,
      FullDuplex,
      LinkStatus,
      IPv4Addresses,
      IPv6Addresses,
      Status
    }'
    
  done
}

rf_inventory() {
    #echo "=== Hardware Inventory ==="
    SYS=$(rf_system)
    rf_get "$SYS" | jq '{
      System: {
        Model,
        Manufacturer,
        SerialNumber,
        ServiceTag: .SKU,
        BiosVersion
      },
      Processors: .ProcessorSummary,
      Memory: .MemorySummary
    }'
}    
# ===== Sensor (如果支援) =====
rf_thermal() {
  #rf_get /redfish/v1/Chassis/1/Thermal | jq
  rf_get "/redfish/v1/Chassis/Self/Thermal" | jq '{
      Temperatures: [.Temperatures[] | {
        Name,
        Reading: .ReadingCelsius,
        Upper: .UpperThresholdCritical,
        Status: .Status.Health
      }],
      Fans: [.Fans[] | {
        Name,
        Speed: .Reading,
        Units,
        Status: .Status.Health
      }]
    }'

}

rf_power_usage() {
  rf_get /redfish/v1/Chassis/1/Power | jq
}

rf_test() {
    echo "Testing Redfish connectivity and authentication..."
    echo "Target: ${BMC_IP}"
    echo "Credential source: ${CREDS_SOURCE}"
    echo ""

    # Test 1: Network connectivity
    echo -n "1. Network connectivity... "
    if curl -k -s --connect-timeout 5 "https://${BMC_IP}/redfish/v1/" > /dev/null 2>&1; then
      echo "✅ OK"
    else
      echo "❌ FAILED (cannot reach ${BMC_IP})"
      exit 1
    fi

    # Test 2: Authentication
    echo -n "2. Credential hydration (${CREDS_SOURCE})... "
    hydrate_creds
    if [ -f "$CREDS_FILE" ]; then
      echo "✅ OK"
    else
      echo "❌ FAILED"
      exit 1
    fi

    # Test 3: API access
    echo -n "3. API access (Redfish root)... "
    RESPONSE=$(rf_get "/redfish/v1/" 2>&1)
    if echo "$RESPONSE" | jq -e '.RedfishVersion' > /dev/null 2>&1; then
      VERSION=$(echo "$RESPONSE" | jq -r '.RedfishVersion')
      echo "✅ OK (Redfish ${VERSION})"
    else
      echo "❌ FAILED (invalid response or auth failure)"
      exit 1
    fi

    # Test 4: System query
    echo -n "4. System data... "
    SYSTEM=$(rf_get "/redfish/v1/Systems/Self" 2>&1)
    if echo "$SYSTEM" | jq -e '.Model' > /dev/null 2>&1; then
      MODEL=$(echo "$SYSTEM" | jq -r '.Model')
      HEALTH=$(echo "$SYSTEM" | jq -r '.Status.Health')
      echo "✅ OK (${MODEL}, Health: ${HEALTH})"
    else
      echo "❌ FAILED"
      exit 1
    fi

    echo ""
    echo "All tests passed! Redfish API is fully accessible."  
}

help() {
   cat <<EOF
Generic Redfish API Helper

Usage: $0 <command>

Commands:
  scan
  test          Test connectivity and authentication
  info          System summary (model, power, CPU, memory)
  health        Health checks (overall, temps, fans, power)
  power         Current power state
  inventory     Full hardware inventory
  logs          Recent system event log entries (last 10)
  cpu           CPU info
  mem           Memory info
  nic           Network interfaces
  thermal       Detailed temperature and fan status
  storage       Storage controllers and drives
  reset-types   Available power reset types
  help          Show this help

Config: ${CONFIG_FILE}
Credentials: ${CREDS_SOURCE} → ${CREDS_FILE}
EOF
#echo "Usage:"
#    echo "  ./redfish.sh info"
#    echo "  ./redfish.sh power"
#    echo "  ./redfish.sh on|off|reboot|shutdown"
#    echo "  ./redfish.sh cpu|mem"
#    echo "  ./redfish.sh thermal|powercap"
}

# Load config before any command
load_config

# ===== 使用說明 =====
case "${1:-help}" in
  scan) rf_scan $2 ;;
  test) rf_test ;; 
  info) rf_info ;;
  power) rf_power ;;
  health) rf_health ;;
  model) rf_model ;;
  on) rf_reset On ;;
  off) rf_reset ForceOff ;;
  reboot) rf_reset ForceRestart ;;
  shutdown) rf_reset GracefulShutdown ;;
  cpu) rf_cpu ;;
  mem) rf_mem ;;
  nic) rf_nic ;;
  thermal) rf_thermal ;;
  inventory) rf_inventory ;;
  powercap) rf_power_usage ;;
  #link) explorer.exe "https://10.1.9.86" ;;
  link) /mnt/c/Program\ Files\ \(x86\)/Microsoft/Edge/Application/msedge.exe --ignore-certificate-errors "$BMC_BASE" ;;
 #/mnt/c/Program\ Files/Google/Chrome/Application/chrome.exe --ignore-certificate-errors "https://your-unsafe-site.com"
  help|*) help;;

esac


