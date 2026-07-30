#!/usr/bin/env bash

CONFIG_DIR="${HOME}/.bmcsvr"
CONFIG_FILE="${CONFIG_DIR}/nodeconfig"

mkdir -p "$CONFIG_DIR"
touch "$CONFIG_FILE"
########################################
# node utils
########################################

ensure_node() {
    local node="$1"
    grep -q "^\[node \"$node\"\]" "$CONFIG_FILE" || die "Node '$node' not found"
}
ensure_node_field() {
    local node="$1"
    local field="$2"

#    [[ -z "$node" || -z "$field" ]] && \
#        die "Usage: ensure_node_field <node> <field>"

    local exists

    exists=$(awk -v node="$node" -v field="$field" '
    $0 ~ "\\[node \""node"\"\\]" {found=1; next}
    found && $0 ~ /^\[/ {exit}
    found && $1==field {print "yes"; exit}
    ' "$CONFIG_FILE")

    if [[ "$exists" != "yes" ]]; then
        die "Field '$field' not found in node '$node'"
    fi
}

get_node_field() {
    local node="$1"
    local field="$2"

    awk -v node="$node" -v field="$field" '
    $0 ~ "\\[node \""node"\"\\]" {found=1; next}
    found && $0 ~ /^\[/ {exit}
    found && $1==field {print $3}
    ' "$CONFIG_FILE"
}

set_node_field() {
    local node="$1"
    local field="$2"
    local value="$3"

    awk -v node="$node" -v field="$field" -v value="$value" '
    BEGIN {in_node=0; updated=0}
    {
        if ($0 ~ "\\[node \""node"\"\\]") {
            in_node=1
            print
            next
        }

        if (in_node && $0 ~ /^\[/) {
            if (!updated) {
                print "    " field " = " value
                updated=1
            }
            in_node=0
        }

        if (in_node && $1==field) {
            print "    " field " = " value
            updated=1
            next
        }

        print
    }
    END {
        if (in_node && !updated) {
            print "    " field " = " value
        }
    }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

del_node_field() {
    local node="$1"
    local field="$2"

    [[ -z "$node" || -z "$field" ]] && \
        die "Usage: del_node_field <node> <field>"

    ensure_node_field "$node" "$field"

    awk -v node="$node" -v field="$field" '
    BEGIN {in_node=0}
    {
        # Enter target node block
        if ($0 ~ "\\[node \""node"\"\\]") {
            in_node=1
            print
            next
        }

        # Exit node block
        if (in_node && $0 ~ /^\[/) {
            in_node=0
        }

        # Skip the field to delete
        if (in_node && $1==field) {
            next
        }

        print
    }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}
########################################
# node commands
########################################

cmd_node_add() {
    local name="$1"; shift
    [[ -z "$name" ]] && cmd_node_help add && die "Usage: node add <name> --host <ip> --user <user> --pass <pass>"

    local host user pass

    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            --host) host="$2"; shift 2;;
            --user) user="$2"; shift 2;;
            --pass) pass="$2"; shift 2;;
            *) die "Unknown option $1";;
        esac
    done

    [[ -z "$host" || -z "$user" || -z "$pass" ]] && cmd_node_help add && die "Missing required fields"

    if grep -q "^\[node \"$name\"\]" "$CONFIG_FILE"; then
        die "Node exists"
    fi

    cat >> "$CONFIG_FILE" <<EOF
[node "$name"]
    host = $host
    user = $user
    pass = $pass
EOF

    log "Node '$name' added"
}

cmd_node_get() {
    local name="${1:-}"
    local field="$2"

    [[ -z "$name" || -z "$field" ]] && cmd_node_help get && die "Usage: node get <name> <field>"

    ensure_node "$name"
    get_node_field "$name" "$field"
}

cmd_node_set() {
    local name="$1"
    local field="$2"
    local value="$3"

    [[ -z "$name" || -z "$field" || -z "$value" ]] && cmd_node_help set && \
        die "Usage: node set <name> <field> <value>"

    ensure_node "$name"
    set_node_field "$name" "$field" "$value"

    ok "Updated $field form '$name' node  "
}
cmd_node_delfield() {
    local name="$1"
    local field="$2"
    
    [[ -z "$name" || -z "$field" ]] && cmd_node_help delfield && \
        die "Usage: node delfield <name> <field>"

    ensure_node "$name"
    del_node_field "$name" "$field" 

    ok "Removed $field form '$name' node"
}
cmd_node_remove() {
    local name="$1"
    [[ -z "$name" ]] && cmd_node_help remove && die "Usage: node remove <name>"

    ensure_node "$name"

    awk -v node="$name" '
    BEGIN {skip=0}
    {
        if ($0 ~ "\\[node \""node"\"\\]") {skip=1; next}
        if (skip && $0 ~ /^\[/) {skip=0}
        if (!skip) print
    }
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

    ok "Node '$name' removed"
}

########################################
# output format
########################################

print_table() {
    printf "%-15s %-15s %-10s\n" "NAME" "HOST" "USER"
    printf "%-15s %-15s %-10s\n" "----" "----" "----"

    awk '
 /^\[node/ {
    name=$2
    gsub(/"|]/, "", name)
}
/host/ {host=$3}
/user/ {user=$3}
/^\[/ && NR!=1 {
    if (prev_name) {
        printf "%-15s %-15s %-10s\n", prev_name, prev_host, prev_user
    }
}
{
    if (name) {
        prev_name=name
        prev_host=host
        prev_user=user
    }
}
END {
    if (prev_name) {
        printf "%-15s %-15s %-10s\n", prev_name, prev_host, prev_user
    }
}
    ' "$CONFIG_FILE"
}

print_yaml() {
    awk '
BEGIN {
    # YAML does not require a root wrapper like JSON
}

# Matches [node "name"]
/^\[node / {
    match($0, /\[node "([^"]+)"\]/, arr)
    node = arr[1]

    # YAML Top-level node
    printf "%s:\n", node
    next
}

# Matches key = value
/^[ \t]*[a-zA-Z0-9_]+[ \t]*=/ {
    key = $1
    sub(/[ \t]*=/, "", key)

    value = $0
    sub(/^[^=]+=[ \t]*/, "", value)
    
    # Optional: Clean existing quotes from value to prevent double-quoting
    gsub(/^"|"$/, "", value)

    # Print with 2-space indentation
    printf "  %s: \"%s\"\n", key, value
}
    ' "$CONFIG_FILE"
}

get_node_jsondata() {
   awk '
 BEGIN {
    print "{"
    first_node = 1
}

/^\[node / {
    if (!first_node) {
        print "\n  },"
    }
    first_node = 0

    match($0, /\[node "([^"]+)"\]/, arr)
    node = arr[1]

    printf "  \"%s\": {", node
    first_field = 1
    next
}

/^[ \t]*[a-zA-Z0-9_]+[ \t]*=/ {
    key = $1
    sub(/[ \t]*=/, "", key)

    value = $0
    sub(/^[^=]+=[ \t]*/, "", value)

    if (!first_field) {
        printf ","
    }
    first_field = 0

    printf "\n    \"%s\": \"%s\"", key, value
}

END {
    print "\n  }"
    print "}"
}
    ' "$CONFIG_FILE"
}

########################################
# list / show
########################################

cmd_node_list() {
    #data=$(get_node_jsondata) 
    local jsondata
    jsondata=$(get_node_jsondata | jq 'to_entries | map({name: .key} + .value)')
   
    local DATA_TYPE='Nodes'

    jsondata1=$(echo "$jsondata" | jq -c \
        --arg DATA_TYPE "$DATA_TYPE" \
        '{ Type: $DATA_TYPE, Data: ., Count: length }')
    #dbg echo $jsondata1 | jq 
    case "${1:-}" in
        --json) echo $jsondata1 | jq -c;;
        --yaml) print_yaml ;;

        *) 
         local tsvdata
         tsvdata=$(echo "$jsondata1" | jq -r '
            (["Name", "Host", "User", "Password", "Vendor", "Location"] | @tsv), 
            (.Data[] | [.name, .host, .user, .pass, .vendor, .location] | @tsv)
        ')
        export TABLE_FMT="fancy_grid"
        local host type count
        read -r host type count < <(echo "$jsondata1" | jq -r '[.Type, .Type, .Count] | join(" ")')

        echo -e "Type: ${BOLD}${type}${RESET}"
        echo "$tsvdata" | eval "$display_table" 2>/dev/null || echo "$tsvdata" | column -t -s $'\t'
        echo -e "Total Nodes Entities: ${BOLD}${count}${RESET}"

        hint "Usage: node list [--json | --yaml | --table]"
        ;;
    esac
}

cmd_node_show() {
    local name="$1"; shift

    [[ -z "$name" ]] && die "Usage: node show <name> "

    ensure_node "$name"

    if [[ "$1" == "--json" ]]; then
    echo $(
        echo "{"
        echo "  \"$name\": {"
        awk -v node="$name" '
        $0 ~ "\\[node \""node"\"\\]" {found=1; next}
        found && $0 ~ /^\[/ {exit}
        found {printf "    \"%s\": \"%s\",\n", $1, $3}
        ' "$CONFIG_FILE" | sed '$ s/,$//'
        echo "  }"
        echo "}" ) | jq
    else
        awk -v node="$name" '
        $0 ~ "\\[node \""node"\"\\]" {found=1; print; next}
        found && $0 ~ /^\[/ {exit}
        found {print}
        ' "$CONFIG_FILE"
    fi
}

########################################
# exec / test
########################################

cmd_node_exec() {
    local name="$1"; shift
    local cmd="$*"

    [[ -z "$cmd" ]] && die "Usage: node exec <name> <command>"

    ensure_node "$name"

    local host user pass
    host=$(get_node_field "$name" host)
    user=$(get_node_field "$name" user)
    pass=$(get_node_field "$name" pass)

    log "Executing on $name ($host)"

    sshpass -p "$pass" ssh -o StrictHostKeyChecking=no "$user@$host" "$cmd"
}

cmd_node_test() {
    local name="$1"
    ensure_node "$name"

    local host user pass
    host=$(get_node_field "$name" host)
    user=$(get_node_field "$name" user)
    pass=$(get_node_field "$name" pass)

    echo "[TEST] $name ($host)"

    if ping -c1 -W1 "$host" >/dev/null 2>&1; then
        echo "  Ping: OK"
    else
        echo "  Ping: FAIL"
        return
    fi

    if sshpass -p "$pass" ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "$user@$host" "echo ok" >/dev/null 2>&1; then
        echo "  SSH: OK"
    else
        echo "  SSH: FAIL"
    fi
}






########################################
# help system
########################################

cmd_node_help() {
    case "${1:-}" in
        add)
            cat <<EOF
${BOLD}Usage${RESET}:
  ${SCRIPT_NAME} node add <name> --host <ip> --user <user> --pass <pass>

${BOLD}Description${RESET}:
  Add a new server node

${BOLD}Options${RESET}:
  --host    BMC or server IP address
  --user    Login username
  --pass    Login password

${BOLD}Example${RESET}:
  $SCRIPT_NAME node add node01 --host 10.1.1.1 --user root --pass 1234
EOF
            ;;
        get)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node get <name> <field>

${BOLD}Description${RESET}:
  Get a field value from node

${BOLD}Example${RESET}:
  $SCRIPT_NAME node get node01 host
EOF
            ;;
        set)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node set <name> <field> <value>

${BOLD}Description${RESET}:
  Set a field value for node

${BOLD}Example${RESET}:
  $SCRIPT_NAME node set node01 user admin
EOF
            ;;
        remove)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node remove <name>

${BOLD}Description${RESET}:
  Remove a node

${BOLD}Example${RESET}:
  $SCRIPT_NAME node remove node01
EOF
            ;;
        list)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node list [--json | --yaml | --table]

${BOLD}Description${RESET}:
  List all nodes

${BOLD}Options${RESET}:
  --json     Output JSON
  --table    Output table (default)

${BOLD}Example${RESET}:
  $SCRIPT_NAME node list 
  $SCRIPT_NAME node list --json
  $SCRIPT_NAME node list --yaml
  $SCRIPT_NAME node list --table  
EOF
            ;;
        show)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node show <name> [--json]

${BOLD}Description${RESET}:
  Show node details

${BOLD}Example${RESET}:
  $SCRIPT_NAME node show node01
EOF
            ;;
        exec)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node exec <name> <command>

${BOLD}Description${RESET}:
  $SCRIPT_NAME on remote node via SSH

${BOLD}Example${RESET}:
  $SCRIPT_NAME node exec node01 "uptime"
EOF
            ;;
        test)
            cat <<EOF
${BOLD}Usage${RESET}:
  $SCRIPT_NAME node test <name>

${BOLD}Description${RESET}:
  Test node connectivity (Ping + SSH)

${BOLD}Example${RESET}:
  $SCRIPT_NAME node test node01
EOF
            ;;
        *)
            cat <<EOF
$SCRIPT_NAME node - manage server nodes

${BOLD}Usage${RESET}:
  $SCRIPT_NAME node <command> [options]

${BOLD}Commands${RESET}:
  add       Add new node
  get       Get node field
  set       Set node field
  delfield  Delete node dield
  remove    Remove node
  list      List nodes
  show      Show node detail
  exec      Execute remote command
  test      Test connectivity
  help      Show help

${BOLD}Examples${RESET}:
  $SCRIPT_NAME node add node01 --host 10.1.1.1 --user root --pass 1234
  $SCRIPT_NAME node list
  $SCRIPT_NAME node show node01 
  $SCRIPT_NAME node set node01 location Taipei
  $SCRIPT_NAME node set node01 vendor GBT  
  
${BOLD}Use${RESET}:
  $SCRIPT_NAME node help <command>

EOF
            ;;
    esac
}







cmd_node() {
    case "${1:-}" in
        add) shift; cmd_node_add "$@" ; cmd_node_show $1;;
        get) shift; cmd_node_get "$@" ;;
        set) shift; cmd_node_set "$@" ; cmd_node_show $1;;
        delfield) shift; cmd_node_delfield "$@" ; cmd_node_show $1;;
        remove) shift; cmd_node_remove "$@" ;;
        list) shift; cmd_node_list "$@" ;;
        show) shift; cmd_node_show "$@" ;;
        exec) shift; cmd_node_exec "$@" ;;
        test) shift; cmd_node_test "$@" ;;
        *) cmd_node_help ;;
    esac
}
