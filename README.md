# bmcsvc


## 安裝 (for WSL/Linux/MacOS)
```
curl -fsSL https://github.com/My-Redfish/test/releases/latest/download/install.sh | bash
```
## 安裝內容
```
ipmitool
redfishtool
Yafuflash
bmcsvc-cli
```
## bmcsvc 使用範例

### Version 
```
bmcsvc version
```

### Scan
```
bmcsvc scan 10.1.6.0/24
```
### 建立管理節點
```
bmcsvc node add <node> --host 10.1.1.1 --user admin --pass admin
bmcsvc node list
```
### Inventory
```
bmcsvc inventory <node> cpu
bmcsvc inventory <node> mem
bmcsvc inventory <node> fru
bmcsvc inventory <node> system
bmcsvc inventory <node> chassis
bmcsvc inventory <node> gpu
bmcsvc inventory <node> psu
bmcsvc inventory <node> storage
```
### Sensors
```
bmcsvc sensors <node> fan
bmcsvc sensors <node> temp
bmcsvc sensors <node> volt
bmcsvc sensors <node> sensor
bmcsvc sensors <node> thermal
```
### Power Control
```
bmcsvc powerctl <node> status
bmcsvc powerctl <node> on
bmcsvc powerctl <node> off
bmcsvc powerctl <node> forceoff
bmcsvc powerctl <node> powercycle
bmcsvc powerctl <node> forcerestart
```
### LED Control
```
bmcsvc ledctl <node> status
bmcsvc ledctl <node> lit
bmcsvc ledctl <node> off
bmcsvc ledctl <node> blinking
```
### FAN Control
```
bmcsvc fanctl <node> status
bmcsvc fanctl <node> fullspeed
bmcsvc fanctl <node> normal
bmcsvc fanctl <node> silent
```
### logs
```
bmcsvc logs <node> system
bmcsvc logs <node> audit
bmcsvc logs <node> event
```
### webui
```
bmcsvc webui <node>
```
### firmware
```
bmcsvc firmware <node> list
bmcsvc firmware <node> update <filepath>
```
持續整理ing


