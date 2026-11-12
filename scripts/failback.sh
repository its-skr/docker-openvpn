#!/bin/bash
#
# Failback watchdog for the RESERVE server (see docker-compose.reserve.yaml).
#
# OpenVPN clients have two `remote` lines (primary first) but never move back
# on their own once they landed on the reserve. For every region this loop
# checks whether the primary region container is alive (TCP connect to its
# SSH port 22<REGION>, sshd runs in the same container as openvpn). Once the
# primary has been reachable for FAILBACK_STABLE_MIN minutes in a row, all
# clients on the reserve vpn-<REGION> are kicked via its management interface,
# except FAILBACK_KEEP (client-<REGION>-db is connected to both servers on
# purpose). Kicked clients reconnect and try the primary first.
#
# Requires `management 0.0.0.0 7505` in the reserve server.conf.
#
# Env:
#   FAILBACK_ENABLED     1 = on, 0 = do nothing (default 1)
#   FAILBACK_STABLE_MIN  minutes the primary must be up before kicking (default 5)
#   FAILBACK_REGIONS     space-separated region codes (default "26 73 68 44 56 61")
#   PRIMARY_ADDR         primary server address (default 185.69.153.81)
#   MGMT_PORT            reserve management port (default 7505)

FAILBACK_ENABLED="${FAILBACK_ENABLED:-1}"
FAILBACK_STABLE_MIN="${FAILBACK_STABLE_MIN:-5}"
FAILBACK_REGIONS="${FAILBACK_REGIONS:-26 73 68 44 56 61}"
PRIMARY_ADDR="${PRIMARY_ADDR:-185.69.153.81}"
MGMT_PORT="${MGMT_PORT:-7505}"

log() { echo "$(date '+%F %T') $*"; }

if [ "$FAILBACK_ENABLED" != "1" ]; then
    log "failback disabled (FAILBACK_ENABLED=$FAILBACK_ENABLED)"
    exec tail -f /dev/null
fi

log "failback on: regions [$FAILBACK_REGIONS], primary $PRIMARY_ADDR, stable ${FAILBACK_STABLE_MIN}m"

# Send management commands to the reserve vpn-<REGION>, print its reply.
mgmt() {
    local region="$1"; shift
    { printf '%s\n' "$@"; echo quit; } | nc -w 5 "vpn-$region" "$MGMT_PORT" | tr -d '\r'
}

declare -A up_min

while true; do
    for r in $FAILBACK_REGIONS; do
        if nc -z -w 5 "$PRIMARY_ADDR" "22$r" 2>/dev/null; then
            up_min[$r]=$(( ${up_min[$r]:-0} + 1 ))
        else
            up_min[$r]=0
            continue
        fi

        [ "${up_min[$r]}" -lt "$FAILBACK_STABLE_MIN" ] && continue

        keep="${FAILBACK_KEEP:-client-$r-db}"
        # status 2 -> "CLIENT_LIST,<CN>,<real addr>,<virtual addr>,..."
        clients=$(mgmt "$r" "status 2" | awk -F, -v keep="$keep" \
            '$1 == "CLIENT_LIST" && $2 != keep && $2 != "UNDEF" { print $2 }' | sort -u)

        if [ -n "$clients" ]; then
            log "region $r: primary up ${up_min[$r]}m, kicking back:" $clients
            mgmt "$r" "$(printf 'kill %s\n' $clients)" >/dev/null
        fi
        # ponytail: a client that cannot reach the primary from its side returns
        # to the reserve and gets kicked again every FAILBACK_STABLE_MIN minutes.
        up_min[$r]=0
    done
    sleep 60
done
