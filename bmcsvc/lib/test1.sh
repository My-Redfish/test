#!/bin/bash

# Define the secret key used for encryption and decryption
# Keep this key safe; without it, the license cannot be reversed
SECRET_KEY="my_secure_key"

# Function to encode a password string into a 5-5 license key
encode_password() {
    local input_pass=$1
    
    # 1. Encrypt the input using AES-128-CBC with PBKDF2 key derivation
    # 2. Convert to Base32 to ensure character readability
    # 3. Clean characters: Replace potentially confusing 'I' and 'O' with '8' and '9'
    # 4. Truncate to 25 characters to fit the 5x5 format
    # 5. Insert hyphens every 5 characters using sed
    local encrypted=$(echo -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | \
        base32 | \
        tr -d '=' | \
        head -c 25 | \
        sed 's/.\{5\}/&-/g; s/-$//')
    echo -n "$input_pass" >&2
    echo  "openssl" >&2 
    echo -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 >&2
    echo  "base32" >&2     
    echo  -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | \
        base32  >&2
 echo  "trtt" >&2  
    echo  "KUZEM43EI5LGWWBRFNEHANZVOBFHI6KNNNKHSTCUJZCTGQLIMNIVMWLHGE2VA6TCJFCEKPIK" |  >&2

    echo  "tr\n\t" >&2   
    echo -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | \
        base32 | \
        tr -d '=' >&2
    echo  "head" >&2   
    echo -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | \
        base32 | \
        tr -d '=' | \
        head -c 25 >&2
    echo  "sed">&2       
    echo -n "$input_pass" | \
        openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | \
        base32 | \
        tr -d '=' | \
        tr 'IO' '89' | \
        head -c 25 | \
        sed 's/.\{5\}/&-/g; s/-$//'  >&2
    echo "ABCDEFGHIJKLMNOPQRSTUVWXY"   | \
        sed 's/.\{5\}/&-/g; s/-$//'  >&2  

    echo "$encrypted" 
}

# Function to decode a 5-5 license key back into the original password
decode_license() {
    local license=$1
    # 1. Remove hyphens and restore original Base32 characters ('8'->'I', '9'->'O')
    local clean_key=$(echo "$license" | tr -d '-' | tr '89' 'IO')
    # 2. Restore Base32 padding (Base32 strings must be multiples of 8 in length)
    local len=${#clean_key}
    local rem=$((len % 8))
    [[ $rem -ne 0 ]] && clean_key="${clean_key}$(printf '=%.0s' $(seq 1 $((8 - rem))))"

    # 3. Decode from Base32 and decrypt using the same AES settings
    # 2>/dev/null suppresses warnings if the key or padding is slightly off

    echo "$clean_key" | base32 -d 
    
    exit head -c 25
    local decrypted=$(echo "$clean_key" | \
        base32 -d | \
        openssl enc -aes-128-cbc -d -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 2>/dev/null)
    
    echo "$decrypted"
}

#

echo "ssssssssssssssssssssssssssssssssssss"
SECRET_KEY="my_secure_key"
input_pass="gigabyte@123"
    
echo -n "$input_pass" | openssl enc -aes-128-cbc -a -salt -pass "pass:$SECRET_KEY" -pbkdf2 | base32 | tr -d '=' | tr 'IO' '89' 
 #| tr '89' 'IO' | base32 -d | openssl enc -aes-128-cbc -d -a -salt -pass "pass:$SECRET_KEY" -pbkdf2
#openssl enc -aes-128-cbc -d -a -salt -pass "pass:$SECRET_KEY" -pbkdf2

    #ssldata="U2FsdGVkX18zQXu2ZULsL7CQmAaK9HwRxCKP4paFMV8="

    #echo $ssldate

 #   exit 0
 
echo "(((((((((((((((((((())))))))))))))))))))"
