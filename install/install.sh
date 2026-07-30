echo "Hello World!"
pwd
ls -la
TMP="${PWD}"
echo "$TMP"


sudo mkdir -p /usr/local/lib/bmcsvc

sudo cp -a "$TMP/bmcsvc/." /usr/local/lib/bmcsvc/

sudo ln -sf \
    /usr/local/lib/bmcsvc/bmcsvc-cli.sh \
    /usr/local/bin/bmcsvc

sudo mkdir -p /usr/local/lib/Yafuflash

sudo cp -a "$TMP/Yafuflash/." /usr/local/lib/Yafuflash/

sudo ln -sf \
    /usr/local/lib/Yafuflash/Linux_x86_64/Yafuflash \
    /usr/local/bin/Yafuflash
    
rm -rf "$TMP"

echo "Installed."
