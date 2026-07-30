#!/bin/bash
#curl.getservices.sh <BMC IP> <Username> <Password>
#NOTE : !!!! Very Important !!!!
#need to do follow things first
#sudo npm -g install jsontool

count=0

if [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ]
then
       BMC_IP=$1
       username=$2
       password=$3

##### step 1, create session
       echo -e "\n##### Post Session ....."
       curl -i -L -s -k --request POST \
         --url "https://$BMC_IP/api/session" \
         --header 'Cache-Control: no-cache' \
         --header 'Content-Type: application/x-www-form-urlencoded' \
         --header 'postman-token: a5bee417-5686-53d2-6476-1128149281c4' \
         --data "password=$password&username=$username" > tmp.json

       SESSION_HEADER=`grep -Po "Cookie: QSESSIONID=\w{30}" tmp.json`
       #SESSION_HEADER=`grep Set-Cookie tmp.json |awk -F ':' '{print $2}'`
       #CSRFTOKEN=`tail -n 1 tmp.json | awk -F ':' '{print $10}'|awk '{print $1}'|sed 's/\"//g'`
       CSRFTOKEN=`tail -n 1 tmp.json | json CSRFToken`

       echo "Login Session Info:"
       echo $SESSION_HEADER
       echo "Token: $CSRFTOKEN"

##### step 2, Get Service sessions
       echo -e "\n##### Get Services "


       RES=`curl -L -i -k   -w "%{http_code}" --request GET \
           --url "https://$BMC_IP/api/settings/services" \
           --header 'Connection: keep-alive' \
           --header "Host: $BMC_IP" \
           --header "$SESSION_HEADER" \
           --header "X-CSRFTOKEN: $CSRFTOKEN" \
           --header 'Cache-Control: no-cache' \
           --header 'Accept-Encoding: gzip, deflate, br, zstd' \
           --header 'Accept-Language: en-US,zh-TW;q=0.8,zh;q=0.5,en;q=0.3' \
           --header 'Content-Type: application\/json' \
           --header 'X-Requested-With: XMLHttpRequest' `
#                    --data "{\"service_id\":1}"`
       echo $RES

#                 count=`expr $count + 1`
#                 echo $count ":times"
#                 sleep 2
#                 if [ "$count" -gt "15000" ]
#                 then
#                         exit 0
#                 fi

###### step 3, delete session
       echo -e "\n##### Delete Session"
       RESPONSE=`curl -L -s -k --request DELETE \
         --url "https://$BMC_IP/api/session" \
         --header 'Cache-Control: no-cache' \
         --header "X-CSRFTOKEN: $CSRFTOKEN" \
         --header "$SESSION_HEADER"`
       echo "delete session response: "$RESPONSE

       exit 0
fi