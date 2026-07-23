echo "Hello World!"
pwd
ls -la
TMP="${PWD}"
echo "$TMP"


sudo mkdir -p /usr/local/lib/bmcsvr

sudo cp -a "$TMP/bmcsvr/." /usr/local/lib/bmcsvr/

sudo ln -sf \
    /usr/local/lib/bmcsvr/bmcsvr-cli.sh \
    /usr/local/bin/bmcsvc

rm -rf "$TMP"

echo "Installed."
