#!/bin/bash

# Copy FROM ./scripts/server/conf TO $APP_PERSIST_DIR/openvpn/server.conf in DockerFile
mkdir $APP_PERSIST_DIR/openvpn
cd ${APP_INSTALL_PATH}
cp cat config/server.conf $APP_PERSIST_DIR/openvpn/server.conf
echo "REGION=$REGION"
{ cat config/server.conf; echo "server 10.8.$REGION.0 255.255.255.0"; } > $APP_PERSIST_DIR/openvpn/server.conf
cp config/ipp.txt $APP_PERSIST_DIR/openvpn/ipp.txt

cd ${APP_PERSIST_DIR}
cp pki/dh.pem $APP_PERSIST_DIR/openvpn


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
mkdir $APP_PERSIST_DIR/server
cp pki/ca.crt pki/issued/MyReq.crt pki/private/MyReq.key ta.key $APP_PERSIST_DIR/server
cp pki/ca.crt pki/issued/MyReq.crt pki/private/MyReq.key $APP_PERSIST_DIR/openvpn
