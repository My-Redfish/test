BMC_IP=10.1.9.86
USER=test
PASS=gigabyte


SERVICE=$(curl -k -u $USER:$PASS https://$BMC_IP/redfish/v1/ \
| jq -r '.Systems["@odata.id"]')

SYSTEM=$(curl -k -u $USER:$PASS https://$BMC_IP$SERVICE \
  | jq -r '.Members[0]["@odata.id"]')

curl -sk -u $USER:$PASS https://$BMC_IP$SYSTEM | jq -r '.Model, .Manufacturer'



rf_system() {
  curl -sk -u "$USER:$PASS" https://$BMC_IP/redfish/v1/Systems \
  | jq -r '.Members[]."@odata.id"'
}

rf_get() {
  curl -sk -u "$USER:$PASS" https://$BMC_IP$1 | jq
}

SYS=$(rf_system)
rf_get $SYS