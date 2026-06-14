#!/usr/bin/env bash
#
# Generate a full per-region OpenVPN setup (PKI, server cert, all clients)
# into the named volume openvpn-<REGION>, WITHOUT rebuilding the image.
#
# Certificate validity is passed at runtime via EASYRSA_CA_EXPIRE /
# EASYRSA_CERT_EXPIRE (easy-rsa reads them from the environment), so the
# existing image is used as-is. Default is 100 years (36500 days).
#
# The result is a tarball ./openvpn-<REGION>.tar.gz ready to copy to the VPS.
#
# Usage (Git Bash):
#   REGION=26 HOST_ADDR=<VPS_PUBLIC_IP> ./create_region_setup_full.sh
#
# Optional overrides (env vars):
#   PORT                external UDP port (auto-detected for known regions)
#   IMAGE               docker image to run (default: skr2/skr-openvpn-server)
#   EASYRSA_CA_EXPIRE   CA validity in days   (default: 36500)
#   EASYRSA_CERT_EXPIRE cert validity in days (default: 36500)
#   CLEAN               1 = wipe old data in the volume first (default: 1)

set -euo pipefail

# ---- Required input --------------------------------------------------------
: "${REGION:?Set REGION, e.g. REGION=26 HOST_ADDR=1.2.3.4 ./create_region_setup_full.sh}"
: "${HOST_ADDR:?Set HOST_ADDR to the VPS public IP (gets embedded into client .ovpn)}"

# ---- Defaults --------------------------------------------------------------
IMAGE="${IMAGE:-skr2/skr-openvpn-server}"
EASYRSA_CA_EXPIRE="${EASYRSA_CA_EXPIRE:-36500}"
EASYRSA_CERT_EXPIRE="${EASYRSA_CERT_EXPIRE:-36500}"
CLEAN="${CLEAN:-1}"
VOLUME="openvpn-$REGION"

# Region -> external UDP port (from docker-compose.yml / run.sh)
if [ -z "${PORT:-}" ]; then
    case "$REGION" in
        61) PORT=1193 ;;
        26) PORT=1195 ;;
        73) PORT=1196 ;;
        68) PORT=1197 ;;
        44) PORT=1198 ;;
        56) PORT=1199 ;;
        *)  echo "Unknown REGION '$REGION'; set PORT explicitly (PORT=...)." >&2; exit 1 ;;
    esac
fi

# Stop Git Bash from rewriting /opt/... and volume:/path arguments on Windows.
export MSYS_NO_PATHCONV=1

echo "=============================================================="
echo " Region        : $REGION"
echo " UDP port      : $PORT"
echo " Host (VPS IP) : $HOST_ADDR"
echo " Volume        : $VOLUME"
echo " Image         : $IMAGE"
echo " CA expire     : $EASYRSA_CA_EXPIRE days"
echo " Cert expire   : $EASYRSA_CERT_EXPIRE days"
echo "=============================================================="

# Helper: run a script/command in the image against this region's volume.
docker_run() {
    docker run --entrypoint /bin/bash --rm \
        -v "$VOLUME:/opt/Dockovpn_data" \
        -e REGION="$REGION" \
        -e PORT="$PORT" \
        -e HOST_ADDR="$HOST_ADDR" \
        -e EASYRSA_CA_EXPIRE="$EASYRSA_CA_EXPIRE" \
        -e EASYRSA_CERT_EXPIRE="$EASYRSA_CERT_EXPIRE" \
        "$IMAGE" "$@"
}

# ---- 0. Clean old data (so easyrsa init-pki does not prompt) ----------------
if [ "$CLEAN" = "1" ]; then
    echo "==> [0/5] Cleaning old data in volume $VOLUME"
    docker_run -c 'rm -rf /opt/Dockovpn_data/pki \
                          /opt/Dockovpn_data/openvpn \
                          /opt/Dockovpn_data/server \
                          /opt/Dockovpn_data/clients \
                          /opt/Dockovpn_data/ta.key'
fi

# ---- 1. PKI + DH -----------------------------------------------------------
echo "==> [1/5] init_pki.sh"
docker_run init_pki.sh

# ---- 2. CA + server cert + server.conf (subnet added automatically) --------
echo "==> [2/5] create_server.sh"
docker_run create_server.sh

# ---- 3. Addressing: region-correct ipp.txt + authoritative CCD reservations
# ipp.txt template is hardcoded to region 61. We also switch from best-effort
# ifconfig-pool-persist to client-config-dir (CCD), which truly reserves a
# fixed IP per client CN (no fallback to the dynamic pool -> no .61/.62 drift).
echo "==> [3/5] Configuring addressing (ipp.txt region + CCD reservations)"
docker_run -c '
set -e
cd /opt/Dockovpn_data/openvpn
sed -i "s/61/$REGION/g" ipp.txt
tr -d "\r" < ipp.txt > ipp.clean && mv ipp.clean ipp.txt
sed -i "/ifconfig-pool-persist/d" server.conf
grep -q "^client-config-dir" server.conf || \
    printf "client-config-dir /opt/Dockovpn_data/openvpn/ccd\nccd-exclusive\n" >> server.conf
mkdir -p ccd
while IFS=, read -r cn ip; do
    [ -z "$cn" ] && continue
    echo "ifconfig-push $ip 255.255.255.0" > "ccd/$cn"
done < ipp.txt
echo "CCD files generated: $(ls ccd | wc -l)"
'

# ---- 4. Generate all clients (remote = HOST_ADDR:PORT) ---------------------
echo "==> [4/5] create_clients.sh"
docker_run create_clients.sh

# ---- 5. Export the whole volume to a tarball on the host -------------------
# tar -> stdout -> host file: avoids Windows bind-mount path issues entirely.
# --entrypoint tar bypasses ssh-server.sh so nothing pollutes the tar stream.
echo "==> [5/5] Exporting volume to ./openvpn-$REGION.tar.gz"
docker run --rm -v "$VOLUME:/data" --entrypoint tar "$IMAGE" \
    czf - -C /data . > "openvpn-$REGION.tar.gz"

echo "=============================================================="
echo " Done. Verify validity:"
echo "   docker run --rm -v $VOLUME:/d --entrypoint /bin/bash $IMAGE \\"
echo "     -c 'openssl x509 -enddate -noout -in /d/pki/ca.crt'"
echo
echo " Transfer to the VPS:"
echo "   scp openvpn-$REGION.tar.gz user@vps:/tmp/"
echo "   # on VPS:"
echo "   docker-compose stop vpn-$REGION"
echo "   docker volume rm $VOLUME && docker volume create $VOLUME"
echo "   docker run --rm -v $VOLUME:/data -v /tmp:/backup alpine \\"
echo "     tar xzf /backup/openvpn-$REGION.tar.gz -C /data"
echo "   docker-compose up -d vpn-$REGION"
echo
echo " Then redistribute the new .ovpn files from clients/ to all clients."
echo "=============================================================="