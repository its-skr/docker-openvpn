# CLAUDE.md

## What this is

A personal fork of [dockovpn/dockovpn](https://github.com/dockovpn/dockovpn) used to run **multiple OpenVPN servers** (one per "region") from a single Docker image. It adds:

- A **per-region model**: each region is a numeric code (`REGION`) mapping to a UDP port and a dedicated `/24` subnet `10.8.<REGION>.0/24`.
- An **SSH gateway** inside the container (`sshd` + TCP forwarding) for tunneling/management.
- **Fixed per-client IPs** via OpenVPN CCD (`client-config-dir` + `ccd-exclusive`) and a deterministic client-naming scheme.
- **Long-lived certificates** (100 years).

Authoritative human docs are in **`README.fork.md`** (Russian). `run.sh` is an operational cheat-sheet of commands, **not** a script meant to be run end-to-end. Upstream's `README.md` / `Makefile` (`alekslitvinenk/openvpn`) are inherited and not used by this fork.

## Regions

Current regions and their ports (see `run.sh` and `docker-compose.yml`):

| Region | VPN port (UDP→1194) | SSH port (→22) | Subnet |
|--------|--------|--------|--------|
| 61 | 1193 | 2261 | 10.8.61.0/24 |
| 26 | 1195 | 2226 | 10.8.26.0/24 |
| 73 | 1196 | 2273 | 10.8.73.0/24 |
| 68 | 1197 | 2268 | 10.8.68.0/24 |
| 44 | 1198 | 2244 | 10.8.44.0/24 (commented out) |
| 56 | 1199 | 2256 | 10.8.56.0/24 |

Each region has an **external** Docker volume `openvpn-<REGION>` holding its PKI, server config and generated clients under `/opt/Dockovpn_data`.

## Image

- Local build tag: `skr2/skr-openvpn-server` (built from `Dockerfile`).
- Registry image used by compose: `cloud.canister.io:5000/skr/skr-openvpn-server:tunnel`.
- Base: `alpine:3.11.3`. Installs `openvpn`, `easy-rsa`, `openssh-server`, `zip`, `dumb-init`.
- Entrypoint `scripts/ssh-server.sh` starts `sshd` (loads `authorized_keys` from the volume's `ssh_authorized_keys`), then runs CMD `dumb-init ./start.sh`.
- `Dockerfile` ARG `PASSWORD` sets the `root`/`sshuser` passwords; pass via `--build-arg PASSWORD=...`. SSH config permits root login, empty passwords and TCP forwarding (gateway use). Timezone `Europe/Kiev`.

## Layout

- `scripts/` — copied into the image at `/opt/Dockovpn` (`$APP_INSTALL_PATH`):
  - `start.sh` — main runtime: creates `/dev/net/tun`, sets iptables rules for the VPN's own traffic, copies certs from `server/` into `openvpn/`, launches `openvpn`.
  - `ssh-server.sh` — entrypoint; creates `/home/sshuser/.ssh`, installs `authorized_keys` from the volume, starts sshd.
  - `init_pki.sh` — `easyrsa init-pki` + `gen-dh` (one-time per volume).
  - `create_server.sh` — sources `functions.sh` (for cert-expiry env vars), builds CA + server cert + `ta.key`, writes `server.conf` appending `server 10.8.$REGION.0 255.255.255.0`, copies `ipp.txt`.
  - `create_clients.sh` — batch-generates the standard set of clients for a region.
  - `genclient.sh` — generates one client `.ovpn` (set `CLIENT_ID`); supports `z`/`zp`/`o`/`oz`/`ozp` flags for zip/password/stdout output.
  - `functions.sh` — shared helpers (`createConfig`, zip helpers, `datef`). `createConfig` embeds ca/cert/key/ta into the `.ovpn`.
  - `version.sh` — prints `$APP_NAME $APP_VERSION` from `config/VERSION`.
- `config/` — `server.conf`, `client.ovpn` (templates), `ipp.txt` (canonical CN→IP map, used to build CCD), `VERSION`.
- Root-level orchestration scripts (run on the **host**, drive the container via `docker run`):
  - `create_region_setup_full.sh` — one-shot full provisioning of a region into volume `openvpn-<REGION>` (PKI → server → CCD → clients → tarball), without rebuilding the image. See "Provisioning".
  - `migrate_to_ccd.sh` — adds CCD static-IP reservations to an **existing** region volume without regenerating certificates (so clients keep their `.ovpn`).
- Runtime persistent data lives in volume `/opt/Dockovpn_data` (`$APP_PERSIST_DIR`): `pki/`, `openvpn/` (incl. `ccd/`), `server/`, `clients/<CLIENT_ID>/`.

## Provisioning a new region

Preferred: the host script does everything in one pass (PKI, server, CCD, all clients, export tarball) and auto-detects the port from `REGION`:

```bash
REGION=26 HOST_ADDR=<VPS_PUBLIC_IP> ./create_region_setup_full.sh
# -> produces ./openvpn-26.tar.gz to copy onto the VPS
```

`HOST_ADDR` **must** be the VPS public IP (it gets embedded as `remote <HOST_ADDR> <PORT>` in every client `.ovpn`). The script internally runs `init_pki.sh` → `create_server.sh` → rewrites `ipp.txt` for the region + builds `ccd/` + patches `server.conf` for CCD → `create_clients.sh` → exports the volume. It uses the existing image (no rebuild); cert validity is passed via `EASYRSA_*` env vars.

The underlying scripts (`init_pki.sh`, `create_server.sh`, `create_clients.sh`) can still be run individually via `--entrypoint /bin/bash skr2/skr-openvpn-server <script>` against `-v openvpn-$REGION:/opt/Dockovpn_data`, but then the ipp.txt/CCD steps are manual.

Deploy: copy the tarball to the VPS, replace the volume contents, restart the container (preserve `ssh_authorized_keys` if used as a gateway — it is not in the tarball). Regenerating a region creates a **new CA**, so all client `.ovpn` must be redistributed.

## Client naming & fixed IPs

`client-<REGION>-db` (head), `client-<REGION>-03..50` (departments), `client-<REGION>-01-01..10` (remote) — 59 clients total. Each gets a fixed IP via a CCD file `ccd/<CN>` containing `ifconfig-push 10.8.<REGION>.<N> 255.255.255.0` (`.2` for db, ascending). The canonical CN→IP map is `config/ipp.txt` (region-substituted from the `61` template).

## Static IP addressing (CCD)

`config/server.conf` uses `client-config-dir /opt/Dockovpn_data/openvpn/ccd` + `ccd-exclusive`. This **reserves** each client's IP authoritatively and disables the dynamic pool — only clients with a `ccd/<CN>` file may connect. This replaced `ifconfig-pool-persist`, which only *preferred* an IP and would hand out a pool address (e.g. `.61`/`.62`) when the intended one was momentarily busy.

- Temporarily block a client: add `disable` to its `ccd/<CN>` file (reversible, no restart, no cert change).
- A client whose CN has no CCD file is rejected (consequence of `ccd-exclusive`).

## Certificate validity

Set to **100 years** (36500 days) via `EASYRSA_CA_EXPIRE` / `EASYRSA_CERT_EXPIRE`, exported in `scripts/functions.sh` (sourced by `create_server.sh`). easy-rsa 3.x defaults were ~3 years for certs / 10 years for the CA. The orchestration scripts also pass these via `-e`, so the existing image works without rebuilding. `dh.pem` and `ta.key` have no expiry.

## Common commands

```bash
# Build image
docker build -t skr2/skr-openvpn-server .

# Bring up all regions
echo HOST_ADDR=$(curl -s https://api.ipify.org) > .env && docker-compose up

# Generate one client (inside running container / via bash entrypoint)
CLIENT_ID=client-73-01-01 ./genclient.sh

# View connected clients for a region container
docker exec <container> cat ./openvpn-status.log

# Restart one region
docker ps && docker restart <container>
```

## Networking model

The VPN is used for **client-to-client communication only** — clients reach each other inside `10.8.<REGION>.0/24`. **Internet egress through the VPN is NOT required.** Client-to-client routing is provided by the `client-to-client` directive in `config/server.conf`, handled internally by the OpenVPN daemon (it does not use kernel IP forwarding or netfilter).

Because of this, `scripts/start.sh` keeps only the iptables rules for the VPN's own traffic (UDP 1194 in/out on `eth0`, accept on `tun0`). The FORWARD and NAT/MASQUERADE rules (internet egress) were removed — they were unused and were the only place that hardcoded `10.8.26.0/24`. Do not re-add forwarding/NAT unless internet egress becomes a requirement (which would also need `net.ipv4.ip_forward=1`).

## Gotchas (important)

- **`config/ipp.txt` is the canonical CN→IP map but is hardcoded to region `61`** (a template). `create_region_setup_full.sh` / `migrate_to_ccd.sh` substitute `61`→`$REGION` automatically; if you run the raw scripts, do it manually.
- `create_server.sh` line `cp cat config/server.conf ...` is a leftover typo; the next line overwrites the file via `{ cat ...; echo "server ..."; }`, so it is harmless but misleading (it prints two `cp` errors).
- Regenerating a region = new CA = **all client `.ovpn` must be redistributed**. CCD changes (via `migrate_to_ccd.sh`) do NOT touch certs, so no redistribution.
- `ssh_authorized_keys` lives in the volume root and is **not** included in the export tarball — re-add it after replacing a volume if the region is used as an SSH gateway.
- `crl.pem` (revocation) is not auto-handled; `start.sh` copies only `ca.crt/MyReq.crt/MyReq.key/ta.key` from `server/` into `openvpn/` on each start.
- Client config HTTP-download server in `genclient.sh`/`start.sh` is commented out — clients are distributed manually from `clients/<id>/`.

## Branches

`master` is the active branch — the `r61` work (regions, SSH gateway, CCD, 100-year certs, the orchestration scripts) has been fast-forward merged into it. `tunnel` and `gateway` are obsolete predecessors of the SSH-gateway feature (already superseded by what is in `master`); do not merge them. The compose file references the `cloud.canister.io:5000/skr/skr-openvpn-server:tunnel` image tag.

## Conventions

- Shell scripts are bash (POSIX `sh` for `ssh-server.sh`); the `scripts/` ones run inside Alpine in the container, the root-level `*.sh` run on the host (Git Bash on Windows).
- All paths inside the in-container scripts use `$APP_INSTALL_PATH` (`/opt/Dockovpn`) and `$APP_PERSIST_DIR` (`/opt/Dockovpn_data`).
- When changing per-region behavior, prefer parameterizing on `$REGION` rather than hardcoding subnet/port literals.
- This repo runs on Windows: `core.filemode` is set to `false` (Git ignores exec-bit churn), and the host scripts export `MSYS_NO_PATHCONV=1` to stop Git Bash from mangling `docker` path/volume arguments. The `Dockerfile` `chmod +x`'s the scripts it executes (incl. `start.sh`, `version.sh`, `genclient.sh`), so exec bits in Git don't matter for the image.