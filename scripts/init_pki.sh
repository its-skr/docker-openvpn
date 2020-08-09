#!/bin/bash

cd ${APP_PERSIST_DIR}

/usr/share/easy-rsa/easyrsa init-pki && \
/usr/share/easy-rsa/easyrsa gen-dh
# DH parameters of size 2048 created at /usr/share/easy-rsa/pki/dh.pem
# Copy DH file

