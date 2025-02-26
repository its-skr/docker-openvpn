#!/bin/bash

function datef() {
    # Output:
    # Sat Jun  8 20:29:08 2019
    date "+%a %b %-d %T %Y"
}

function createConfig() {
    cd "$APP_PERSIST_DIR"
    CLIENT_PATH="$APP_PERSIST_DIR/clients/$CLIENT_ID"

    # Redirect stderr to the black hole
    /usr/share/easy-rsa/easyrsa build-client-full "$CLIENT_ID" nopass &> /dev/null
    # Writing new private key to '/usr/share/easy-rsa/pki/private/client.key
    # Client sertificate /usr/share/easy-rsa/pki/issued/client.crt
    # CA is by the path /usr/share/easy-rsa/pki/ca.crt

    mkdir -p $CLIENT_PATH

    cd "$APP_PERSIST_DIR"
    cp "pki/private/$CLIENT_ID.key" "pki/issued/$CLIENT_ID.crt" pki/ca.crt ta.key $CLIENT_PATH

    # Set default value to HOST_ADDR if it was not set from environment
    if [ -z "$HOST_ADDR" ]
    then
        HOST_ADDR='localhost'
    fi

    cd "$APP_INSTALL_PATH"
    cp config/client.ovpn $CLIENT_PATH/$CLIENT_ID.ovpn

    echo -e "\nremote $HOST_ADDR $PORT" >> "$CLIENT_PATH/$CLIENT_ID.ovpn"

    # Embed client authentication files into config file
    cat <(echo -e '<ca>') \
        "$CLIENT_PATH/ca.crt" <(echo -e '</ca>\n<cert>') \
        "$CLIENT_PATH/$CLIENT_ID.crt" <(echo -e '</cert>\n<key>') \
        "$CLIENT_PATH/$CLIENT_ID.key" <(echo -e '</key>\n<tls-auth>') \
        "$CLIENT_PATH/ta.key" <(echo -e '</tls-auth>') \
        >> "$CLIENT_PATH/$CLIENT_ID.ovpn"

    echo $CLIENT_PATH
}

function zipFiles() {
    CLIENT_PATH="$1"
    IS_QUITE="$2"

    # -q to silence zip output
    # -j junk directories
    zip -q -j "$CLIENT_PATH/$CLIENT_ID.zip" "$CLIENT_PATH/$CLIENT_ID.ovpn"
    if [ "$IS_QUITE" != "-q" ]
    then
       echo "$(datef) $CLIENT_PATH/$CLIENT_ID.zip file has been generated"
    fi
}

function zipFilesWithPassword() {
    CLIENT_PATH="$1"
    ZIP_PASSWORD="$2"
    IS_QUITE="$3"
    # -q to silence zip output
    # -j junk directories
    # -P pswd use standard encryption, password is pswd
    zip -q -j -P "$ZIP_PASSWORD" "$CLIENT_PATH/$CLIENT_ID.zip" "$CLIENT_PATH/$CLIENT_ID.ovpn"

    if [ "$IS_QUITE" != "-q" ]
    then
       echo "$(datef) $CLIENT_PATH/$CLIENT_ID.zip with password protection has been generated"
    fi
}
