
#!/bin/bash

# 設定參數
BMC_IP="10.1.9.86"
USER="test"
PASS="gigabyte@123"

echo "=== 1. 嘗試登入 Web API 獲取 Token ==="

# 呼叫 MegaRAC 的登入端點
LOGIN_REPLY=$(curl -sk -X POST "https://$BMC_IP/api/session" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\", \"password\":\"$PASS\"}" ) 
echo $LOGIN_REPLY
# 使用 jq 解析出 JSON 內的回傳 token
WEB_TOKEN=$(echo "$LOGIN_REPLY" | jq -r '.token // empty')

if [ -z "$WEB_TOKEN" ] || [ "$WEB_TOKEN" == "null" ]; then
    echo "[-] 登入失敗，無法取得 Token。"
    echo "原始回應: $LOGIN_REPLY"
    exit 1
fi

echo "[+] 成功取得 Token: ${WEB_TOKEN:0:10}..."

echo -e "\n=== 2. 測試 /api/status/uptime 端點 ==="

# 呼叫目標端點，必須將 Token 放入 X-CSRF-TOKEN 標頭中
UPTIME_REPLY=$(curl -sk -X GET "https://$BMC_IP/api/status/uptime" \
  -H "X-CSRF-TOKEN: $WEB_TOKEN" \
  -H "Accept: application/json")

echo "原始 JSON 回應:"
echo "$UPTIME_REPLY" | jq '.'

echo -e "\n=== 3. 解析 Uptime 結果 ==="
# 根據 AMI 標準規格，通常會回傳秒數或日/時/分，以下進行漂亮排版
echo "$UPTIME_REPLY" | jq -r '"BMC 已運行時間: " + (.uptime_str // .uptime // "未知")'