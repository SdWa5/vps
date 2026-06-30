# SdWa5 VPS Infrastructure

Contabo VPS · Debian 12 (bookworm) · all services in `/opt/docker/`

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
| Minecraft         | itzg/minecraft-server:latest   | 25565           | —                           | docker-compose.yml (commented out)  |

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
├── shopware-html-data/             # gitignored — Shopware web root + MySQL
├── shopware-mysql-data/            # gitignored
├── shopware-data/                  # gitignored (legacy mount)
├── dolibarr-mariadb-data/          # gitignored — Dolibarr SdWa5 DB
├── dolibarr-documents-data/        # gitignored — Dolibarr SdWa5 uploads
├── dolibarr-custom-data/           # gitignored — Dolibarr SdWa5 custom modules
├── vaultwarden-data/               # gitignored — Vaultwarden data
├── ollama-data/                    # gitignored — Ollama model cache
├── minecraft-data/                 # gitignored — Minecraft world data
└── rclone-config/                  # gitignored — rclone.conf with OAuth tokens
    └── rclone.conf
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
- Minecraft is fully configured but commented out; `minecraft-data/` persists the world.
