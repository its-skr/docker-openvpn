#!/usr/bin/env bash
#
# Add authoritative static-IP reservations (CCD) to an EXISTING region volume
# WITHOUT regenerating certificates. Clients keep their current .ovpn — no
# redistribution needed.
#
# Fixes the intermittent wrong-IP bug (e.g. client-56-db getting 10.8.56.62
# instead of 10.8.56.2): ifconfig-pool-persist only *prefers* an address and
# falls back to the dynamic pool when it is momentarily busy. client-config-dir
# with ifconfig-push *reserves* the address per client CN, and ccd-exclusive
# disables the dynamic pool entirely, so the wrong address can never be handed out.
#
# Run against the named volume (locally or on the VPS), then restart the container.
#
# Usage:
#   REGION=56 ./migrate_to_ccd.sh
#   REGION=61 IMAGE=cloud.canister.io:5000/skr/skr-openvpn-server:tunnel ./migrate_to_ccd.sh
#
# After it finishes:
#   docker-compose restart vpn-<REGION>
#
# NOTE: ccd-exclusive rejects any client whose CN has no CCD file. CCD files are
# built from the canonical address map (config/ipp.txt, region-substituted),
# which covers the standard client set (db, 03-50, 01-01..01-10). Any client
# outside that set would be locked out until you add a ccd/<cn> file for it.

set -euo pipefail

: "${REGION:?Set REGION, e.g. REGION=56 ./migrate_to_ccd.sh}"
IMAGE="${IMAGE:-skr2/skr-openvpn-server}"
VOLUME="openvpn-$REGION"

# Stop Git Bash from rewriting /opt/... and volume:/path arguments on Windows.
export MSYS_NO_PATHCONV=1

echo "==> Migrating volume $VOLUME to CCD static-IP reservations (image: $IMAGE)"
docker run --rm --entrypoint /bin/bash \
    -v "$VOLUME:/opt/Dockovpn_data" \
    -e REGION="$REGION" \
    "$IMAGE" -c '
set -e
cd /opt/Dockovpn_data/openvpn
# Switch server.conf from best-effort pool-persist to authoritative CCD.
sed -i "/ifconfig-pool-persist/d" server.conf
grep -q "^client-config-dir" server.conf || \
    printf "client-config-dir /opt/Dockovpn_data/openvpn/ccd\nccd-exclusive\n" >> server.conf
# Build one CCD file per client from the canonical address map.
mkdir -p ccd
sed "s/61/$REGION/g" /opt/Dockovpn/config/ipp.txt | tr -d "\r" | \
while IFS=, read -r cn ip; do
    [ -z "$cn" ] && continue
    echo "ifconfig-push $ip 255.255.255.0" > "ccd/$cn"
done
echo "--- server.conf (tail) ---"; tail -3 server.conf
echo "--- CCD files: $(ls ccd | wc -l) ---"
echo "--- sample: ccd/client-'"$REGION"'-db ---"; cat "ccd/client-$REGION-db" 2>/dev/null || true
'

echo "=============================================================="
echo " Done. Restart the container to apply:"
echo "   docker-compose restart vpn-$REGION"
echo
echo " Verify after restart (a client should always get its fixed IP):"
echo "   docker exec <container> cat ./openvpn-status.log"
echo "=============================================================="