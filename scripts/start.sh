#!/bin/bash

source ./functions.sh

mkdir -p /dev/net

if [ ! -c /dev/net/tun ]; then
    echo "$(datef) Creating tun/tap device."
    mknod /dev/net/tun c 10 200
fi

# Allow UDP traffic on port 1194.
iptables -A INPUT -i eth0 -p udp -m state --state NEW,ESTABLISHED --dport 1194 -j ACCEPT
iptables -A OUTPUT -o eth0 -p udp -m state --state ESTABLISHED --sport 1194 -j ACCEPT

# Allow traffic on the TUN interface.
iptables -A INPUT -i tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT

# Allow forwarding traffic only from the VPN.
iptables -A FORWARD -i tun0 -o eth0 -s 10.8.26.0/24 -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -t nat -A POSTROUTING -s 10.8.26.0/24 -o eth0 -j MASQUERADE


cd $APP_PERSIST_DIR/server
cp ca.crt MyReq.crt MyReq.key ta.key /etc/openvpn

cd "$APP_INSTALL_PATH"

# Print app version
./version.sh

# Need to feed key password
openvpn --config $APP_PERSIST_DIR/openvpn/server.conf &

# By some strange reason we need to do echo command to get to the next command
echo " "

# Generate client config
#./genclient.sh $@

tail -f /dev/null
