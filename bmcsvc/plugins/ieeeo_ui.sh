#!/bin/bash

# Define the path for the local OUI cache file
OUI_CACHE="$HOME/.cache/ieee_oui.txt"

# Function: Initialize the OUI database (Download if cache does not exist)
init_oui_db() {
    if [ ! -f "$OUI_CACHE" ]; then
        echo "[*] Initializing IEEE OUI database. Please wait..." >&2
        mkdir -p "$(dirname "$OUI_CACHE")"
        # Fetch official list and format it to contain only Hex OUI and Vendor name
        curl -s https://standards-oui.ieee.org/oui/oui.txt | \
            grep "(hex)" | \
            sed 's/^[ \t]*//g' > "$OUI_CACHE"
    fi
}

# Main Function: Accept IP or MAC, return Vendor Name
check_macaddr() {
    local input="$1"
    local mac=""
    local oui=""

    if [ -z "$input" ]; then
        echo "Error: Please provide an IP or MAC address."
        return 1
    fi

    # 1. Determine if the input is an IP or MAC address
    if [[ "$input" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Input is an IP: Trigger ARP resolution via ping + ip neighbor
        ping -c 1 -W 1 "$input" > /dev/null 2>&1
        mac=$(ip neighbor show "$input" | awk '{print $5}' | tr '[:lower:]' '[:upper:]')
        
        if [ -z "$mac" ] || [[ ! "$mac" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]]; then
            echo "Unknown (Unable to resolve MAC from IP)"
            return 1
        fi
    elif [[ "$input" =~ ^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$ ]]; then
        # Input is a MAC: Normalize format to Uppercase with Colons
        mac=$(echo "$input" | tr '[:lower:]' '[:upper:]' | tr '-' ':')
    else
        echo "Error: Invalid IP or MAC address format."
        return 1
    fi

    # 2. Optimization: Check U/L bit (2nd char of 1st byte: 2, 6, A, E)
    local first_byte_second_char="${mac:1:1}"
    if [[ "$first_byte_second_char" =~ [26AE] ]]; then
        echo "Locally Administered (Temporary/Random/VM)"
        return 0
    fi

    # 3. Extract OUI Prefix (First 3 Bytes, formatted as XX-XX-XX for IEEE lookup)
    oui=$(echo "$mac" | cut -d':' -f1-3 | tr ':' '-')

    # 4. Ensure OUI database cache is ready
    init_oui_db

    # 5. Search local database for the Vendor Name
    local vendor=""
    vendor=$(grep -i "^$oui" "$OUI_CACHE" | cut -d')' -f2- | sed 's/^[ \t]*//g')

    if [ -n "$vendor" ]; then
        echo "$vendor"
    else
        echo "Unknown Vendor (Unregistered or new allocation)"
    fi
}

if false; then
# --- Test Block ---
# You can run this script directly to test the outputs

echo "=== Test 1: Real Hardware MAC Addresses ==="
echo -n "MAC 30:C5:99:11:22:33 -> "
check_macaddr "30:C5:99:11:22:33"

echo -n "MAC 14:2D:27:AA:BB:CC -> "
check_macaddr "14:2D:27:AA:BB:CC"

echo -e "\n=== Test 2: Software/Random MAC (U/L bit = 1) ==="
echo -n "MAC 02:11:22:33:44:55 -> "
check_macaddr "02:11:22:33:44:55"

echo -e "\n=== Test 3: Local Network IP Target ==="
# Replace with a reachable IP on your local subnet (e.g., your gateway or a BMC)
TARGET_LAN_IP="192.168.1.1" 
echo -n "IP $TARGET_LAN_IP -> "
check_macaddr "$TARGET_LAN_IP"

echo -e "\n=== Test 4: Software/Random MAC (U/L bit = 1) ==="
echo -n "MAC 2A:84:22:41:EE:7D -> "
check_macaddr 2A:84:22:41:EE:7D
fi