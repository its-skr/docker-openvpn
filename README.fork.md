Для установки используются команды из *run.sh*  

При внесении изменений в образ:  
- **git pull**  
- **docker build -t skr2/skr-openvpn-server .**

Для создания нового сервера необходимо:
1.  Установить переменные  
**export PORT=1197 && export REGION=68**

2. Инициализировать pki  
>docker run --entrypoint /bin/bash \
-v openvpn-$REGION:/opt/Dockovpn_data \
--rm \
skr2/skr-openvpn-server \
init_pki.sh

3. Создать сервер  
>docker run --entrypoint /bin/bash \
 -v openvpn-$REGION:/opt/Dockovpn_data \
 --rm \
 skr2/skr-openvpn-server \
 create_server.sh

После этого необходимо отредактировать ipp.txt  
и отредактировать сеть сервера в server.conf

4. Сформировать клиентов  
>docker run --entrypoint /bin/bash \
 -v openvpn-$REGION:/opt/Dockovpn_data \
 -e HOST_ADDR=$(curl -s https://api.ipify.org) \
 -e PORT=$PORT \
 -e REGION=$REGION \
 --rm \
 skr2/skr-openvpn-server \
 create_clients.sh

Пример запуска контейнера для одного региона:  
>docker run --name openvpn-$REGION --cap-add=NET_ADMIN \
 -p $PORT:1194/udp -p 80:8080/tcp \
 -v openvpn-$REGION:/opt/Dockovpn_data \
 --rm \
 skr2/skr-openvpn-server

Пример формирования одного клиента:  
>CLIENT_ID=client-73-01-01 ./genclient.sh

Путь к volume:
>/var/lib/docker/volumes/openvpn_26/_data/clients/client-26-01

Для добавления региона необходимо обновить docker-compose.yaml  
и перезапустить композицию.
>echo HOST_ADDR=$(curl -s https://api.ipify.org) > .env && docker-compose up

Можно перезапустить один контейнер.
>docker ps  
>docker restart

Просмотр подключенных клиентов:
>docker exec dockeropenvpn_vpn-73_1 cat ./openvpn-status.log
