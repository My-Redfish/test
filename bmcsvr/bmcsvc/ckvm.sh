#!/bin/bash
 tmp=`curl -i -sk -H "Content-Type:application/x-www-form-urlencoded" -d \
"username=test&password=gigabyte@123" -X POST https://10.1.9.86/api/session -D cookie`
echo $tmp 
 CSRF=`echo $tmp | awk -F "\"" '{print $28}'`
 echo "CSRF TOKEN:"$CSRF
 sess=`cat cookie |grep Set-Cookie |awk -F" " '{print $2}' |awk -F";" '{print $1}'`
 echo "SESSION TOKEN:"$sess







# tmp=`curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" X -k -F \
#'new_certificate=@filepath/sign_cert.pem' -F 'new_private_key=@filepath/privkey.pem' \
#https://10.1.9.86/api/settings/ssl/certificate`
 tmp=`curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -k \
https://10.1.9.86/api/status/uptime`
 echo $tmp

curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -k \
https://10.1.9.86/api/sensors | jq

curl -sk -X POST \
  -H "cookie: $sess" \
  -H "X-CSRFTOKEN: $CSRF" \
  -H "Content-Type: application/json" \
  "https://10.1.9.86/api/sol/session" 

curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF"  -sk \
https://10.1.9.86/api/sol/session | jq
curl -X DELETE -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -sk \
https://10.1.9.86/api/sol/session | jq
curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF"  -sk \
https://10.1.9.86/api/sol/session | jq

curl -X POST -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF"  -sk \
-H "Content-Type: application/json" \
https://10.1.9.86/api/sol/solcfg  


#fail curl -sk -b cookie -X DELETE https://10.1.9.86/api/session
curl -sk -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -X DELETE https://10.1.9.86/api/session | jq
curl -sk -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -X DELETE https://10.1.9.86/api/session | jq
#curl -X POST -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -s -k \
#curl -X POST -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -s -k \
#https://10.1.9.86/api/sol/session | jq
echo "lllllllllllllllllllllllllll"



exit




curl -H "cookie: $sess" -H "X-CSRFTOKEN:$CSRF" -k \
https://10.1.9.86/api/sensors 
 

