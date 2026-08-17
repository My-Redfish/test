#!/bin/bash
BMC_IP="10.1.9.86"
USER="test"
PASS="gigabyte@123"

# 1. 透過 Redfish 建立 Session 並獲取 Session Token
SESSION_INFO=$(curl -s -k -X POST https://$BMC_IP/redfish/v1/SessionService/Sessions \
   -H "Content-Type: application/json" -d "{\"UserName\":\"$USER\", \"Password\":\"$PASS\"}" -i)
echo $SESSION_INFO
# 2. 從 HTTP Header 中擷取 X-Auth-Token
TOKEN=$(echo "$SESSION_INFO" | grep -m 1 -i 'X-Auth-Token' | awk '{print $2}' | tr -d '\r')
echo $TOKEN
if [ -z "$TOKEN" ]; then
    echo "無法獲取 Token，請檢查認證或 BMC 是否支援 Redfish"
    exit 1
fi

# 3. 根據 BMC 廠牌的 URL 規則拼接直連 KVM 網址 
# (以下以常見的 KVM 導向路徑為例，實際路徑依 OpenBMC/AMI 廠牌定義可能微調)
KVM_URL="https://$BMC_IP/#/console?token=$TOKEN"
echo $KVM_URL
echo "正在為 $BMC_IP 啟動 HTML5 KVM..."

# 4. 用命令列直接呼叫系統預設瀏覽器開啟 (跨平台相容)
if command -v xdg-open &> /dev/null; then
    xdg-open "$KVM_URL" # Linux
elif command -v open &> /dev/null; then
    open "$KVM_URL"     # macOS
else
    cmd.exe /c start "$KVM_URL" # Windows / WSL
fi