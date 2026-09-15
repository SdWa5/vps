# SdWa5 VPS Docker Config

Docker Compose configuration for all services running on the SdWa5 Contabo VPS.

## Requirements

- Docker + Docker Compose v1. The VPS has `docker-compose` 1.29.2. The v2 subcommand form `docker compose` does not exist there, so every command below uses the hyphenated binary.
- Caddy (system service, not in Docker)
- A `.env` file in this directory (see `.env.example`)

## Setup

```bash
cp .env.example .env
# Fill in all values in .env
docker-compose up -d
```

## Services

| Service            | URL                           | Compose file                   |
|--------------------|-------------------------------|--------------------------------|
| Shopware (SdWa5)   | https://sdwa5.org             | docker-compose.yml             |
| Vaultwarden        | https://vault.sdwa5.org       | docker-compose.yml             |
| Dolibarr SdWa5     | https://erp.sdwa5.org         | docker-compose.yml             |
| Ollama (inactive)  | :11434 (no public domain)     | docker-compose.yml (profile: ollama) |
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
[`docs/`](https://github.com/SdWa5/docs/tree/main/docs).

See `docs/` for per-service documentation:

- [Infrastructure overview](docs/infrastructure.md)
- [Shopware](docs/shopware/README.md)
- [Dolibarr](docs/dolibarr.md)
- [Vaultwarden](docs/vaultwarden.md)
- [Backup (Restic + rclone)](docs/backup.md)
- [Caddy](docs/caddy.md)
- [Ollama](docs/ollama.md)
- [Minecraft](docs/minecraft.md)
- [Maintenance (disk cleanup, log caps)](docs/maintenance.md)
- [Monitoring (health checks, alerts, Vaultwarden auto-update)](docs/monitoring.md)
- [SSH hardening (key-only access, fail2ban)](docs/ssh-hardening.md)

## Common operations

```bash
# Start all main services
docker-compose up -d

# Start Project 2/Project 3 services
docker-compose -f docker-compose.projects.yml up -d

# Start a profile-gated service (excluded from default up)
docker-compose --profile minecraft up -d
docker-compose --profile ollama up -d

# Restart a single service
docker-compose restart shopware

# Follow logs
docker-compose logs -f

# Reload Caddy config
systemctl reload caddy

# Health check on demand (see docs/monitoring.md)
/opt/docker/monitoring/vps-health.sh --dry-run

# Read the Dolibarr ERP from a workstation (see docs/dolibarr.md)
tools/dolibarr/doli.sh status

# Show what the project/task backlog would change in the ERP (--apply writes)
tools/dolibarr/sync-pm.sh
```

## Monitoring

Four cron jobs watch the box and mail every address in `MONITOR_MAIL_TO` when something is wrong.
It defaults to `ripper@sdwa5.org` alone, and any private address is configured in `.env` on the host
rather than committed here. A healthy system sends nothing. Vaultwarden updates itself daily, because
the Bitwarden clients auto-update and a server left behind stops working with them.

See [docs/monitoring.md](docs/monitoring.md).

## Host access

SSH is key-only. `PasswordAuthentication no` and `PermitRootLogin prohibit-password`, applied
2026-09-07 after 13,672 failed root logins in 24 hours, with fail2ban behind it. The deployable
config lives in [`hardening/`](hardening/).

The Contabo console remains the fallback and is unaffected by any of it, because it goes through
getty and PAM rather than sshd. See [docs/ssh-hardening.md](docs/ssh-hardening.md).

## Tests

```bash
tests/run.sh
```

Runs the bats suite for the monitoring scripts and `tools/`, plus shellcheck, both inside Docker.
Nothing has to be installed on the host.

[`.github/workflows/tests.yml`](.github/workflows/tests.yml) runs the same script on every push, so
CI and a local run are the same thing, and adds a secret scan over the working tree and the full
history:

```bash
gitleaks dir . --redact --config .gitleaks.toml
gitleaks git . --redact --config .gitleaks.toml
```

The tree scan flags `minecraft-data/server.properties` when you run it on a deploy checkout. That is
correct and expected: the live file holds a generated `rcon.password`, which is exactly why it is not
tracked. CI never sees it, because an untracked file is not in the clone.

## Licence

Two licences, because this repository is part tooling and part writing.

- **MIT** ([LICENSE](LICENSE)) for the code and configuration: `monitoring/`, `hardening/`, `minecraft/`, `tools/`, `tests/`, `.github/`, `Caddyfile`,
  `docker-compose*.yml` and `.env.example`.
- **CC BY-SA 4.0** ([LICENSE-docs](LICENSE-docs)) for the prose and data: `docs/`, `README.md`, `CHANGELOG.md` and `TODO.md`.

Attribute as "Musikverein Schmeiß die Wand an 5 (SdWa5)" with a link to the repository. Share-alike applies to the prose, so a
derivative of the documentation stays under the same licence. The code carries no such condition.

**Not ours to license**: `shopware-html-data/`, which is store-installed Shopware plugin content
tracked because those plugins are not managed through composer, and `minecraft-data/`, which is server
and mod configuration produced by the image and its mods, including 27 LuckPerms translation files.
Each carries its own vendor's terms.
