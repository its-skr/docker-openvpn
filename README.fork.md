create_region_setup_full.sh
для оновлення сертифікатів




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

## Резервный сервер

Основной: `185.69.153.81`, сети `10.8.<REGION>.0/24`.
Резервный: `57.131.195.188`, сети `10.9.<REGION>.0/24`, PKI скопирован с основного (сертификаты общие).

Клиент подключается к основному, если он доступен, иначе к резервному.
Сервер `client-<REGION>-db` подключён к обоим одновременно (`10.8.R.2` и `10.9.R.2`),
поэтому клиент всегда находит его по адресу «своя сеть + `.2`». Маршрутизация между серверами не нужна,
клиенты разных серверов друг друга не видят.

### 1. Запуск резервного сервера
Добавить management-интерфейс (нужен сторожу failback) в каждый регион резерва:
>for R in 26 73 68 44 56 61; do docker run --rm -v openvpn-$R:/d alpine sh -c 'grep -q "^management" /d/openvpn/server.conf || echo "management 0.0.0.0 7505" >> /d/openvpn/server.conf'; done

Порт 7505 доступен только внутри docker-сети, наружу не публикуется.
Скопировать на резерв `docker-compose.reserve.yaml` и `scripts/failback.sh` (с сохранением пути), затем:
>echo HOST_ADDR=57.131.195.188 > .env && docker compose -f docker-compose.reserve.yaml up -d

### 2. Сторож failback
Сам клиент OpenVPN на основной не возвращается. Контейнер `failback` проверяет основной регион
(TCP на `185.69.153.81:22<REGION>`). Если тот доступен `FAILBACK_STABLE_MIN` минут подряд, он отключает
всех клиентов резервного `vpn-<REGION>`, кроме `client-<REGION>-db`, и они переподключаются к основному.
Выключить: `FAILBACK_ENABLED: "0"` в `docker-compose.reserve.yaml`.
>docker compose -f docker-compose.reserve.yaml logs -f failback

### 3. Клиентские .ovpn
На машине, где есть volume региона (на резерве, чтобы не трогать продакшн):
>REGION=26 IMAGE=cloud.canister.io:5000/skr/skr-openvpn-server:tunnel ./helpers/add_reserve_remote.sh

В каждый `.ovpn` дописывается `remote 57.131.195.188 <PORT>` и `server-poll-timeout 10`;
результат в `./clients-26.tar.gz`. Сертификаты не меняются. Обычным клиентам раздать обновлённый `<id>.ovpn`.
Новые клиенты: `RESERVE_ADDR=57.131.195.188` (через `helpers/create_region_setup_full.sh` или `-e`) — нужен пересобранный образ.

### 4. Сервер client-<REGION>-db (Windows, OpenVPN как служба)
1. Добавить второй сетевой адаптер (cmd от администратора):
   >"C:\Program Files\OpenVPN\bin\tapctl.exe" create --hwid ovpn-dco

   (OpenVPN 2.5: `--hwid wintun`)
2. Положить `client-<REGION>-db-main.ovpn` и `client-<REGION>-db-reserve.ovpn` в
   `C:\Program Files\OpenVPN\config-auto\` (обычный `client-<REGION>-db.ovpn` оттуда убрать).
3. Перезапустить службу `OpenVPNService`. Проверить `ipconfig`: должны быть `10.8.R.2` и `10.9.R.2`.
