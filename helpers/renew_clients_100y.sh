#!/bin/bash
# Issue new 100-year certs for ALL existing clients of a region (same keys, same CA)
# and rebuild their .ovpn (only <ca> and <cert> blocks replaced).
# Run AFTER renew_ca_100y.sh. Old .ovpn keep working until their own expiry.
#   REGION=61 ./helpers/renew_clients_100y.sh   -> ./clients-new-61.tar.gz
# Same layout as clients/: clients-new/<CN>/{<CN>.ovpn,<CN>.crt,<CN>.key,ca.crt,ta.key}
export MSYS_NO_PATHCONV=1
set -e
: "${REGION:?set REGION}"
IMAGE="${IMAGE:-skr2/skr-openvpn-server}"
VOL="openvpn-$REGION"
export PRIMARY="${PRIMARY:-185.69.153.81}" RESERVE="${RESERVE:-57.131.195.188}"

docker run --rm -e PRIMARY -e RESERVE -v "$VOL":/opt/Dockovpn_data -v "$PWD":/b --entrypoint /bin/bash "$IMAGE" -c '
set -e
cd /opt/Dockovpn_data
cp /usr/share/easy-rsa/x509-types/client /tmp/ext
echo "subjectKeyIdentifier=hash" >> /tmp/ext
echo "authorityKeyIdentifier=keyid,issuer:always" >> /tmp/ext
rm -rf clients-new; mkdir clients-new
for d in clients/*/; do
  cn=$(basename "$d")
  old="$d$cn.ovpn"
  [ -f "$old" ] && [ -f "pki/reqs/$cn.req" ] || { echo "SKIP $cn"; continue; }
  n="clients-new/$cn"; mkdir -p "$n"
  openssl x509 -req -in "pki/reqs/$cn.req" -CA pki/ca.crt -CAkey pki/private/ca.key \
    -CAserial pki/serial -days 36500 -extfile /tmp/ext -out "$n/$cn.crt" 2>/dev/null
  openssl verify -CAfile pki/ca.crt "$n/$cn.crt" >/dev/null
  cp "$d$cn.key" "$d/ta.key" "$n"; cp pki/ca.crt "$n"
  # replace <ca>/<cert> blocks, keep everything else
  awk -v ca=pki/ca.crt -v crt="$n/$cn.crt" '"'"'
    function dump(f,  l){ while ((getline l < f) > 0) print l; close(f) }
    /^<ca>/   { print; dump(ca);  skip=1; next }
    /^<cert>/ { print; dump(crt); skip=1; next }
    /^<\/(ca|cert)>/ { skip=0 }
    !skip'"'"' "$old" > "$n/$cn.ovpn"
  # ensure both servers: primary first, reserve second (same port); idempotent
  if ! grep -q "^remote $RESERVE " "$n/$cn.ovpn"; then
    awk -v p="$PRIMARY" -v r="$RESERVE" "\$1==\"remote\" && \$2==p { print; print \"remote\", r, \$3; print \"server-poll-timeout 10\"; next } { print }" \
      "$n/$cn.ovpn" > "$n/t" && mv "$n/t" "$n/$cn.ovpn"
  fi
  # db connects to both servers at once: one single-remote config for each
  case "$cn" in *-db)
    grep -v -e "^remote $RESERVE " -e "^server-poll-timeout" "$n/$cn.ovpn" > "$n/$cn-main.ovpn"
    grep -v -e "^remote $PRIMARY " -e "^server-poll-timeout" "$n/$cn.ovpn" > "$n/$cn-reserve.ovpn" ;;
  esac
  echo "OK $cn"
done
tar czf /b/clients-new-'"$REGION"'.tar.gz -C clients-new .
'
echo "Done: clients-new-$REGION.tar.gz (new .ovpn for each client)"
