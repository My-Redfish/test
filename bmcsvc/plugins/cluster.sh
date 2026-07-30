#!/usr/bin/env bash
########################################
# cluster utils
########################################
CONFIG_DIR="${HOME}/.bmcsvr"
GROUPCONFIG_FILE="${CONFIG_DIR}/groupconfig"

mkdir -p "$CONFIG_DIR"
touch "$GROUPCONFIG_FILE"
ensure_cluster() {
    local group="$1"
    grep -q "^\[cluster \"$group\"\]" "$GROUPCONFIG_FILE" || die "Cluster '$group' not found"
}

get_cluster_nodes() {
    local group="$1"

    awk -v group="$group" '
    $0 ~ "\\[cluster \""group"\"\\]" {found=1; next}
    found && $0 ~ /^\[/ {exit}
    found && $1=="nodes" {print $3}
    ' "$GROUPCONFIG_FILE"
}

set_cluster_nodes() {
    local group="$1"
    local nodes="$2"

    awk -v group="$group" -v nodes="$nodes" '
    BEGIN {in_group=0; updated=0}
    {
        if ($0 ~ "\\[cluster \""group"\"\\]") {
            in_group=1
            print
            next
        }

        if (in_group && $0 ~ /^\[/) {
            if (!updated) {
                print "    nodes = " nodes
                updated=1
            }
            in_group=0
        }

        if (in_group && $1=="nodes") {
            print "    nodes = " nodes
            updated=1
            next
        }

        print
    }
    END {
        if (in_group && !updated) {
            print "    nodes = " nodes
        }
    }
    ' "$GROUPCONFIG_FILE" > "$GROUPCONFIG_FILE.tmp" && mv "$GROUPCONFIG_FILE.tmp" "$GROUPCONFIG_FILE"
}

cmd_cluster_add() {
    local group="$1"
    local node="$2"

    [[ -z "$group" || -z "$node" ]] && cmd_cluster_help add &&\
        die "Usage: cluster add <group> <node>"

    ensure_node "$node"

    if ! grep -q "^\[cluster \"$group\"\]" "$GROUPCONFIG_FILE"; then
        echo "[cluster \"$group\"]" >> "$GROUPCONFIG_FILE"
        echo "    nodes = $node" >> "$GROUPCONFIG_FILE"
        log "Cluster '$group' created"
        return
    fi

    local nodes
    nodes=$(get_cluster_nodes "$group")

    if [[ "$nodes" == *"$node"* ]]; then
        die "Node already in cluster"
    fi

    nodes="${nodes},${node}"
    set_cluster_nodes "$group" "$nodes"

    log "Added node '$node' to cluster '$group'"
}

cmd_cluster_remove() {
    local group="$1"
    [[ -z "$group" ]] && cmd_cluster_help remove && die "Usage: cluster remove <group>"

    ensure_cluster "$group"

    awk -v group="$group" '
    BEGIN {skip=0}
    {
        if ($0 ~ "\\[cluster \""group"\"\\]") {skip=1; next}
        if (skip && $0 ~ /^\[/) {skip=0}
        if (!skip) print
    }
    ' "$GROUPCONFIG_FILE" > "$GROUPCONFIG_FILE.tmp" && mv "$GROUPCONFIG_FILE.tmp" "$GROUPCONFIG_FILE"

    log "Cluster '$group' removed"
}

cmd_cluster_delnode() {
    local group="$1"
    local node="$2"

    [[ -z "$group" || -z "$node" ]] && cmd_cluster_help delnode && \
        die "Usage: cluster delnode <group> <node>"

    ensure_cluster "$group"

    local nodes
    nodes=$(get_cluster_nodes "$group")

    nodes=$(echo "$nodes" | sed "s/\b$node\b//g" | sed 's/,,/,/g' | sed 's/^,//;s/,$//')
    if [ -n "$nodes" ] ; then 
        set_cluster_nodes "$group" "$nodes"
        log "Removed node '$node' from '$group'"
    else
        set_cluster_nodes "$group" "$nodes"
        log "Removed node '$node' from '$group'"
        cmd_cluster_remove "$group" 
    fi
 
}

cmd_cluster_list() {
    case "$1" in
        --json)
            echo "{"
            awk '
            BEGIN {first=1}
            /^\[cluster/ {
                if (!first) printf ",\n"
                first=0
                name=$2
                gsub(/"|]/,"",name)
                printf "  \"%s\": {", name
            }
            $1=="nodes" {
                printf "\"nodes\": \"%s\"}", $3
            }
            END {print "\n}"}
            ' "$GROUPCONFIG_FILE"
            ;;
        *)
            printf "%-15s %-30s\n" "GROUP" "NODES"
            printf "%-15s %-30s\n" "-----" "-----"

            awk '
            /^\[cluster/ {
                name=$2
                gsub(/"|]/,"",name)
            }
            $1=="nodes" {
                printf "%-15s %-30s\n", name, $3
            }
            ' "$GROUPCONFIG_FILE"
            ;;
    esac
}

cmd_cluster_show() {
    local group="$1"

    ensure_cluster "$group"

    if [[ "$2" == "--json" ]]; then
        echo "{ \"$group\": {"
        awk -v group="$group" '
        $0 ~ "\\[cluster \""group"\"\\]" {found=1; next}
        found && $0 ~ /^\[/ {exit}
        found {printf "\"%s\": \"%s\"\n", $1, $3}
        ' "$GROUPCONFIG_FILE"
        echo "} }"
    else
        awk -v group="$group" '
        $0 ~ "\\[cluster \""group"\"\\]" {found=1; print; next}
        found && $0 ~ /^\[/ {exit}
        found {print}
        ' "$GROUPCONFIG_FILE"
    fi
}


cmd_cluster_help() {
    case "$1" in
        add)
            cat <<EOF
${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster add <group> <node>

${BOLD}Description${RESET}:
  Add a node to a cluster. If the cluster does not exist, it will be created.

${BOLD}Arguments${RESET}:
  <group>   Cluster name
  <node>    Node name (must exist)

${BOLD}Example${RESET}:
  bmcsvr-cli.sh cluster add group01 node01
EOF
            ;;
        remove)
            cat <<EOF
${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster remove <group>

${BOLD}Description${RESET}:
  Remove an entire cluster

${BOLD}Arguments${RESET}:
  <group>   Cluster name

${BOLD}Example${RESET}:
  bmcsvr-cli.sh cluster remove group01
EOF
            ;;
        delnode)
            cat <<EOF
${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster delnode <group> <node>

${BOLD}Description${RESET}:
  Remove a node from a cluster

${BOLD}Arguments${RESET}:
  <group>   Cluster name
  <node>    Node name

${BOLD}Example${RESET}:
  bmcsvr-cli.sh cluster delnode group01 node01
EOF
            ;;
        list)
            cat <<EOF
${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster list [--json | --table | --filter <expr>]

${BOLD}Description{RESET}:
  List all clusters

${BOLD}Options${RESET}:
  --json       Output in JSON format
  --table      Output in table format (default)
  --filter     Filter expression (future support)

${BOLD}Example${RESET}:
  bmcsvr-cli.sh cluster list --json
EOF
            ;;
        show)
            cat <<EOF
${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster show <group> [--json | --table | --filter <expr>]

${BOLD}Description${RESET}:
  Show details of a cluster

${BOLD}Arguments${RESET}:
  <group>   Cluster name

${BOLD}Options${RESET}:
  --json       Output in JSON format
  --table      Output in table format (default)
  --filter     Filter expression (future support)

${BOLD}Example${RESET}:
  bmcsvr-cli.sh cluster show group01
EOF
            ;;
        *)
            cat <<EOF
${BOLD}bmcsvr-cli.sh${RESET} cluster - manage server clusters

${BOLD}Usage${RESET}:
  bmcsvr-cli.sh cluster <command> [options]

${BOLD}Commands${RESET}:
  add        Add node to cluster (create if not exist)
  remove     Remove cluster
  delnode    Remove node from cluster
  list       List clusters
  help       Show help

${BOLD}Examples${RESET}:
  bmcsvr-cli.sh cluster add group01 node01
  bmcsvr-cli.sh cluster list
  bmcsvr-cli.sh cluster remove group01 node01
  bmcsvr-cli.sh cluster delnode group01 node01

${BOLD}CLUSTERCONFIG${RESET}
    Config stored in: ${CLUSTERCONFIG_DIR}/

${BOLD}Use${RESET}:
  bmcsvr-cli.sh cluster help <command>

EOF
            ;;
    esac
}

cmd_cluster() {
    case "$1" in
        help|"") shift; cmd_cluster_help "$@" ;;
        add) shift; cmd_cluster_add "$@" ; cmd_cluster_list ;;
        remove) shift; cmd_cluster_remove "$@" ; cmd_cluster_list ;;
        delnode) shift; cmd_cluster_delnode "$@" ; cmd_cluster_list ;;
        list) shift; cmd_cluster_list "$@" ;;
        *)
            cmd_cluster_help
            ;;
    esac
    
}