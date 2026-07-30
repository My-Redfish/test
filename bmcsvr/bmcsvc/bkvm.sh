#!/bin/bash
BMC_IP="10.1.9.86"
USER="test"
PASS="gigabyte@123"
#"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --app="https://192.168.1.100/html/kvm.html"
# 1. 透過 Redfish 取得 Session Token
TOKEN=$(curl -k -X POST "https://${BMC_IP}/redfish/v1/SessionService/Sessions" \
  -H "Content-Type: application/json" \
  -d "{\"UserName\":\"${USER}\",\"Password\":\"${PASS}\"}" \
  -i )
#TOKEN=$(curl -k -X POST "https://${BMC_IP}/viewer.html" \
#  -H "Content-Type: application/json" \
#  -d "{\"UserName\":\"${USER}\",\"Password\":\"${PASS}\"}" \
#  -i | grep -i 'X-Auth-Token' | awk '{print $2}' | tr -d '\r')

#curl -k -X POST "https://${BMC_IP}/viewer.html" \
#  -H "Content-Type: application/json" \
#  -d "{\"UserName\":\"${USER}\",\"Password\":\"${PASS}\"}" \
#  -i
echo "AAAAACCCCAAAAAAAAAAAAA"
#curl -k -X POST "https://${BMC_IP}/redfish/v1/SessionService/Sessions" \
#  -H "Content-Type: application/json" \
#  -d "{\"UserName\":\"${USER}\",\"Password\":\"${PASS}\"}" \
#  -i | grep -m 1 -i "X-Auth-Token:" | awk '{print $2}'
echo $TOKEN
echo "AAAAAAAAAAAAAAAAAA"
# 2. 根據不同廠牌的機制，將 Token 帶入 H5Viewer 網址中（此處以示意為主，各家參數不同）
# 註：部分廠商支援透過 URL 帶 Token，部分則需要寫入 Cookie
#google-chrome --app="https://${BMC_IP}/html/kvm.html?token=${TOKEN}"
#"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --app="https://${BMC_IP}/html/kvm.html?token=${TOKEN}"
#"/mnt/c/Program Files/Google/Chrome/Application/chrome.exe" --app="https://${BMC_IP}"
#viewer.html
curl -k -X POST "https://${BMC_IP}/api/sessions" \
  -H "Content-Type: application/json" \
  -d "{\"UserName\":\"${USER}\",\"Password\":\"${PASS}\"}" \
  -i 
