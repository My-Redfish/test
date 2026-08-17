
test_ouput ()
{
    echo -n "✅" | od -An -t x1
    echo -e "\u2705"

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'




    BOLD=$(tput bold)
    RESET=$(tput sgr0) 

    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)


    BG_RED=$(tput setab 1)
    BG_GREEN=$(tput setab 2)


}


test_jq () {


    data='{ "Name": "PSU2 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 231, "Status": "Absent" } { "Name": "USB4_FAN", "Speed": 4680, "Units": "RPM", "SensorNumber": 81, "Status": "Enabled" } { "Name": "W_PUMP+", "Speed": null, "Units": "RPM", "SensorNumber": 57, "Status": "Absent" } { "Name": "PSU2 FAN", "Speed": null, "Units": "RPM", "SensorNumber": 201, "Status": "Absent" } { "Name": "CHA_FAN5", "Speed": 3120, "Units": "RPM", "SensorNumber": 56, "Status": "Enabled" } { "Name": "CPU_OPT", "Speed": null, "Units": "RPM", "SensorNumber": 51, "Status": "Absent" } { "Name": "M.2_FAN", "Speed": 4320, "Units": "RPM", "SensorNumber": 84, "Status": "Enabled" } { "Name": "CPU_FAN", "Speed": null, "Units": "RPM", "SensorNumber": 50, "Status": "Absent" } { "Name": "CHA_FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 52, "Status": "Absent" } { "Name": "PSU1 FAN", "Speed": null, "Units": "RPM", "SensorNumber": 200, "Status": "Absent" } { "Name": "PSU1 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 226, "Status": "Absent" } { "Name": "CHA_FAN4", "Speed": null, "Units": "RPM", "SensorNumber": 55, "Status": "Absent" } { "Name": "VRMW_HS_FAN", "Speed": 0, "Units": "RPM", "SensorNumber": 83, "Status": "Enabled" } { "Name": "VRME_HS_FAN", "Speed": 0, "Units": "RPM", "SensorNumber": 82, "Status": "Enabled" } { "Name": "CHA_FAN3", "Speed": null, "Units": "RPM", "SensorNumber": 54, "Status": "Absent" } { "Name": "CHA_FAN2", "Speed": null, "Units": "RPM", "SensorNumber": 53, "Status": "Absent" }'
    echo $data | jq -s -c
    echo $data | jq -s -c --arg BMC_HOST "10.1.9.86" '{ Host: $BMC_HOST } + { Fans: (.) } + {Count: (. | length)} ' 

    echo $data | jq -s -c --arg BMC_HOST "test" '{
            Host: $BMC_HOST,
            Fans: (.), 
            Count: (. | length)
            }' 

    data1=$(echo $data | jq -s -c --arg BMC_HOST "test" '{
            Host: $BMC_HOST,
            Fans: (.), 
            Count: (. | length)
            }')        

    echo $data1

    echo $data1 | jq -c '.Fans | length'
    echo $data1 | jq -c '.Fans[0]'
    echo $data1 | jq '.Count'
    echo $data1 | jq '.Host'
    #{"Name":"PSU2 Slow FAN1","Speed":null,"Units":"RPM","SensorNumber":231,"Status":"Absent"} -> ["PSU2 Slow FAN1","Absent","RPM"]
    echo $data1 | jq -c '['Name', 'RPM', 'OK'],(.Fans[] | [ .Name, .Status , .Units ])'
    #["PSU2 Slow FAN1","Absent","RPM"] ->  "PSU2 Slow FAN1\tAbsent\tRPM"
    echo $data1 | jq -c '.Fans[] | [ .Name, .Status , .Units ] | @tsv' 

    echo '{"name": "Fan\t1"}' | jq -r .
    echo '{"name": "Fan\t1"}' | jq -r .name


    echo '"PSU2 Slow FAN1\tAbsent\tRPM" -> PSU2 Slow FAN1\tAbsent\tRPM'
    # -r important : remove ""
    echo $data1 | jq -r '.Fans[] | [ .Name, .Status , .Units ] | @tsv'  

    header='[ .Name, .Units , .Status ]'
    headerstr='[ "Name", "Units" , "Status" ]'
    echo $data1 | jq -r ".Fans[] | $header | @tsv" 


data3=$(echo $data1 | jq -r ".Fans[] | $header | @tsv") 
    echo $data3 | column -t -s $'\t'

    data2=$(echo $data1 | jq -r ".Fans[] | $header | @tsv"  ) 
    #echo $data2
#PSU2 Slow FAN1  Absent  RPM
#USB4_FAN        Enabled RPM
#W_PUMP+ Absent  RPM
#PSU2 FAN        Absent  RPM
#CHA_FAN5        Enabled RPM
#╒════════════════╤═════════╤══════════╕
#│ Name           │ Speed   │ Status   │
# ════════════════╪═════════╪══════════╡
#│ PSU2 Slow FAN1 │ Absent  │ RPM      │
#├────────────────┼─────────┼──────────┤
#│ USB4_FAN       │ Enabled │ RPM      │
#├────────────────┼─────────┼──────────┤
   
    echo $data1 | jq -r ".Fans[] | $header | @tsv" | python3 -c  \
        "import sys, tabulate; \
        print(tabulate.tabulate([line.strip().split('\t') for line in sys.stdin], headers=$headerstr, tablefmt='fancy_grid'))"
    #echo $data2 | python3 -c  \
    #    "import sys, tabulate; \
    #    print(tabulate.tabulate([line.strip().split('\t') for line in sys.stdin], headers=['Name', 'Speed', 'Status'], tablefmt='fancy_grid'))"

    exit 0    

}
#test_jq
: << 'COMMENT'
╒════════╤═════════╤══════════╕
│ Name   │ Units   │ Status   │
╞════════╪═════════╪══════════╡
│ Name   │ RPM     │ OK       │
├────────┼─────────┼──────────┤
│ FAN2   │ RPM     │ Absent   │
╘════════╧═════════╧══════════╛
COMMENT

test_table(){
jsondata='{ "Name": "PSU2 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 231, "Status": "Absent" } { "Name": "USB4_FAN", "Speed": 4680, "Units": "RPM", "SensorNumber": 81, "Status": "Enabled" }' 
    echo $jsondata | jq -s -c
    echo $jsondata | jq -s -c --arg BMC_HOST "10.1.9.86" '{ Host: $BMC_HOST } + { Fans: (.) } + {Count: (. | length)} ' 

    echo $jsondata | jq -s -c --arg BMC_HOST "test" '{
            Host: $BMC_HOST,
            Fans: (.), 
            Count: (. | length)
            }' 
            
    echo $jsondata | jq -s -r -c '[ "Name","Status" ,"Units" ],(.[] | [ .Name, .Status , .Units ])'

    echo $jsondata | jq -s -r -c '[ "Name","Status" ,"Units" ],(.[] | [ .Name, .Status , .Units ]) | @tsv'

echo $jsondata | jq -s -r -c '[ "Name","Status" ,"Units" ],(.[] | [ .Name, .Status , .Units ]) | @tsv' | od -c
    #echo $(echo $jsondata | jq -s -c '[ "Name","Status" ,"Units" ],(.[] | [ .Name, .Status , .Units ]) | @tsv')

tsvdata=$(echo $jsondata | jq -s -r -c '[ "Name","Status" ,"Units" ],(.[] | [ .Name, .Status , .Units ]) | @tsv')
echo "$tsvdata" | od -c
echo "$tsvdata" | head -n 1 | jq -R 'split("\t")' -c


headerstr="['Name', 'Units', 'Status']"
#headerstr="$(echo "$tsvdata" | head -n 1 | python3 -c "import sys; line = sys.stdin.readline().strip(); print(line.split('\t'))")"
tablefmt="'fancy_grid'"
firstlinerun="python3 -c \"
import sys, tabulate;
data = [line.strip().split('\t') for line in sys.stdin if line.strip()];
print(tabulate.tabulate(data, headers=$headerstr, tablefmt=$tablefmt))
\""

run="python3 -c \"
import sys, tabulate;
data = [line.strip().split('\t') for line in sys.stdin if line.strip()];
if data:
    headers = data.pop(0)
    print(headers)
    print(tabulate.tabulate(data, headers=headers, tablefmt=$tablefmt))
\""
echo $run
echo "$tsvdata" | eval "$run"

#exit 0
}

#test_table

test_table_fan(){
jsondata='{ "Name": "PSU2 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 231, "Status": "Absent" } { "Name": "USB4_FAN", "Speed": 4680, "Units": "RPM", "SensorNumber": 81, "Status": "Enabled" }' 
    #echo $jsondata | jq -s -c

    #dbgecho $jsondata | jq  -s -c --arg BMC_HOST "10.1.9.86" '{ Host: $BMC_HOST } + { Fans: .}  + {Count: length} '
    jsondata1=$(echo $jsondata | jq  -s -c --arg BMC_HOST "10.1.9.86" '{ Host: $BMC_HOST } + { Fans: .}  + {Count: length} ')

    #echo $jsondata1 | jq .
    #dbg echo $jsondata1 | jq  -r -c '.Host'
    echo "Host:${BOLD}$(echo $jsondata1 | jq  -r -c '.Host')${RESET}"
    #dbg echo $jsondata1 | jq  -r -c '.Count'
    echo "Count:${BOLD}$(echo $jsondata1 | jq  -r -c '.Count')${RESET}"
     #dbg echo $jsondata1 | jq  '.Fans[] | [ .Name, .Status , .Units ]' | jq -s -r '(["Name", "Status", "Units"] | @tsv), (.[] | @tsv)'
    #echo '[ "Name","Status" ,"Units" ]'
    #$tsvdata=$(echo $jsondata1 | jq  -c ' (.Fans | [ .Name, .Status , .Units ]) ' | jq -s -r '(["Name", "Status", "Units"] | @tsv), (.[] | @tsv)')
    tsvdata=$(echo $jsondata1 | jq  '.Fans[] | [ .Name, .Status , .Units ]' | jq -s -r '(["Name", "Status", "Units"] | @tsv), (.[] | @tsv)')
    tablefmt="'fancy_grid'"
    runwithheader="python3 -c \"
import sys, tabulate;
data = [line.strip().split('\t') for line in sys.stdin if line.strip()];
print(tabulate.tabulate(data, headers=$headerstr, tablefmt=$tablefmt))
\""

    run="python3 -c \"
import sys, tabulate;
data = [line.strip().split('\t') for line in sys.stdin if line.strip()];
if data:
    headers = data.pop(0)
    print(tabulate.tabulate(data, headers=headers, tablefmt=$tablefmt))
\""
    #echo $run
    echo "$tsvdata" | eval "$run"

#exit 0
 
}
test_table_fan

#json -> markdown
jsondata='{ "Name": "PSU2 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 231, "Status": "Absent" } { "Name": "USB4_FAN", "Speed": 4680, "Units": "RPM", "SensorNumber": 81, "Status": "Enabled" }' 
echo "$jsondata" | jq -s -r '
  ["Name", "Speed", "Status"],
  (.[] | [.Name[0:15], (.Speed|tostring), .Status])
  | "| " + join(" | ") + " |"'

jsondata='{ "Name": "PSU2 Slow FAN1", "Speed": null, "Units": "RPM", "SensorNumber": 231, "Status": "Absent" } { "Name": "USB4_FAN", "Speed": 4680, "Units": "RPM", "SensorNumber": 81, "Status": "Enabled" }' 
echo "$jsondata" | jq -s -r '
  ["Name", "Speed", "Status"],["----------", "--------", "---------"],
  (.[] | [.Name[0:15], (.Speed|tostring), .Status]) | @tsv'

python3 -c '
from tabulate import tabulate
headers = ["Id", "Socket", "Model", "Status"]
data = [
    ["CPU0", "Socket 0", "AMD Ryzen Threadripper\nPRO 9985WX 64-Cores", "Enabled"],
    ["CPU1", "Socket 1", "AMD Ryzen Threadripper\nPRO 9985WX 64-Cores", "Enabled"]
]
print(tabulate(data, headers=headers, tablefmt="fancy_grid"))
'

echo "ssssssss , dsdssddsd ,sdddsds,  sdsd," | jq '.Model | gsub(", "; "@@") | rtrimstr("@@")'
#exit 0