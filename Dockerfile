FROM alpine:3.11.3

ARG PASSWORD

ENV APP_NAME Dockovpn
ENV APP_INSTALL_PATH /opt/${APP_NAME}
ENV APP_PERSIST_DIR /opt/${APP_NAME}_data

WORKDIR ${APP_INSTALL_PATH}

COPY scripts .
COPY config ./config
COPY VERSION ./config

RUN adduser --disabled-password --gecos '' sshuser

RUN apk add --no-cache openvpn easy-rsa bash netcat-openbsd zip dumb-init openssh-server && \
    mkdir -p ${APP_PERSIST_DIR}

RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' /etc/ssh/sshd_config && \
    sed -i 's/AllowTcpForwarding no/AllowTcpForwarding yes/' /etc/ssh/sshd_config

RUN ssh-keygen -A && \
    echo "sshuser:${PASSWORD}" | chpasswd \
    && echo "root:${PASSWORD}" | chpasswd

ENV TZ=Europe/Kiev
RUN apk add tzdata && cp /usr/share/zoneinfo/Europe/Kiev /etc/localtime && echo "Europe/Kiev" >  /etc/timezone && apk del tzdata

RUN chmod +x create_server.sh create_clients.sh init_pki.sh ssh-server.sh

EXPOSE 1194/udp
EXPOSE 22

VOLUME [ "/opt/Dockovpn_data" ]

ENTRYPOINT [ "./ssh-server.sh" ]

CMD [ "dumb-init", "./start.sh" ]
