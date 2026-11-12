#!/bin/bash
# Re-issue CA (same key/subject/serial) and server cert (same key) for 100 years.
# Old client .ovpn keep working: they chain to the same CA key. Run on the host
# that owns the volume (VPS), then restart the region container.
#   REGION=61 ./helpers/renew_ca_100y.sh
export MSYS_NO_PATHCONV=1
set -e
: "${REGION:?set REGION}"
IMAGE="${IMAGE:-skr2/skr-openvpn-server}"
VOL="openvpn-$REGION"

# Backup first (volume is production data)
docker run --rm -v "$VOL":/d -v "$PWD":/b --entrypoint tar "$IMAGE" czf "/b/$VOL.backup-$(date +%F).tar.gz" -C /d .

docker run --rm -v "$VOL":/opt/Dockovpn_data --entrypoint /bin/bash "$IMAGE" -c '
set -e
cd /opt/Dockovpn_data/pki
# CA: re-sign existing cert with its own key; subject, serial, extensions are kept
openssl x509 -in ca.crt -signkey private/ca.key -days 36500 -out ca.new
mv ca.new ca.crt
# Server cert: same key (from existing req), new serial, 100 years
cp /usr/share/easy-rsa/x509-types/server /tmp/ext
echo "subjectKeyIdentifier=hash" >> /tmp/ext
echo "authorityKeyIdentifier=keyid,issuer:always" >> /tmp/ext
openssl x509 -req -in reqs/MyReq.req -CA ca.crt -CAkey private/ca.key \
  -CAserial serial -days 36500 -extfile /tmp/ext -out issued/MyReq.crt
# Check: new server cert AND every existing client cert still verify
openssl verify -CAfile ca.crt issued/*.crt | grep -v ": OK" && { echo VERIFY FAILED; exit 1; } || true
cd ..
cp pki/ca.crt pki/issued/MyReq.crt server/
cp pki/ca.crt pki/issued/MyReq.crt openvpn/
openssl x509 -in pki/ca.crt -noout -enddate
openssl x509 -in pki/issued/MyReq.crt -noout -enddate
'
echo "Done. Restart the container for region $REGION."
