#!/bin/bash

/usr/share/easy-rsa/easyrsa init-pki && \
/usr/share/easy-rsa/easyrsa gen-dh && \
# DH parameters of size 2048 created at /usr/share/easy-rsa/pki/dh.pem
# Copy DH file
cp pki/dh.pem /etc/openvpn && \
# Copy FROM ./scripts/server/conf TO /etc/openvpn/server.conf in DockerFile
cd ${APP_INSTALL_PATH} && \
cp config/server.conf /etc/openvpn/server.conf && \
cp config/ipp.txt /etc/openvpn/ipp.txt

cd "$APP_PERSIST_DIR"

/usr/share/easy-rsa/easyrsa build-ca nopass << EOF

EOF
# CA creation complete and you may now import and sign cert requests.
# Your new CA certificate file for publishing is at:
# /opt/Dockovpn_data/pki/ca.crt

/usr/share/easy-rsa/easyrsa gen-req MyReq nopass << EOF2

EOF2
# Keypair and certificate request completed. Your files are:
# req: /opt/Dockovpn_data/pki/reqs/MyReq.req
# key: /opt/Dockovpn_data/pki/private/MyReq.key

/usr/share/easy-rsa/easyrsa sign-req server MyReq << EOF3
yes
EOF3
# Certificate created at: /opt/Dockovpn_data/pki/issued/MyReq.crt

openvpn --genkey --secret ta.key << EOF4
yes
EOF4

# Copy server keys and certificates
cp pki/ca.crt pki/issued/MyReq.crt pki/private/MyReq.key ta.key /etc/openvpn

