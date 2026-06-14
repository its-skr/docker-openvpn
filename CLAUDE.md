# CLAUDE.md

## What this is

A personal fork of [dockovpn/dockovpn](https://github.com/dockovpn/dockovpn) used to run **multiple OpenVPN servers** (one per "region") from a single Docker image. It adds:

- A **per-region model**: each region is a numeric code (`REGION`) mapping to a UDP port and a dedicated `/24` subnet `10.8.<REGION>.0/24`.
- An **SSH gateway** inside the container (`sshd` + TCP forwarding) for tunneling/management.
- Static client IP assignments and a fixed client-naming scheme.

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
  - `start.sh` — main runtime: creates `/dev/net/tun`, sets iptables NAT/forwarding, copies certs into the openvpn dir, launches `openvpn`.
  - `ssh-server.sh` — entrypoint; starts sshd.
  - `init_pki.sh` — `easyrsa init-pki` + `gen-dh` (one-time per volume).
  - `create_server.sh` — builds CA + server cert + `ta.key`, writes `server.conf` appending `server 10.8.$REGION.0 255.255.255.0`, copies `ipp.txt`.
  - `create_clients.sh` — batch-generates the standard set of clients for a region.
  - `genclient.sh` — generates one client `.ovpn` (set `CLIENT_ID`); supports `z`/`zp`/`o`/`oz`/`ozp` flags for zip/password/stdout output.
  - `functions.sh` — shared helpers (`createConfig`, zip helpers, `datef`). `createConfig` embeds ca/cert/key/ta into the `.ovpn`.
  - `version.sh` — prints `$APP_NAME $APP_VERSION` from `config/VERSION`.
- `config/` — `server.conf`, `client.ovpn` (templates), `ipp.txt` (static IP map), `VERSION`.
- Runtime persistent data lives in volume `/opt/Dockovpn_data` (`$APP_PERSIST_DIR`): `pki/`, `openvpn/`, `server/`, `clients/<CLIENT_ID>/`.

## Provisioning a new region (run order)

Set `export PORT=<port> REGION=<code>`, then, all with `-v openvpn-$REGION:/opt/Dockovpn_data --entrypoint /bin/bash skr2/skr-openvpn-server <script>`:

1. `init_pki.sh` — init PKI + DH.
2. `create_server.sh` — CA, server cert, `server.conf`, `ipp.txt`.
3. **Manual edit** (see Gotchas): fix `server.conf` subnet and `ipp.txt` region numbers in the volume.
4. `create_clients.sh` (pass `-e HOST_ADDR=$(curl -s https://api.ipify.org) -e PORT -e REGION`) — generate clients.

Then run normally via `docker-compose up` (needs `.env` with `HOST_ADDR=...`).

## Client naming

`client-<REGION>-db` (head), `client-<REGION>-03..50` (departments), `client-<REGION>-01-01..10` (remote). IPs assigned statically in `ipp.txt` (`.2` for db, ascending thereafter).

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

- **`config/ipp.txt` is hardcoded to region `61`**; it must be edited per region (replace `61` with the target region) after `create_server.sh`, per `README.fork.md`.
- `server.conf` subnet line is appended by `create_server.sh`, but the static IPs in `ipp.txt` must match the region subnet — keep them consistent.
- `create_server.sh` line `cp cat config/server.conf ...` is a leftover typo; the next line overwrites the file via `{ cat ...; echo "server ..."; }`, so it is harmless but misleading.
- Client config HTTP-download server in `genclient.sh`/`start.sh` is commented out — clients are distributed manually from `clients/<id>/`.

## Branches

`master` (base), `tunnel` (SSH tunnel for Telegram / image tag in use), `gateway` (current — SSH gateway config). The compose file references the `:tunnel` image tag.

## Conventions

- Shell scripts are bash (POSIX `sh` for `ssh-server.sh`); they run inside Alpine in the container, not on the host.
- All paths inside scripts use `$APP_INSTALL_PATH` (`/opt/Dockovpn`) and `$APP_PERSIST_DIR` (`/opt/Dockovpn_data`).
- When changing per-region behavior, prefer parameterizing on `$REGION` rather than hardcoding subnet/port literals.