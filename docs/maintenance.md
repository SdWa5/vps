# Maintenance

Operational runbooks for the SdWa5 VPS (Contabo, `/`= 99 GB).

Since 2026-09-01 an hourly health check mails when disk, containers, backups, public endpoints,
Caddy or the Vaultwarden version go wrong. See [monitoring.md](monitoring.md). The runbooks below are
what to do once that mail arrives.

Two incidents shaped them:

- **Disk full** — see [Disk cleanup](#disk-cleanup) below.
- **Clients broken while the web vault works** — a Vaultwarden version mismatch, not an outage. The
  runbook lives in [vaultwarden.md](vaultwarden.md#runbook-clients-broken-web-vault-fine).

## Disk cleanup

Runbook distilled from the **July 2026 incident** — root `/` hit **100 %** (99 GB used), services at risk.
Recovered to 28 % (~72 GB freed) with zero data loss.

### 1. Find the culprit — look before deleting

```bash
docker system df                                  # docker's own view (NOTE: "RECLAIMABLE" overstates — it counts shared layers)
df -h                                             # real disk usage
du -h --max-depth=1 / 2>/dev/null | sort -rh | head -20     # top-level fat dirs
```

Drill into whatever is biggest:

```bash
du -h --max-depth=2 /opt/docker 2>/dev/null | sort -rh | head -25
du -h --max-depth=1 /root 2>/dev/null | sort -rh | head
```

> `docker image prune -a` reported `0B` reclaimed despite `docker system df` claiming 22 GB — the images
> were all tied to running containers. Trust `du`/`df`, not the docker df "reclaimable" column.

### 2. What ate the disk (July 2026)

| Culprit | Size | Fix |
|---------|------|-----|
| `ollama-data/models/` | 22 GB | unused service — profile-gated + models purged (see [ollama.md](ollama.md)) |
| `/root/.cache` | 12 GB | regenerable cache — `rm -rf /root/.cache/*` |
| `minecraft-data/backup/world/` | 11 GB | old `textile_backup` archives left because the (inactive) server never ran to prune them (see [minecraft.md](minecraft.md)) |
| systemd journal + apt cache + dangling images | ~5 GB | commands below |

### 3. Zero-risk quick wins

```bash
rm -rf /root/.cache/*                 # regenerable; refills slowly, re-nuke anytime
journalctl --vacuum-size=200M         # trim systemd journal
apt-get clean                         # nuke apt package cache
docker image prune -a                 # remove images not used by any container
```

### 4. Volumes — handle with care

`docker system prune --volumes` and `rm` on bind-mount dirs under `/opt/docker/*-data/` delete **live app
data** (databases, uploads). Never blanket-prune volumes here. All persistent state lives in bind mounts
under `/opt/docker/`, which Restic backs up daily — but restore is slower than not deleting.

## Docker packages

Docker comes from Docker's own apt repository since 2026-10-15, not from Debian. Debian 12's docker.io
20.10.24 carried runc 1.1.5 and containerd 1.6.20, both behind the 2024 and 2025 container escape
fixes, and Debian 13 would still ship runc 1.1.15.

| Package | Version on 2026-10-15 |
|---|---|
| `docker-ce`, `docker-ce-cli` | 29.9.1 |
| `containerd.io` | 2.4.2, bundles runc 1.5.2 |
| `docker-compose-plugin` | 5.6.0 |

The key is `/etc/apt/keyrings/docker.asc` (fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF
CD88`) and the source is `/etc/apt/sources.list.d/docker.list`. The host has no gpg, so the key is
stored armored. It was installed with `--no-install-recommends`, which leaves out buildx and the
rootless extras, because nothing here builds images. `nftables` came in as a hard dependency, and its
service stays disabled, because `/etc/nftables.conf` would flush the firewall at boot.

unattended-upgrades never reboots (`Automatic-Reboot` stays at Debian's default `false`), decided on
2026-10-17 (SEC-D02). A fix that needs a reboot runs only after a manual one, and the `reboot` check of
[vps-health.sh](monitoring.md) warns while one is pending.

The first such reboot ran on 2026-10-17 at 23:35 for linux 6.12.113 (DSA-6568-1), which unattended-upgrades
had installed at 06:59. SSH answered again after ca. 40 seconds. All 13 containers came back, and the static
IPv6 address and route from `hardening/netplan/60-ipv6.yaml` survived their first boot. `security-recheck.sh
--restore` reported the same 67 OK before and after. A manual reboot is therefore a short window with a
recheck on both sides:

```bash
monitoring/security-recheck.sh --restore   # from a client with IPv6, before and after
ssh sdwa5.org systemctl reboot
```

unattended-upgrades covers only Debian origins, so Docker updates are manual. That is deliberate, because
every daemon restart stops and restarts every container. Update in a quiet hour:

```bash
apt-get update && apt-get install --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin
docker info --format '{{.ServerVersion}} {{.Driver}}'   # expect overlay2, the store the images live in
systemctl restart sdwa5-firewall                         # Docker rebuilds its chains on start
```

The switch from docker.io took ca. 2 minutes of downtime on 2026-10-15. Both compose files went down
first, then the packages were swapped, then the stack came back under Compose v2. overlay2 and every
image survived the upgrade, and the containers were recreated because v2 labels them differently.

`docker-compose.service` has `Requires=docker.service`. Stopping or upgrading Docker therefore stops
the unit too, and its `ExecStop` runs `down` on the main stack, which removes those containers and
networks. They come back with `systemctl start docker-compose.service`. docker-compose.projects.yml is
not part of the unit and needs its own `up`.

## Compose version

The host runs Compose v2, the `docker compose` plugin, and the commands in these docs are written for
it. Debian's docker-compose v1 1.29.2 was removed on 2026-10-15, together with its Python dependencies
and docker.io's leftovers (criu, tini). **Do not reinstall it.** v1 and v2 label containers
differently, so every `up` from the other version recreates every container.

[`tools/compose.sh`](../tools/compose.sh) sets `DOCKER_COMPOSE` to `docker compose` where the plugin
exists and to `docker-compose` otherwise, and `monitoring/lib.sh`, `tools/mariadb/reset-root-password.sh`
and the boot unit use it. A `DOCKER_COMPOSE` set in the environment wins.

The boot unit is [`hardening/systemd/docker-compose.service`](../hardening/systemd/docker-compose.service).
It runs `up -d` for `docker-compose.yml` at boot and `down` at shutdown. Install it without starting it,
because a restart of the unit runs `down` and then `up` on the live stack:

```bash
install -m 644 -o root -g root /opt/docker/hardening/systemd/docker-compose.service /etc/systemd/system/
systemctl daemon-reload
```

Compose v5.6.0 was checked against both compose files on 2026-10-15. It renders the same project,
container and network names and the same environment, ports, mounts and networks per service, and it
warns only about the obsolete `version:` key.

## Log growth prevention

Container logs are capped in `docker-compose.yml` via the `x-logging` anchor (json-file, `max-size: 10m`,
`max-file: 3`) applied to every service as `logging: *default-logging`. This is VCS-tracked in preference to
host `/etc/docker/daemon.json` so it deploys with the stack.

Log opts apply on container (re)creation, not to running containers:

```bash
cd /opt/docker
docker compose up -d                                              # recreates changed services
docker inspect --format '{{.HostConfig.LogConfig}}' shopware      # expect: {json-file map[max-file:3 max-size:10m]}
```

`docker-compose.projects.yml` carries **its own copy** of the `x-logging` anchor rather than
referencing the one in `docker-compose.yml`, because YAML anchors do not cross files. Both blocks must
be kept in step. To change the cap, edit both and recreate.

## CI dependencies

`tests/run.sh` uses exact version tags paired with immutable multi-platform image-index digests.
The 2026-10-15 pins preserve these already-cached runtimes, measured with their version commands.
Their digests were also verified as available from the upstream registries. The tags label the
measured runtime versions. Docker selects the immutable digest when a tag points at a rebuilt image.

| Test image | Measured runtime |
|---|---|
| `bats/bats:1.14.0` | Bats 1.14.0 |
| `koalaman/shellcheck:v0.11.0` | ShellCheck 0.11.0 |
| `php:8.2.33-cli` | PHP 8.2.33 |
| `python:3.12.15-slim` | Python 3.12.15 |
| `mcr.microsoft.com/playwright:v1.63.0-noble` | Playwright 1.63.0, in `tests/storefront/run.sh` |

The Playwright image tag must match `@playwright/test` in `tests/storefront/package.json`, because the
browsers come with the image. Update both together and regenerate `package-lock.json` in the image.

Review an image update, resolve its index digest with `docker buildx imagetools inspect`, verify the
runtime and update its tag and digest together in `tests/run.sh`. Run `tests/run.sh` and verify the
GitHub workflow for the resulting commit. Package installation still resolves repository metadata
at run time, including the bats container's Alpine packages and the Python test dependencies.

The workflow pins checkout to an upstream commit, explicitly grants read-only contents access and
does not persist checkout credentials. It installs gitleaks 8.30.1 through
`.github/scripts/install-ci-tool.sh`, which checks its committed SHA-256 before extracting or
installing the archive member. A tool update requires reviewing the release and updating its version
and checksum together. The normal test entry point includes the installer's regression suite.

## Image versions

Every image was on `:latest` until 2026-09-08, and only Vaultwarden was ever pulled. So `:latest`
delivered neither updates nor reproducibility, and the real hazard was a `docker compose pull` at some
future date crossing a major version under a live database. `mariadb:latest`, `lts`, `12` and `12.3`
all pointed at the same digest when measured, so `latest` was 12.3 and would have followed to 13 on
its own.

| Service | Tag | Why |
|---|---|---|
| `shopware` | `dockware/shopware:6.7.15.1@sha256:1a4018ce…` | Exact, by tag and digest, because dockware rebuilds existing tags (6.7.15.1 was built on 2026-10-12). The `6.7-latest` series tag exists but rolls across minors, whose migrations run forward only. An update is a deliberate bump of the line after a rehearsal, see [Updating Shopware](shopware/infrastructure.md#updating-shopware). Chimo Diazz stays on 6.7.11.1 in `docker-compose.projects.yml` |
| `dolibarr`, `dolibarr_cron` | `dolibarr/dolibarr:24.0.2` | Exact. The isolated rehearsal takes its target from this pin, so a Dolibarr update starts by bumping it, see [Dolibarr 24.0.1 upgrade](#dolibarr-2401-upgrade) |
| `dolibarr_db` and the project DBs | `mariadb:12.3` | Minor series. Patch updates inside 12.3 are safe and wanted; crossing a major version is the one-way door |
| `paperless_sdwa5`, `paperless_home` | `ghcr.io/paperless-ngx/paperless-ngx:3.3.2@sha256:d232cba3…` | Exact, by tag and digest, the same pin on both services, which a test keeps equal. 3.3.2 of 2026-10-16 fixes GHSA-c8f3-pqr2-rr24. A minor runs forward-only migrations, so a bump goes through the dev mirror first, see [paperless.md](paperless.md#updates) |
| `paperless_*_db` | `mariadb:12.3` | Same series as `dolibarr_db` |
| `paperless_*_broker` | `valkey/valkey:9.1-alpine` | Minor series. A queue without a volume, so nothing persists across an update. 9.0 to 9.1 on 2026-10-18 through Dependabot; 9.2-alpine was only 9.2.0-rc1 then |
| `vaultwarden` | `vaultwarden/server:latest` | Deliberately unpinned. [`monitoring/vaultwarden-autoupdate.sh`](../monitoring/vaultwarden-autoupdate.sh) pulls it daily and verifies the result, and a pin would silently freeze security updates for a password vault. See [vaultwarden.md](vaultwarden.md) |
| `restic` | `creativeprojects/resticprofile:0.33.1-amd64` | Exact. Used only for the restic, rclone, crond and flock it ships; the schedule and the run are [`restic/`](../restic/). `latest` is rebuilt weekly and would move restic and rclone on its own. Until 2026-10-15 this was `lobaro/restic-backup-docker:latest`, frozen since 2021-05-05 at restic 0.12.0. A bump is followed by the [restore drill](backup.md#restore-drill) |
| `minecraft`, `ollama` | `:latest` | Profile-gated and not present on the host, so there is no running digest to pin to. For Minecraft the build is decided by the `VERSION` environment variable anyway |

### Update proposals

Dependabot checks the pins weekly, configured in
[`.github/dependabot.yml`](../.github/dependabot.yml) since 2026-10-18. It covers the compose files'
images and the workflow's actions, and it opens at most three image pull requests and two action pull
requests at a time. A MariaDB major version is never proposed, because it upgrades the data files in
place. The `:latest` services have no version to compare and are skipped. The test images in
`tests/run.sh` are not covered and stay with [CI dependencies](#ci-dependencies).

**No image is shared through a YAML anchor.** Dependabot's compose updater finds the image right after
`image:` in the raw text, so `image: &name valkey/valkey:9.0-alpine` makes it raise "Expected content to
change!" and fails the whole run. That is what failed the first two runs on 2026-10-18, read in
dependabot-core's `build_old_declaration_regex`, since a newer valkey tag existed. The Paperless and broker
images are therefore written out on both services, and `tests/dependabot.bats` keeps each pair equal.

**A new release is proposed three days after it was pushed.** dependabot-core applies a three-day
cooldown when `dependabot.yml` configures none, since 2026-07-30 (`DEFAULT_COOLDOWN_DAYS` in
`updater/lib/dependabot/job.rb`). Dolibarr 24.0.2, pushed on 2026-10-17, was therefore skipped on
2026-10-18, measured with the Dependabot CLI v1.96.0 against this repository (`Skipping tag 24.0.2 due
to cooldown period`). The default stays, because it keeps an image that turns out broken or compromised
in its first days out of the proposals.

**A merged proposal deploys nothing**, because production pulls by hand. A Shopware or Dolibarr pull
request is a signal that a version exists. It goes through
[Updating Shopware](shopware/infrastructure.md#updating-shopware) or the Dolibarr rehearsal, never
through a plain merge, and the rehearsal's commit replaces the proposal. Dependabot pushes its branches
to this repository, so the workflow's `push` trigger runs the tests on them with a read-only token.

**Pinning is not a no-op on the next `up -d`, and changing the image *reference* is enough to recreate
a container even when the image content is identical.** That caught us on 2026-09-08: the host's
images were tagged `:latest` locally, so `dockware/shopware:6.7.11.1` was not present under its
pinned name and `up -d` would have pulled and recreated Shopware and both Dolibarr services for no
gain.

The fix was to give the already-running images their pinned names on the host, which is accurate
because that image *is* 6.7.11.1:

```bash
docker tag "$(docker inspect -f '{{.Image}}' shopware)" dockware/shopware:6.7.11.1
docker tag "$(docker inspect -f '{{.Image}}' dolibarr)" dolibarr/dolibarr:23.0.2
```

`mariadb:12.3` was deliberately **not** tagged that way. It resolves to a newer digest than the one
running, so the next `up -d` recreates `dolibarr_db` and upgrades MariaDB within 12.3. That is
routine at patch level, and leaving it as a real step keeps it deliberate rather than hidden.

So after this change `up -d` recreates `dolibarr_db` alone. Check before running it:

```bash
cd /opt/docker
for s in shopware dolibarr dolibarr_cron dolibarr_db; do
  cfg=$(docker compose config | awk -v svc="  $s:" '$0==svc{f=1} f&&/image:/{print $2; exit}')
  run=$(docker inspect -f '{{.Image}}' "$s")
  want=$(docker image inspect -f '{{.Id}}' "$cfg" 2>/dev/null || echo not-local)
  echo "$s: $cfg recreate=$([ "$run" = "$want" ] && echo no || echo YES)"
done
```

Updating a pinned service:

```bash
cd /opt/docker
# 1. Check what the new tag would be, and read that project's release notes.
# 2. Edit the image line in docker-compose.yml.
# 3. Back up first. Dolibarr and Shopware both migrate forward-only.
docker compose pull dolibarr dolibarr_cron
# For Dolibarr, follow the maintenance procedure below before starting either service.
docker compose logs --tail=50 dolibarr
```

## SEC-05 and SEC-25 maintenance window

Executed on 2026-10-15 between 17:24 and 19:30. Production now runs Debian 13.7 with kernel
6.12.111+deb13-cloud-amd64 and Dolibarr 23.0.4. The ERP was down ca. 10 minutes, all public sites
ca. 1 hour 10 minutes. Every gate below passed, and the corrections the execution forced are written
into the steps. The baseline before the window was Debian 12.15, kernel 6.1.0-53-cloud-amd64,
Dolibarr 23.0.2, Docker CE 29.9.1 and Compose plugin 5.6.0. Caddy 2.11.7 already used the upstream
repository and was not touched.

Repeat it for the next major upgrade with these timings in mind. `apt full-upgrade` took ca. 25
minutes, most of it regenerating all 509 locales enabled in `/etc/locale.gen`. The first boot of
Debian 13 took 5 minutes because of the stale `cloud-init` LSB script described below.

### Preparation evidence on 2026-10-15

The isolated rehearsal passed with the version-specific comment normalization described below.
The image and database reported 23.0.4, all four business-record counts matched, installation lock
mode was 400, and external TCP egress was blocked. A fresh full dump imported and passed all table
checks in a separate database. Restoring the original archive into an empty schema and starting
the exact old image also passed. All seven production image IDs remained unchanged.

The pulled target manifest is
`sha256:89283ec0b936f7abbfe6eb881d155a8530a0d7431cb6e4a48d83f37ece36ccb7`.
Both temporary Caddy candidates validated without activation. The isolated Trixie APT simulation
proposed 428 package installations/upgrades and 25 removals. Twenty-four removed libraries have
their corresponding t64 replacements; the remaining removal is `insserv`. Caddy stays unchanged,
Docker CE/containerd/Compose retain their upstream versions with Trixie package suffixes, and no
Debian Docker packages replace them. Active APT sources and installed packages were not changed.
Refresh the simulation and review any changed result immediately before the actual upgrade.

### Prepare and rehearse

Pull only `dolibarr/dolibarr:23.0.4`. Record its digest and every running container's image ID.
Retain the old ERP and database images. Do not prune images or pull other floating tags. Before a
whole-stack recreation, compare cached image IDs to the running baseline. A database patch upgrade
is a separate change. Do not start Minecraft or Ollama.

```bash
cd /opt/docker
docker pull dolibarr/dolibarr:23.0.4
DATABASE_BACKUP_CONTAINERS=dolibarr_db monitoring/database-backup.sh
bash tools/dolibarr/rehearse-upgrade.sh                       # preview only
bash tools/dolibarr/rehearse-upgrade.sh --apply database-backup/dolibarr_db.tar.gz
```

The applied rehearsal runs as root. It verifies the archive's database image against the running
database, copies documents and custom modules, and imports the archive into an isolated database.
The internal Docker network has no external egress. HTTP checks use the container's loopback through
`docker exec`; no host port is published and no production credential mount is supplied. Native
database events and the application cron stay off. Docker CE 29 discarded the published-port
mapping on an internal network during the first rehearsal probe, so host-port readiness is not used.
Scratch credentials travel through private files, not process arguments or terminal output.

The stock 23.0.4 image reproduced three SQL syntax errors near `--ip used to create record`,
because the SQL parser removes inline comments only when whitespace follows `--`. A mounted wrapper,
`tools/dolibarr/entrypoint.sh`, normalized those three comments until 24.0.1. The 24.0.1 image ships
all three with the whitespace, checked on 2026-10-16, so the wrapper and its mount were removed and
both the production services and the rehearsal start the image's own entrypoint. Duplicate objects and already-completed DROP
operations accepted by upstream are classified separately; syntax errors remain a failed gate.

The gates require version 23.0.4 in the image and database, unchanged counts of users, third parties,
invoices and bank entries, successful migration output without SQL/PHP errors, and installation lock
mode 400. HTML output can be nonempty on success. An HTTP health check alone is insufficient.
The helper then makes a full dump with routines/events/triggers, invokes the existing isolated
restore check, and tests the old image against an empty schema restored from the original archive.
It removes disposable containers, network and data on exit. A mode-700 evidence directory under
`/var/tmp/sec05-evidence.*` retains the source archive, image IDs and private diagnostics. Treat it as
sensitive backup material and keep it outside Git. Once the upgrade it prepared has passed its gates,
put the directory into an archive snapshot and delete it, see [backup.md](backup.md#archive-snapshots).
No production container is stopped or changed.

Prepare ERP-only and whole-host maintenance Caddy candidates from the current live configuration.
Return HTTP 503 with `Retry-After` to ordinary clients. Permit loopback and a verified operator
address through `remote_ip`, never a forwarded-header bypass. Keep all existing security blocks,
headers and shop `header_up Host {host}` settings. Validate the candidates before installation.
Preserve a private original and its checksum so the temporary guard can be removed exactly.

### Apply the ERP patch

After the user approves the window, install the validated ERP-only guard, then drain requests and
stop both old application containers. The database stays running.

```bash
cd /opt/docker
docker compose stop --timeout 120 dolibarr_cron dolibarr
DATABASE_BACKUP_CONTAINERS=dolibarr_db monitoring/database-backup.sh
monitoring/database-restore-check.sh dolibarr_db
```

Preserve the resulting archive under a distinct mode-600 filename in the root-only preparation
directory. Also preserve documents, custom modules and their ownership. The rolling archive alone
is insufficient because the next backup replaces it. Record original cron-job activation states.

Deploy only the reviewed Compose changes. Remove the real installation lock only after both old
application containers have stopped, then start the web service without recreating its database.

```bash
rm /opt/docker/dolibarr-documents-data/install.lock
docker compose up -d --no-deps dolibarr
```

Repeat the independent rehearsal gates. Require image and database version 23.0.4, consistent
business counts, a locked installer and clean migration output. Take another full dump and restore
it successfully. A new foreign-key problem is a failed gate, not permission for an automatic repair.
The user verifies admin login and BankSync access. Verify the read-only REST API and API-explorer
404, then start `dolibarr_cron` with `--no-deps`. Observe ordinary scheduled-runner authentication
and preserve job activation states. Do not force a financial import. The user performs the SMTP
test and confirms mailbox receipt. Keep implicit TLS on port 465 unless separately validated.

ERP rollback requires user authorization. Stop both application services, restore the application
schema from the preserved archive into an empty schema, restore documents/custom modules and their
ownership, and start both services with the preserved 23.0.2 image. Use the exact sequence proven
in rehearsal. Never rely on the entrypoint's automatic-restore message or downgrade the image alone.

## Dolibarr 24.0.1 upgrade

24.0.1 is the first release with the core MCP server. It reuses the two sections above with these
differences. Pull and gate on `dolibarr/dolibarr:24.0.1` instead of 23.0.4, and the rollback image is
23.0.4. The rehearsal requires the copied database to report the `DOLI_VERSION` of the running
image, so it follows whatever production runs. The ERP-only Caddy guard may be skipped, because the ERP has a single operator. The dev mirror
from [docs/dolibarr.md](dolibarr.md) migrated the full production dump from 23.0.4 to 24.0.1 on
2026-10-16, and BankSync v1.2.0 rendered all its pages there without PHP errors.

Executed on 2026-10-16 between 02:26 and 02:40. The ERP was down ca. 3 minutes. The isolated
rehearsal passed every gate first. Production then reported image, environment and database version
24.0.1, unchanged counts of users, third parties, invoices and bank entries, installation lock mode
400 and only upstream-accepted duplicate-object results in the migration output. A fresh dump
passed the restore check, the API explorer returned 404, the admin login and all nine BankSync pages
rendered without PHP errors, and an SMTP test mail was accepted. `dolibarr_cron` started last and
its first run authenticated and completed. The upgrade made module `ai` active. The preserved
archive, documents, custom modules and the 23.0.4 image ID were kept in a root-only
`/var/tmp/dolibarr-24-preserve.*` directory for the rollback. SEC-11 moved that directory on 2026-10-16
into the archive snapshot `bc1b03d1` and deleted it from the host, see
[backup.md](backup.md#archive-snapshots).

The 24.0.1 image writes a full database dump to `documents/backup-before-upgrade.sql` with mode 644.
Set it to 600 right after the upgrade. Once the upgrade has passed its gates, put it into an archive
snapshot and delete it, because it sits in the live documents volume and the daily backups carry it
along with every user's password hash.

24.0.2 repeats these steps. It fixes missing access checks in the REST API (upstream #40522 to #40526:
category link and unlink, contract, supplier invoice, BOM and intervention lines, invoice from
contract). Since 1.93.0 `rehearse-upgrade.sh` reads its target from the `dolibarr` service's pin in
`docker-compose.yml`, so bumping both pins is the whole preparation, and `DOLIBARR_TARGET_IMAGE` names
another image for a trial. The rollback image is 24.0.1, and the preserve directory is
`/var/tmp/dolibarr-24.0.2-preserve.*`. Its migration alters `llx_quickmemo_memo`, the table of the
disabled core module Quick memo, which this instance does not have, so the gate accepts
`DB_ERROR_NOSUCHTABLE` after an `ALTER TABLE` and nowhere else. On the dev mirror on 2026-10-18 the copy
of the 03:39 archive migrated in 75 s and passed that gate, all nine BankSync v1.2.0 pages rendered
without PHP messages, the PmTools v1.0.0 dictionary route answered, and the MCP server listed 43 tools
including the ten `pm_*` ones.

The production upgrade passed on 2026-10-18. The ERP was unavailable from 04:56:31 to 04:59:15
Europe/Berlin. Both services run 24.0.2; the migration, business-count, install-lock, REST and backup
restore gates passed. The admin login and all nine BankSync pages subsequently returned HTTP 200
without PHP errors. The user confirmed receipt of the SMTP test sent at 14:03, completing the
email acceptance check. The cron key was rotated in 1.94.0 after transcript exposure, and the
13:15 cron run authenticated. Since 1.94.1 Caddy returns 404 for the public cron path; scheduled jobs
continue through `dolibarr_cron` on the command line.

### Establish the host recovery checkpoint

Install the validated whole-host guard on the four public sites. Drain accepted requests and
scheduled business work. Record active/enabled/masked states of cron, APT jobs and the Compose boot
unit before changing them. **Do not mask `cron.service`.** `/etc/cron.d/staticroute` adds the eth0
link route `@reboot`, so a masked cron boots the upgraded host without it. Move the business jobs
out of `/etc/cron.d` into a root-only holding directory instead (`chimodiazz-*`, `database-backup`,
`shopware-worker`, `vaultwarden-*`, `vps-health`) and keep `staticroute` and `e2scrub_all`. Mask the
package-update timers/services for the window and disable automatic Compose startup across reboot. Stop application-internal schedulers as well.
These restrictions must survive reboot, and their original state must be recoverable from the
checkpoint. Keep Caddy available for the maintenance response and controlled operator probes.

Create fresh complete dumps of all three SQL databases and the consistent Vaultwarden copy. Run
all SQL restore checks and the documented Vaultwarden restore drill, then run restic and verify its
new snapshot. Protect distinct pre-window archives against scheduled replacement. The backup job
can exit successfully when another run holds its lock, so verify the archive timestamps too.

```bash
/opt/docker/monitoring/database-backup.sh
/opt/docker/monitoring/vaultwarden-db-backup.sh
/opt/docker/monitoring/database-restore-check.sh dolibarr_db
/opt/docker/monitoring/database-restore-check.sh shopware
/opt/docker/monitoring/database-restore-check.sh chimodiazz_shopware
docker exec restic /bin/sh /opt/restic/backup.sh
docker exec restic restic snapshots
```

Cleanly stop the active applications and databases with sufficient shutdown time. Confirm clean
database shutdowns before taking the host snapshot. Stop the boot unit after the containers are
already stopped so its `down` cannot interrupt database shutdown. That `down` removes the main
stack's containers and networks; the data survives because every database is a bind mount.

The dockware images ignore SIGTERM, so `docker stop` kills their internal MySQL after the timeout
(exit 137) and leaves an unclean InnoDB. `service mysql stop` inside the container failed as well.
What worked: find `mysqld` with `docker top <container> -eo pid,comm`, wait for a "ready for
connections" line from the current start, send `kill -TERM <pid>` from the host, wait until the PID is
gone and confirm "Shutdown complete" in `/var/log/mysql/error.log`, then stop the container. The user creates a Contabo
snapshot and verifies that it is ready and can be restored. Do not proceed without this gate.
This checkpoint includes Dolibarr 23.0.4 and the maintenance restrictions.

Keep VNC off by default. Contabo's rescue environment provides SSH independently of the installed
OS. Have the panel recovery instructions available before starting. Enable VNC if console access
is actually needed. Its disable toggle hard-reset this VM on 2026-10-15; stop databases and power
off cleanly before any such toggle. The user enters panel, rescue and console credentials directly.

### Upgrade Debian

Use `screen` and a second independent SSH connection with `ssh -S none`. Save package inventory,
APT sources, network/route settings, SSH configuration, GRUB configuration and firewall baselines
in the root-only preparation directory. Record all command output privately without printing
credentials or full container environments.

1. Finish Bookworm point updates. Add `/etc/cloud/cloud-init.disabled` before the upgraded boot.
   Preserve the existing static netplan configuration, route and SSH hardening.
2. Remove `bookworm-backports` from the upgrade sources. Switch the remaining Debian suites and
   Docker's source to Trixie. Leave Caddy's upstream source unchanged. Keep backports disabled.
3. Review APT simulations. Reject unexpected removals, replacement of Docker CE with `docker.io`,
   and unrelated Caddy/Docker version changes. Then run the minimal upgrade followed by full upgrade.
   Preserve modified conffiles with `--force-confdef --force-confold` and `UCF_FORCE_CONFFOLD=1`.
4. Require a clean `dpkg --audit`, successful `sshd -t`, fresh key-based SSH login, the cloud-kernel
   package and generated GRUB entry. Check `udevadm test-builtin net_setup_link /sys/class/net/eth0`,
   fail2ban's SSH filter and `linux-sysctl-defaults`. Keep `nftables.service` disabled.
5. Reboot. Verify Debian 13, its cloud kernel, IPv4/IPv6 and the static route, fresh SSH access,
   boot logs, SSH effective settings and Caddy validation before application startup.
6. Two leftovers broke on the first Debian 13 boot. `/etc/cron.d/staticroute` had CRLF line endings
   that cron 3.0pl1-197 rejects with "bad minute"; convert it with `sed -i 's/\r$//'`. The old
   Bookworm `/etc/init.d/cloud-init`, an unmodified obsolete conffile, became a generated LSB unit
   that hung for 5 minutes; move it out of `/etc/init.d` and `systemctl daemon-reload`. A third one went
   unnoticed until 2026-10-16: cloud-init still ran and rewrote the netplan file without the static IPv6
   address. Deploy `hardening/netplan/60-ipv6.yaml` and `hardening/cloud-init/` before the reboot, and
   check `ip -6 addr show dev eth0 scope global` after it.
7. fail2ban 1.1 defaults to the nftables banaction on Debian 13. Deploy `hardening/fail2ban/jail.local`,
   which pins `iptables-multiport`, before judging the firewall check.

Use `apt upgrade --without-new-pkgs` followed by `apt full-upgrade` after the reviewed source changes.
Do not change sources and execute a blind noninteractive full upgrade in one unattended command.
Docker packages remain from download.docker.com. Keep password and keyboard-interactive SSH
authentication disabled; retain the existing root key-only policy.

### Restore services and accept

Start only the active application services with their captured image versions while public access
and business schedulers remain restricted. Docker restart stops `docker-compose.service` because
that unit requires Docker and its `ExecStop` runs `down`. Restoring the Docker daemon alone does not
restore the whole stack. Start Chimo explicitly through its own Compose file and profile.
Reapply `sdwa5-firewall` after the networks exist and verify the fail2ban jump afterwards.

Before allowing new writes, verify both shops with their correct Host headers, shop administration
and health endpoints, Vaultwarden `/api/config`, ERP login/API and all SEC-04 denial probes. Repeat
the SEC-03 isolation matrix. Verify Caddy, certificates/HTTP3, INPUT/DOCKER-USER rules, cloud-init
state, unit states and the independent SSH login. Compare results to the pre-window baseline.
`monitoring/security-recheck.sh --restore` from a workstation covers the denial probes, the isolation
matrix, HTTP/3, the firewall chains and the restore checks in one run, see
[monitoring.md](monitoring.md#security-recheck).

If a production gate fails, stop, preserve evidence and request the prepared rollback. Snapshot
restoration returns Debian 12 with Dolibarr 23.0.4; restore the recorded scheduler and boot-unit
states deliberately because the checkpoint contains maintenance restrictions. Once public writes
or scheduled business work resume, snapshot restoration additionally needs explicit approval of
the resulting data loss. Do not silently repair unrelated production issues.

After the pre-resume gates pass, restore original cron/APT/boot-unit states, start the ERP cron and
restic services, and remove the temporary Caddy guard. Verify all seven running containers, health
checks where defined, ordinary scheduled work, fresh backups and `vps-health.sh --dry-run`.
Keep rollback material until these checks pass. Defer autoremove and image pruning. Update the
running-version documentation and close the SEC backlog entries only with actual acceptance
evidence. No memory update is implicit in this procedure.
