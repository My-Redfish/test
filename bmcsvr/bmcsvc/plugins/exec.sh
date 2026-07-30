######################################
# help system
########################################

cmd_node_exec_help() {
    case "$1" in
          *)
            cat <<EOF
$SCRIPT_NAME exec - bmc webui operation

${BOLD}Usage${RESET}:
  $SCRIPT_NAME exec <command> [options]

${BOLD}Commands${RESET}:
  webui      Open BMC webui URL auto-login
  power       Get node field
  inventory   record webui
  account   record webui
  help      Show help

${BOLD}Examples${RESET}:
  $SCRIPT_NAME node exec open node01 

${BOLD}Use${RESET}:
  $SCRIPT_NAME webui help <command>

EOF
            ;;
    esac
}

cmd_node_exec() {
    case "$1" in
        webui) cmd_webui "$@";;
        *) cmd_webui_help ;;
    esac
}