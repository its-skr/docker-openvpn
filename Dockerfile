FROM alpine:3.11.3

ENV APP_NAME Dockovpn
ENV APP_INSTALL_PATH /opt/${APP_NAME}
ENV APP_PERSIST_DIR /opt/${APP_NAME}_data

WORKDIR ${APP_INSTALL_PATH}

COPY scripts .
COPY config ./config
COPY VERSION ./config

RUN apk add --no-cache openvpn easy-rsa bash netcat-openbsd zip dumb-init && \
    mkdir -p ${APP_PERSIST_DIR}

ENV TZ=Europe/Kiev
RUN apk add tzdata && cp /usr/share/zoneinfo/Europe/Kiev /etc/localtime && echo "Europe/Kiev" >  /etc/timezone && apk del tzdata

RUN chmod +x create_server.sh create_clients.sh init_pki.sh

EXPOSE 1194/udp

VOLUME [ "/opt/Dockovpn_data" ]

ENTRYPOINT [ "dumb-init", "./start.sh" ]
CMD [ "" ]
