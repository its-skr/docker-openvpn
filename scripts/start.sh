#!/bin/bash

cd "$APP_INSTALL_PATH"

# Print app version
./version.sh

# Need to feed key password
openvpn --config /etc/openvpn/server.conf &

# By some strange reason we need to do echo command to get to the next command
echo " "

# Generate client config
#./genclient.sh $@

#tail -f /dev/null
