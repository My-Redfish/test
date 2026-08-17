import requests
import urllib3
import json

# 忽略 HTTPS 憑證警告（開發/內部測試環境常用）
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BMC_IP = "10.1.9.86"
USER = "test"
PASS = "gigabyte@123"
BASE_URL = f"https://{BMC_IP}"

def get_kvm_status():
    # 1. 定義 Redfish Manager 路徑 (依廠商可能微調，如 /redfish/v1/Managers/1)
    url = f"{BASE_URL}/redfish/v1/Managers/bmc"
    
    try:
        # 2. 發送 GET 請求獲取經理器詳細資訊
        response = requests.get(url, auth=(USER, PASS), verify=False, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            
            # 3. 解析 GraphicalConnect 屬性
            graphical_dict = data.get("GraphicalConnect", {})
            enabled = graphical_dict.get("ServiceEnabled", False)
            connect_types = graphical_dict.get("ConnectTypesSupported", [])
            port = graphical_dict.get("Port", "未標明")
            
            print(f"=== BMC KVM 狀態 ===")
            print(f"KVM 服務狀態: {'已啟用 (Enabled)' if enabled else '已停用 (Disabled)'}")
            print(f"支援的連線類型: {connect_types}")
            print(f"KVM 服務埠口 (Port): {port}")
            
            # 如果是 OpenBMC，通常會提供 WebSocket KVM 路徑
            # 例如: wss://<BMC_IP>/kvm/0
            if "KVMIP" in connect_types or enabled:
                print(f"\n[提示] 可透過 WebSocket 連線至: wss://{BMC_IP}/kvm/0")
                
        else:
            print(f"無法獲取資料，HTTP 狀態碼: {response.status_code}")
            print(response.text)
            
    except requests.exceptions.RequestException as e:
        print(f"連線失敗: {e}")

if __name__ == "__main__":
    get_kvm_status()