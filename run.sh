#!/usr/bin/env bash

#docker stop openvpn-26
export PORT=1195 && export REGION=26
export PORT=1196 && export REGION=73
export PORT=1197 && export REGION=68

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

#docker exec openvpn-26 ./genclient.sh z

#/var/lib/docker/volumes/openvpn_26/_data/clients/client-26-01


#------------------------------
#docker run --cap-add=NET_ADMIN \
#-v openvpn_conf:/opt/Dockovpn \
#-p 1194:1194/udp -p 80:8080/tcp \
#-e HOST_ADDR=localhost \
#--rm \
#alekslitvinenk/openvpn "$@"
