#!/usr/bin/env bash

#docker stop openvpn-26

docker build -t skr2/openvpn-server-26 .

docker run --entrypoint /bin/bash \
-v openvpn-26:/opt/Dockovpn_data \
--rm \
skr2/openvpn-server-26 \
init_pki.sh

docker run --entrypoint /bin/bash \
-v openvpn-26:/opt/Dockovpn_data \
--rm \
skr2/openvpn-server-26 \
create_server.sh

docker run --entrypoint /bin/bash \
-v openvpn-26:/opt/Dockovpn_data \
-e HOST_ADDR=$(curl -s https://api.ipify.org) \
-e PORT=1195 \
-e REGION=26 \
--rm \
skr2/openvpn-server-26 \
create_clients.sh

docker run --name openvpn-26 --cap-add=NET_ADMIN \
-d \
-p 1195:1194/udp -p 80:8080/tcp \
-v openvpn-26:/opt/Dockovpn_data \
--rm \
skr2/openvpn-server-26

docker logs openvpn-26 -f

#docker exec openvpn-26 ./genclient.sh z

#/var/lib/docker/volumes/openvpn_26/_data/clients/client-26-01


#------------------------------
#docker run --cap-add=NET_ADMIN \
#-v openvpn_conf:/opt/Dockovpn \
#-p 1194:1194/udp -p 80:8080/tcp \
#-e HOST_ADDR=localhost \
#--rm \
#alekslitvinenk/openvpn "$@"
