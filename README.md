# test


## 安裝 (for WSL/Linux/MacOS)

curl -fsSL https://github.com/My-Redfish/test/releases/latest/download/install.sh | bash

## 安裝內容

ipmitool
redfishtool
bmcsvr-cli

## bmcsvr 使用範例

### 掃描BMC Machine 
bmcsvr scan 10.1.6.0/24

### 建立管理節點
bmcsver node add <node> --host 10.1.1.1 --user admin --pass admin
bmcsvr node list

### Inventory
'''
bmcsvr inventory <node> cpu
bmcsvr inventory <node> mem
bmcsvr inventory <node> fru
bmcsvr inventory <node> system
bmcsvr inventory <node> chassis
bmcsvr inventory <node> gpu
bmcsvr inventory <node> psu
bmcsvr inventory <node> storage
'''
### sensors
bmcsvr sensors <node> fan
bmcsvr sensors <node> temp
bmcsvr sensors <node> volt
bmcsvr sensors <node> sensor
bmcsvr sensors <node> thermal


### Power Control
bmcsvr powerctl <node> status
bmcsvr powerctl <node> on
bmcsvr powerctl <node> off
bmcsvr powerctl <node> forceoff
bmcsvr powerctl <node> powercycle
bmcsvr powerctl <node> forcerestart

### LED Control
bmcsvr ledctl <node> status
bmcsvr ledctl <node> lit
bmcsvr ledctl <node> off
bmcsvr ledctl <node> blinking

### FAN Control
bmcsvr fanctl <node> status
bmcsvr fanctl <node> fullspeed
bmcsvr fanctl <node> normal
bmcsvr fanctl <node> silent

### logs
bmcsvr logs <node> system
bmcsvr logs <node> audit
bmcsvr logs <node> event

### webui
bmcsvr webui <node>




