# SdWa5 VPS Infrastructure

Contabo VPS · Debian 12 (bookworm) · all services in `/opt/docker/`

## Overview diagram

```mermaid
flowchart LR
    U((Internet))

    subgraph vps ["Contabo VPS · Debian 12"]
        C["Caddy<br/>systemd · TLS via Let's Encrypt"]

        subgraph docker ["Docker · /opt/docker"]
            SW["Shopware<br/>127.0.0.1:8001/8443"]
            VW["Vaultwarden<br/>127.0.0.1:8000"]
            DL["Dolibarr SdWa5<br/>127.0.0.1:8002"]
            DLC["dolibarr_cron"]
            DLDB[("MariaDB<br/>dolibarr_db")]
            P2["Dolibarr Project 2<br/>127.0.0.1:8003"]
            P2DB[("MariaDB")]
            P3["Dolibarr Project 3<br/>127.0.0.1:8004"]
            P3DB[("MariaDB")]
            OL["Ollama<br/>0.0.0.0:11434 · no auth"]
            MC["Minecraft<br/>0.0.0.0:25565 · profile, inactive"]
            RS["Restic backup<br/>daily 04:00 · source /opt/docker (ro)"]
        end
    end

    GD[("Google Drive<br/>rclone:SdWa5:restic-backups")]

    U -- "sdwa5.org" --> C
    U -- "vault.sdwa5.org" --> C
    U -- "erp.sdwa5.org" --> C
    U -- "project2/project3.sdwa5.org" --> C
    U -. ":11434" .-> OL
    U -. ":25565" .-> MC

    C --> SW & VW & DL
    C --> P2 & P3

    DL --> DLDB
    DLC --> DLDB
    P2 --> P2DB
    P3 --> P3DB

    RS -- "rclone (OAuth2)" --> GD
```

Domain → port mapping lives in the [Caddyfile](../Caddyfile); backup detail in
[backup.md](backup.md).

## Stack overview

| Service           | Image                          | Port (internal) | Public URL                  | Compose file                        |
|-------------------|--------------------------------|-----------------|-----------------------------|-------------------------------------|
| Shopware          | dockware/shopware:latest       | 8001 / 8443     | https://sdwa5.org           | docker-compose.yml                  |
| Vaultwarden       | vaultwarden/server:latest      | 8000            | https://vault.sdwa5.org     | docker-compose.yml                  |
| Dolibarr SdWa5    | dolibarr/dolibarr:latest       | 8002            | https://erp.sdwa5.org       | docker-compose.yml                  |
| Dolibarr SdWa5 cron | dolibarr/dolibarr:latest     | —               | —                           | docker-compose.yml                  |
| Dolibarr Project 2 | dolibarr/dolibarr:latest    | 8003            | https://project2.sdwa5.org | docker-compose.projects.yml    |
| Dolibarr Project 3   | dolibarr/dolibarr:latest       | 8004            | https://project3.sdwa5.org    | docker-compose.projects.yml      |
| Ollama            | ollama/ollama:latest           | 11434           | (no domain, port open)      | docker-compose.yml                  |
| Restic backup     | lobaro/restic-backup-docker    | —               | —                           | docker-compose.yml                  |
| Minecraft         | itzg/minecraft-server:latest   | 25565           | —                           | docker-compose.yml (profile: minecraft) |

Reverse proxy: **Caddy** (systemd service, not in Docker) — see [caddy.md](caddy.md)

## Directory layout (`/opt/docker/`)

```
/opt/docker/
├── docker-compose.yml              # main services
├── docker-compose.projects.yml  # Project 2 + Project 3 Dolibarr
├── .env                            # all secrets — NEVER commit
├── .env.example                    # template for .env
├── Caddyfile                       # Caddy reverse proxy config (copy for ref)
├── docker/
│   ├── nginx/                      # empty (unused)
│   └── php/                        # empty (unused)
├── docs/                           # this documentation
├── shopware-html-data/             # partially tracked — Shopware web root + MySQL
│   ├── composer.json/.lock, symfony.lock, config/*   # tracked
│   ├── custom/plugins/{FroshLazySizes,FroshPlatformFilterSearch,SwagPlatformSecurity,FroshShopmon}/
│   │                                                  # tracked — store-installed, not in composer.lock
│   └── .env, var/, vendor/, public/, files/, config/jwt/   # gitignored (secrets/build/uploads)
├── shopware-mysql-data/            # gitignored
├── shopware-data/                  # gitignored (legacy mount)
├── dolibarr-mariadb-data/          # gitignored — Dolibarr SdWa5 DB
├── dolibarr-documents-data/        # gitignored — Dolibarr SdWa5 uploads
├── dolibarr-custom-data/           # gitignored — only GeoLite2-Country.mmdb (MaxMind, re-downloadable)
├── vaultwarden-data/               # gitignored — Vaultwarden data
├── ollama-data/                    # gitignored — Ollama model cache
├── minecraft-data/                 # partially tracked — Minecraft world data
│   ├── server.properties, eula.txt, ops.json, whitelist.json, banned-*.json, config/   # tracked
│   │   (except config/Discord-Integration.toml — contains the bot token, stays gitignored)
│   └── world/, backup/, mods/, logs/, versions/, libraries/, cache/   # gitignored (data/rebuildable)
└── rclone-config/                  # gitignored — rclone.conf with OAuth tokens
    └── rclone.conf
```

## Memory & swap

5.8 GiB RAM. Two-tier swap: compressed zram first, swapfile as overflow.
Verified live 2026-07-04 (kernel 6.1.0-47-cloud-amd64).

```
NAME       TYPE      SIZE  USED PRIO
/dev/zram0 partition 3,5G 11,8M  100
/swapfile  file        6G 63,6M   -2
```

- **zram** via `zram-tools` package (`zramswap.service`, enabled).
  Config `/etc/default/zramswap`: `ALGO=zstd`, `PERCENT=60` → 3.5G device.
  Priority 100 → kernel swaps here first.
- **Swapfile** `/swapfile` 6G, `/etc/fstab` entry `/swapfile none swap sw 0 0`,
  priority -2 → only used when zram is full.
- **No zswap** — the Debian cloud kernel is built without it
  (`CONFIG_ZSWAP is not set` in `/boot/config-6.1.0-47-cloud-amd64`), so zram
  is the only in-RAM compression option here. The local desktop uses
  zswap + swapfile instead — see
  [ai/docs/debian/zswap-swap-setup.md](../../../ai/docs/debian/zswap-swap-setup.md).
- Sysctls at Debian defaults: `vm.swappiness=60`, `vm.page-cluster=3`.

```bash
# inspect
zramctl
swapon --show
systemctl status zramswap
```

## Common operations

```bash
# start all main services
cd /opt/docker && docker compose up -d

# restart single service
docker compose restart shopware

# view logs
docker compose logs -f shopware

# start project2/project3 services
docker compose -f docker-compose.projects.yml up -d

# reload Caddy config
systemctl reload caddy

# clear Shopware cache
docker exec shopware php bin/console cache:clear
```

## Notes

- Ollama port 11434 is bound to `0.0.0.0` (public). No auth. Consider firewall rule or binding to localhost if not needed externally.
- `docker/nginx/` and `docker/php/` dirs exist but are empty — historical artifact from initial setup.
- `shopware-data/` is a legacy volume mount, unused since migration to `shopware-html-data/`.
- Minecraft is fully configured but excluded from default `up` via compose profile `minecraft`;
  `minecraft-data/` persists the world.
- `shopware-html-data/` and `minecraft-data/` are no longer fully gitignored — see the tree above for which
  subpaths are tracked. `frosh/platform-thumbnail-processor` and `frosh/mail-platform-archive` are also
  installed plugins but stay untracked since they're proper `composer.json`/`composer.lock` requires and get
  reproduced by `composer install`.
