   rf_get "/" | jq '"RedfishVersion=\(.RedfishVersion)"'
   #rf_get "/SessionService" | jq '\(.SessionTimeout)'  #fail
     rf_get "/SessionService" | jq '"\(.SessionTimeout)"'  #"30"
    rf_get "/SessionService" | jq '.SessionTimeout'       #30
    rf_get "/SessionService" | jq '"SessionTimeout=\(.SessionTimeout)"' 
    rf_get "/SessionService" | jq -r '"SessionTimeout=\(.SessionTimeout)"'
