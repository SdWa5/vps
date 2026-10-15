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

## Image versions

Every image was on `:latest` until 2026-09-08, and only Vaultwarden was ever pulled. So `:latest`
delivered neither updates nor reproducibility, and the real hazard was a `docker compose pull` at some
future date crossing a major version under a live database. `mariadb:latest`, `lts`, `12` and `12.3`
all pointed at the same digest when measured, so `latest` was 12.3 and would have followed to 13 on
its own.

| Service | Tag | Why |
|---|---|---|
| `shopware` | `dockware/shopware:6.7.11.1` | Exact. dockware publishes no `6.7` series tag, so a pin here can only be exact. An update is a deliberate bump of the line |
| `dolibarr`, `dolibarr_cron` | `dolibarr/dolibarr:23.0.4` proposed; production 23.0.2 before maintenance | Exact. SQL restore drills passed on 2026-10-15. Application migration and rollback still require their own rehearsal before deployment |
| `dolibarr_db` and the project DBs | `mariadb:12.3` | Minor series. Patch updates inside 12.3 are safe and wanted; crossing a major version is the one-way door |
| `vaultwarden` | `vaultwarden/server:latest` | Deliberately unpinned. [`monitoring/vaultwarden-autoupdate.sh`](../monitoring/vaultwarden-autoupdate.sh) pulls it daily and verifies the result, and a pin would silently freeze security updates for a password vault. See [vaultwarden.md](vaultwarden.md) |
| `restic` | `creativeprojects/resticprofile:0.33.1-amd64` | Exact. Used only for the restic, rclone, crond and flock it ships; the schedule and the run are [`restic/`](../restic/). `latest` is rebuilt weekly and would move restic and rclone on its own. Until 2026-10-15 this was `lobaro/restic-backup-docker:latest`, frozen since 2021-05-05 at restic 0.12.0. A bump is followed by the [restore drill](backup.md#restore-drill) |
| `minecraft`, `ollama` | `:latest` | Profile-gated and not present on the host, so there is no running digest to pin to. For Minecraft the build is decided by the `VERSION` environment variable anyway |

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

This is an execution runbook, not a claim that either upgrade has been deployed. The production
baseline checked on 2026-10-15 was Debian 12.15, kernel 6.1.0-53-cloud-amd64, Dolibarr 23.0.2,
Docker CE 29.9.1 and Compose plugin 5.6.0. Caddy 2.11.7 already uses the upstream repository.
Recheck these facts and the public endpoints before the window. Keep the unrelated local TODO edits.

The proposed work takes ca. 5 hours 30 minutes. Allow ca. 15 minutes of ERP downtime and ca. 1 hour
of full-service maintenance. These estimates are not measurements. The user must approve a window
and have Contabo panel access. A Jira key is required before a branch or commit; the SEC labels
alone do not establish Jira tickets. Do not merge, push, delete branches or restore production
data without the applicable authorization.

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
is a separate change. Do not start project2, project3, Minecraft or Ollama.

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

The stock 23.0.4 image reproduced three SQL syntax errors near `--ip used to create record`.
The SQL parser removes inline comments only when whitespace follows `--`. The mounted
`tools/dolibarr/entrypoint.sh` normalizes only those three comments, then executes the official
entrypoint with its original command. It is idempotent and rejects changed definitions or another
Dolibarr version. Review/remove it when upgrading the image again. The rehearsal uses the same
wrapper as the proposed production definitions. Duplicate objects and already-completed DROP
operations accepted by upstream are classified separately; syntax errors remain a failed gate.

The gates require version 23.0.4 in the image and database, unchanged counts of users, third parties,
invoices and bank entries, successful migration output without SQL/PHP errors, and installation lock
mode 400. HTML output can be nonempty on success. An HTTP health check alone is insufficient.
The helper then makes a full dump with routines/events/triggers, invokes the existing isolated
restore check, and tests the old image against an empty schema restored from the original archive.
It removes disposable containers, network and data on exit. A mode-700 evidence directory under
`/var/tmp/sec05-evidence.*` retains the source archive, image IDs and private diagnostics. Treat it as
sensitive backup material and keep it outside Git. No production container is stopped or changed.

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

### Establish the host recovery checkpoint

Install the validated whole-host guard on the four public sites. Drain accepted requests and
scheduled business work. Record active/enabled/masked states of cron, APT jobs and the Compose boot
unit before changing them. Mask host cron and package-update timers/services for the window and
disable automatic Compose startup across reboot. Stop application-internal schedulers as well.
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
already stopped so its `down` cannot interrupt database shutdown. The user creates a Contabo
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
