#!/usr/bin/env bash
# 假設 $RAW_DATA 是從 Redfish 抓回來的原始 JSON 陣列
format_output() {
    local data="$1"
    local format="$2"
    local filter="$3"

    # 1. 先執行使用者定義的 jq 過濾運算式
    if [ -n "$filter" ]; then
        data=$(echo "$data" | jq "$filter")
    fi

    # 2. 根據格式輸出
    case "$format" in
        --json)
            echo "$data" | jq .
            ;;
        --yaml)
            # 使用 python 或 yq 轉換
            echo "$data" | python3 -c 'import sys, yaml, json; print(yaml.dump(json.load(sys.stdin), sort_keys=False))'
            ;;
        --table)
            # 依據類別定義表頭，這裡以 CPU 為例
            echo "$data" | jq -r '["ID", "Model", "Cores", "Status"], (.[] | [.Id, .Model, .TotalCores, .Status.State]) | @tsv' | column -t -s $'\t'
            ;;
    esac
}

cmd_help() {
    cat <<EOF
${BOLD}$SCRIPT_NAME${RESET} v${VERSION} - BMC Server Manager CLI

${BOLD}USAGE${RESET}:
  $SCRIPT_NAME <command> <subcommand> [options]

${BOLD}COMMANDS${RESET}:
  discovery  Scan CIDR range(s) for BMC hosts
  node       Manage server nodes
  cluster    Manage clusters
  webui      Open BMC WebUI URL
  redfish    BMC faeture Management
  version    Show version
  help       Show this help

Run ${BOLD}$SCRIPT_NAME <command> --help${RESET} for command-specific help.

EOF
}

display_table='python3 -c "
import sys, os
try:
    import shutil
    from tabulate import tabulate
    data = [
      [ cell.replace(\"@@\", \"\n\") for cell in line.strip().split(\"\t\")] 
       for line in sys.stdin if line.strip()
    ]
    term_width = shutil.get_terminal_size().columns
    if data:
        #data.append(data[1])
        new_data = data.copy()
        headers = data.pop(0)
        fmt = os.getenv(\"TABLE_FMT\", \"fancy_grid\")
        h_table = tabulate(data, headers=headers, tablefmt=fmt)
        max_line_width = max(len(line) for line in h_table.split(\"\n\"))
        #print(term_width,max_line_width)
        #print(tabulate(data, headers=headers, tablefmt=fmt))
        if max_line_width <= term_width:
            # Horizontal Output
            print(h_table)
        else:
            #dbg print(new_data)
            transposed = [list(new_data) for new_data in zip(*new_data)]
            #dbg print(transposed)
            transposedheaders = transposed.pop(0)
            v_table=tabulate(transposed, headers=transposedheaders, tablefmt=fmt)
            max_line_width = max(len(line) for line in v_table.split(\"\n\"))
            if max_line_width <= term_width:
                # Horizontal Output
                print(v_table)
            else:
                # Vertical Output (Key-Value pairs)
                print(f\"Note: Output exceeds terminal width ({term_width}). Switching to vertical view.\n\")
                for i, row in enumerate(data, 1):
                    print(f\"--- [ Record {i} ] ---\")
                    # Pair headers with row data
                    v_data = list(zip(headers, row))
                    print(tabulate(v_data, tablefmt=fmt))
                    #print(\"-\" * 30)
except ImportError:
    sys.exit(1)
"'

run_python='python3 -c "
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