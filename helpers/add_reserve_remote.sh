#!/usr/bin/env bash
#
# Add the reserve server as a second `remote` to every client .ovpn of a region
# (certificates are untouched, only the .ovpn text changes):
#
#   remote <PRIMARY> <PORT>
#   remote <RESERVE> <PORT>
#   server-poll-timeout 10
#
# For client-<REGION>-db (connected to BOTH servers at once, as two Windows
# service connections) it also writes two single-remote configs:
#   clients/client-<REGION>-db/client-<REGION>-db-main.ovpn     -> primary only
#   clients/client-<REGION>-db/client-<REGION>-db-reserve.ovpn  -> reserve only
#
# Idempotent. Works on the volume openvpn-<REGION> and exports the clients to
# ./clients-<REGION>.tar.gz.
#
# Usage (Git Bash / Linux):
#   REGION=26 ./helpers/add_reserve_remote.sh
#
# Optional env: PRIMARY (185.69.153.81), RESERVE (57.131.195.188),
#               IMAGE (skr2/skr-openvpn-server)

set -euo pipefail

: "${REGION:?Set REGION, e.g. REGION=26 ./helpers/add_reserve_remote.sh}"
PRIMARY="${PRIMARY:-185.69.153.81}"
RESERVE="${RESERVE:-57.131.195.188}"
IMAGE="${IMAGE:-skr2/skr-openvpn-server}"
VOLUME="openvpn-$REGION"

export MSYS_NO_PATHCONV=1

docker run --rm --entrypoint /bin/bash \
    -v "$VOLUME:/opt/Dockovpn_data" \
    -v "$(pwd):/export" \
    -e REGION="$REGION" -e PRIMARY="$PRIMARY" -e RESERVE="$RESERVE" \
    "$IMAGE" -c '
set -eu
cd /opt/Dockovpn_data/clients
n=0
for f in */*.ovpn; do
    case "$f" in *-db-main.ovpn|*-db-reserve.ovpn) continue ;; esac
    if ! grep -q "^remote $PRIMARY " "$f"; then
        echo "SKIP $f: no \"remote $PRIMARY\" line" >&2; continue
    fi
    grep -q "^remote $RESERVE " "$f" && continue
    awk -v p="$PRIMARY" -v r="$RESERVE" \
        "\$1 == \"remote\" && \$2 == p { print; print \"remote\", r, \$3; print \"server-poll-timeout 10\"; next } { print }" \
        "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    n=$((n + 1))
done
echo "updated $n client configs"

db="client-$REGION-db"
if [ -f "$db/$db.ovpn" ]; then
    grep -v -e "^remote $RESERVE " -e "^server-poll-timeout" "$db/$db.ovpn" > "$db/$db-main.ovpn"
    grep -v -e "^remote $PRIMARY " -e "^server-poll-timeout" "$db/$db.ovpn" > "$db/$db-reserve.ovpn"
    echo "wrote $db/$db-main.ovpn and $db/$db-reserve.ovpn"
else
    echo "WARN: $db/$db.ovpn not found" >&2
fi

tar czf "/export/clients-$REGION.tar.gz" -C /opt/Dockovpn_data clients
'

echo "==> ./clients-$REGION.tar.gz"
