# SdWa5 VPS Docker Config

Docker Compose configuration for all services running on the SdWa5 Contabo VPS.

## Requirements

- Docker + Docker Compose v2. The VPS runs docker-ce 29.9.1 with the `docker compose` plugin 5.6.0 from download.docker.com since 2026-10-15, so every command below uses the subcommand form. See [docs/maintenance.md](docs/maintenance.md#docker-packages).
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
| Paperless-ngx Verein | https://paper.sdwa5.org     | docker-compose.yml             |
| Paperless-ngx household | https://paper.ripper.sdwa5.org | docker-compose.yml        |
| Ollama (inactive)  | :11434 (no public domain)     | docker-compose.yml (profile: ollama) |
| Restic backup      | —                             | docker-compose.yml             |
| Dolibarr Project 2 | https://project2.sdwa5.org | docker-compose.projects.yml |
| Dolibarr Project 3    | https://project3.sdwa5.org      | docker-compose.projects.yml |
| Chimo Diazz        | https://chimodiazz.sdwa5.org | docker-compose.projects.yml (profile: chimodiazz) |
| Minecraft (inactive) | :25565                      | docker-compose.yml (profile: minecraft) |

## Credentials

All secrets live in `.env` — never committed. See `.env.example` for required variable names.

## Outgoing email

Monitoring, Vaultwarden, the SdWa5 shop and the SdWa5 ERP send through the Google Workspace relay
without SMTP credentials. Monitoring, Vaultwarden and Shopware use STARTTLS on port 587. Dolibarr
uses implicit TLS on port 465 because its no-authentication path skips STARTTLS. See
[relay configuration and verification](docs/monitoring.md#outgoing-email-verification) and
[Dolibarr email settings](docs/dolibarr.md#outgoing-email).

## Documentation

`docs/` here holds the technical/ops documentation (*how* services run:
Docker, configs, operations). Org-level documentation (*what* they are used
for and *why*) lives in the parent repo's
[`docs/`](https://github.com/SdWa5/docs/tree/main/docs).

See `docs/` for per-service documentation:

- [Infrastructure overview](docs/infrastructure.md)
- [Shopware](docs/shopware/README.md)
- [Shopware plugins](docs/shopware/plugins.md)
- [Dolibarr](docs/dolibarr.md)
- [Vaultwarden](docs/vaultwarden.md)
- [Paperless-ngx (two instances)](docs/paperless.md)
- [Backup (Restic + rclone)](docs/backup.md)
- [Caddy](docs/caddy.md)
- [Ollama](docs/ollama.md)
- [Minecraft](docs/minecraft.md)
- [Chimo Diazz](docs/chimodiazz.md)
- [Maintenance (disk cleanup, log caps)](docs/maintenance.md)
- [Monitoring (health checks, alerts, Vaultwarden auto-update)](docs/monitoring.md)
- [SSH hardening (key-only access, fail2ban)](docs/ssh-hardening.md)

## Common operations

```bash
# Start all main services
docker compose up -d

# Start Project 2/Project 3 services
docker compose -f docker-compose.projects.yml up -d

# Start a profile-gated service (excluded from default up)
docker compose --profile minecraft up -d
docker compose --profile ollama up -d

# Restart a single service
docker compose restart shopware

# Follow logs
docker compose logs -f

# Reload Caddy config
systemctl reload caddy

# Health check on demand (see docs/monitoring.md)
/opt/docker/monitoring/vps-health.sh --dry-run

# Inspect the scheduled database backup configuration without connecting
/opt/docker/monitoring/database-backup.sh --dry-run

# Restore an SQL archive in an isolated temporary container
/opt/docker/monitoring/database-restore-check.sh dolibarr_db

# Security recheck from a workstation: exposure, firewall, isolation (see docs/monitoring.md)
monitoring/security-recheck.sh

# Show the SQL that recreates a schema's foreign keys under MariaDB 12.x (--apply runs it, see docs/backup.md)
/opt/docker/tools/mariadb/recreate-foreign-keys.sh dolibarr_db

# Set a stopped MariaDB service's root password back to the .env value (see docs/backup.md)
/opt/docker/tools/mariadb/reset-root-password.sh dolibarr_db

# Read the Dolibarr ERP from a workstation (see docs/dolibarr.md)
tools/dolibarr/doli.sh status

# Show what the project, task and ticket backlog would change in the ERP (--apply writes),
# including ticket renames by ref, closing and ticket dictionaries through the PmTools module
tools/dolibarr/sync-pm.sh

# Install or update a Dolibarr custom module at a tag, on the VPS as root (see docs/dolibarr.md)
tools/dolibarr/deploy-module.sh banksync https://github.com/SdWa5/banksync.git v1.0.0

# Enable, disable or report a Dolibarr module through Setup -> Modules, dev mirror by default (see docs/dolibarr.md)
tools/dolibarr/module-setup.sh status PmTools

# Set up the Dolibarr MCP server and its service user, on the dev mirror by default (see docs/dolibarr.md)
tools/dolibarr/mcp-setup.sh

# Rebuild the local Dolibarr dev mirror from the newest production archive, on a workstation (see docs/dolibarr.md)
tools/dolibarr/dev-instance.sh fetch && tools/dolibarr/dev-instance.sh restore

# Give the mirror's admin a local API key for sync-pm.sh and the REST API
tools/dolibarr/dev-instance.sh api-key

# Rebuild the local Shopware mirror from the live shop files and the newest archive, without egress
# (see docs/shopware/infrastructure.md)
tools/shopware/dev-instance.sh fetch && tools/shopware/dev-instance.sh restore
# Run Composer or bin/console on the mirror, for example to make the lock of a Shopware update
tools/shopware/dev-instance.sh composer audit --locked
tools/shopware/dev-instance.sh console plugin:list

# Preview the isolated Dolibarr migration rehearsal without changing anything.
bash tools/dolibarr/rehearse-upgrade.sh

# Show which merch products a data file would create in the shop (--apply writes, see docs/shopware/merch.md)
tools/shopware/create-products.sh tools/shopware/products/print-models.json
# Bring the images of existing products in line with the data file
tools/shopware/create-products.sh tools/shopware/products/print-models.json --sync-media

# Copy purchase prices into the production cost field the shop shows (--apply writes, see docs/shopware/merch.md)
tools/shopware/sync-production-cost.sh

# Replace text in CMS slots or mail templates from an edits file (--apply writes, see docs/shopware/content-cms.md)
tools/shopware/edit-slots.sh tools/shopware/slot-edits/hardware-m2122.json

# Correct confirmation/cancellation copy and preview both languages without sending mail
tools/shopware/edit-slots.sh tools/shopware/slot-edits/order-mail-copy.json
tools/shopware/check-order-mail.sh ORDER_ID

# Turn product photos into cutout, white, light and dark shop images (Docker)
tools/shopware/images/shop-images.sh run tools/shopware/images/print-models.jobs PHOTO_DIR OUT_DIR

# Slice STL models for the Kobra 3 Max and print grams, time and cost per piece (Docker)
tools/shopware/print-cost/print-cost.sh MODEL.stl...
```

The scripts reach Compose through `tools/compose.sh`, which prefers the v2 plugin `docker compose`
and falls back to `docker-compose` v1 where the plugin is missing. See
[docs/maintenance.md](docs/maintenance.md#compose-version).

## Monitoring

The cron jobs watch the box and mail every address in `MONITOR_MAIL_TO` when something is wrong.
It defaults to `ripper@sdwa5.org` alone, and any private address is configured in `.env` on the host
rather than committed here. A healthy system sends nothing. Vaultwarden updates itself daily, because
the Bitwarden clients auto-update and a server left behind stops working with them.

See [docs/monitoring.md](docs/monitoring.md).

The SQL backup job writes consistent ERP and Shopware archives daily at 03:40 Europe/Berlin. Restic
includes them in its later run. The health check alerts when a dump fails or an archive is missing,
corrupt or stale. See [docs/backup.md](docs/backup.md) for the isolated restore drill.

## Host access

SSH is key-only. `PasswordAuthentication no` and `PermitRootLogin prohibit-password`, applied
2026-09-07 after 13,672 failed root logins in 24 hours, with fail2ban behind it. The deployable
config lives in [`hardening/`](hardening/), together with the static IPv6 netplan file and the cloud-init
setting that keeps cloud-init away from it.

The Contabo console remains the fallback and is unaffected by any of it, because it goes through
getty and PAM rather than sshd. See [docs/ssh-hardening.md](docs/ssh-hardening.md).

## Tests

Production runs Debian 13 since 2026-10-15. The compose files pin Dolibarr 24.0.1, rolled out through
the [Dolibarr 24.0.1 upgrade](docs/maintenance.md#dolibarr-2401-upgrade) steps.
The inactive project definitions are updated without starting those services.

```bash
tests/run.sh
```

Runs the bats suite for the monitoring scripts and `tools/`, shellcheck, the PHP database-client
checks, the Python tool checks and the CI installer regression tests inside Docker. Test images use
exact tags and immutable digests. Nothing has to be installed on the host beyond Docker. See
[CI dependency maintenance](docs/maintenance.md#ci-dependencies) for the recorded versions and updates.

[`.github/workflows/tests.yml`](.github/workflows/tests.yml) runs the same script on every push, so
CI and a local run are the same thing, and adds a secret scan over the working tree and the full
history:

```bash
gitleaks dir . --redact --config .gitleaks.toml
gitleaks git . --redact --config .gitleaks.toml
```

The workflow grants `contents: read`, pins checkout to an upstream commit and does not retain
checkout credentials. The gitleaks 8.30.1 archive must match its committed SHA-256 before extraction
or installation. Regression tests reject corrupted archives and failed downloads before extraction,
preserve an existing installation on failure, and cover both flat and nested release archives.

The tree scan flags `minecraft-data/server.properties` when you run it on a deploy checkout. That is
correct and expected: the live file holds a generated `rcon.password`, which is exactly why it is not
tracked. CI never sees it, because an untracked file is not in the clone.

The storefront layout suite checks the rendered SdWa5Theme with Playwright inside Docker:

```bash
tests/storefront/run.sh                       # against https://sdwa5.org
SDWA5_STOREFRONT_URL=http://localhost:8090 tests/storefront/run.sh   # against the dev mirror
tests/storefront/run.sh --update-snapshots    # after an intended design change
```

It asserts that the header settings, the offcanvas settings and the offcanvas donate link share one
centre line, and that the homepage tiles end at their padding. It also compares two element
screenshots against the baselines in `tests/storefront/layout.spec.ts-snapshots/`, at three widths in
light and dark mode. It needs a running Shopware, so it is not part of `tests/run.sh` or CI. Run it
after a theme deploy, or against the mirror before one.

## Licence

Two licences, because this repository is part tooling and part writing.

- **MIT** ([LICENSE](LICENSE)) for the code and configuration: `monitoring/`, `hardening/`, `minecraft/`, `tools/`, `tests/`, `.github/`, `Caddyfile`,
  `docker-compose*.yml`, `.env.example` and the theme code in `shopware-html-data/custom/static-plugins/SdWa5Theme/`.
- **CC BY-SA 4.0** ([LICENSE-docs](LICENSE-docs)) for the prose and data: `docs/`, `README.md`, `CHANGELOG.md` and `TODO.md`.

Attribute as "Musikverein Schmeiß die Wand an 5 (SdWa5)" with a link to the repository. Share-alike applies to the prose, so a
derivative of the documentation stays under the same licence. The code carries no such condition.

**Not ours to license**: `minecraft-data/`, which is server and mod configuration produced by the image
and its mods, including 27 LuckPerms translation files. It carries its vendors' own terms. No third-party
Shopware plugin source is tracked since 2026-10-01, because every plugin installs through composer.

The theme carries two exceptions to the MIT grant. Its fonts DM Sans, Space Grotesk and JetBrains Mono are
under the SIL Open Font License 1.1, see the theme's `assets/fonts/LICENSE.md`. The SdWa5 logo in
`assets/logo/` is the association's mark and is not licensed at all.
