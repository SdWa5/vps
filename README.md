# SdWa5 VPS Docker Config

Docker Compose configuration for all services running on the SdWa5 Contabo VPS.

## Requirements

- Docker + Docker Compose v2
- Caddy (system service, not in Docker)
- A `.env` file in this directory (see `.env.example`)

## Setup

```bash
cp .env.example .env
# Fill in all values in .env
docker compose up -d
```

## Services

| Service            | URL                           | Compose file                   |
|--------------------|-------------------------------|--------------------------------|
| Shopware (SdWa5)   | https://sdwa5.org             | docker-compose.yml             |
| Vaultwarden        | https://vault.sdwa5.org       | docker-compose.yml             |
| Dolibarr SdWa5     | https://erp.sdwa5.org         | docker-compose.yml             |
| Ollama             | :11434 (no public domain)     | docker-compose.yml             |
| Restic backup      | —                             | docker-compose.yml             |
| Dolibarr Project 2 | https://project2.sdwa5.org | docker-compose.projects.yml |
| Dolibarr Project 3    | https://project3.sdwa5.org      | docker-compose.projects.yml |
| Minecraft (inactive) | :25565                      | docker-compose.yml (profile: minecraft) |

## Credentials

All secrets live in `.env` — never committed. See `.env.example` for required variable names.

## Documentation

`docs/` here holds the technical/ops documentation (*how* services run:
Docker, configs, operations). Org-level documentation (*what* they are used
for and *why*) lives in the parent repo's
[`docs/`](https://github.com/bestcodename/sdwa5/tree/master/docs).

See `docs/` for per-service documentation:

- [Infrastructure overview](docs/infrastructure.md)
- [Shopware](docs/shopware/README.md)
- [Dolibarr](docs/dolibarr.md)
- [Vaultwarden](docs/vaultwarden.md)
- [Backup (Restic + rclone)](docs/backup.md)
- [Caddy](docs/caddy.md)
- [Ollama](docs/ollama.md)
- [Minecraft](docs/minecraft.md)

## Common operations

```bash
# Start all main services
docker compose up -d

# Start Project 2/Project 3 services
docker compose -f docker-compose.projects.yml up -d

# Restart a single service
docker compose restart shopware

# Follow logs
docker compose logs -f

# Reload Caddy config
systemctl reload caddy
```
