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
### Node
```
bmcsvc node add <node> --host 10.1.1.1 --user admin --pass admin
bmcsvc node list
bmcsvc node remove <node>
bmcsvc node set <node> host 10.1.1.1
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
bmcsvc inventory <node> pcie
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
### logs (SEL)
```
bmcsvc logs <node> sel
bmcsvc logs <node> info
```
### webui (需輸入login UD/Password)
```
bmcsvc webui <node>
```
### amisetup (需輸入login UD/Password)
```
bmcsvc amisetup <node>
```
### bmc firmware
```
bmcsvc bmcfw <node> status
bmcsvc bmcfw <node> update <filepath>
bmcsvc bmcfw <node> update live
```
### bios firmware
```
bmcsvc biosfw <node> status
bmcsvc biosfw <node> update <filepath>
bmcsvc biosfw <node> update live
```
持續整理ing


