#!/usr/bin/env bash

#docker stop openvpn-26
export PORT=1195 && export REGION=26
export PORT=1196 && export REGION=73
export PORT=1197 && export REGION=68
export PORT=1198 && export REGION=44

docker build -t skr2/skr-openvpn-server .

echo HOST_ADDR=$(curl -s https://api.ipify.org) > .env && docker-compose up

docker run --entrypoint /bin/bash \
-v openvpn-$REGION:/opt/Dockovpn_data \
--rm \
skr2/skr-openvpn-server \
init_pki.sh

docker run --entrypoint /bin/bash \
-v openvpn-$REGION:/opt/Dockovpn_data \
--rm \
skr2/skr-openvpn-server \
create_server.sh

docker run --entrypoint /bin/bash \
-v openvpn-$REGION:/opt/Dockovpn_data \
-e HOST_ADDR=$(curl -s https://api.ipify.org) \
-e PORT=$PORT \
-e REGION=$REGION \
--rm \
skr2/skr-openvpn-server \
create_clients.sh

docker run --name openvpn-$REGION --cap-add=NET_ADMIN \
-p $PORT:1194/udp -p 80:8080/tcp \
-v openvpn-$REGION:/opt/Dockovpn_data \
--rm \
skr2/skr-openvpn-server

# Update server.conf (add region number in network mask)
# Update ipp.txt (replace 26 region with the real one)
