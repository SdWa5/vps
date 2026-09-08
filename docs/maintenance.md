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

## Log growth prevention

Container logs are capped in `docker-compose.yml` via the `x-logging` anchor (json-file, `max-size: 10m`,
`max-file: 3`) applied to every service as `logging: *default-logging`. This is VCS-tracked in preference to
host `/etc/docker/daemon.json` so it deploys with the stack.

Log opts apply on container (re)creation, not to running containers:

```bash
cd /opt/docker
docker-compose up -d                                              # recreates changed services
docker inspect --format '{{.HostConfig.LogConfig}}' shopware      # expect: {json-file map[max-file:3 max-size:10m]}
```

`docker-compose.projects.yml` carries **its own copy** of the `x-logging` anchor rather than
referencing the one in `docker-compose.yml`, because YAML anchors do not cross files. Both blocks must
be kept in step. To change the cap, edit both and recreate.

## Image versions

Every image was on `:latest` until 2026-09-08, and only Vaultwarden was ever pulled. So `:latest`
delivered neither updates nor reproducibility, and the real hazard was a `docker-compose pull` at some
future date crossing a major version under a live database. `mariadb:latest`, `lts`, `12` and `12.3`
all pointed at the same digest when measured, so `latest` was 12.3 and would have followed to 13 on
its own.

| Service | Tag | Why |
|---|---|---|
| `shopware` | `dockware/shopware:6.7.11.1` | Exact. dockware publishes no `6.7` series tag, so a pin here can only be exact. An update is a deliberate bump of the line |
| `dolibarr`, `dolibarr_cron` | `dolibarr/dolibarr:23.0.2` | Exact. A Dolibarr minor upgrade runs forward-only database migrations, and no restore drill has been done yet. The `23` tag exists and would let 23.x move on its own, which is why it is not used |
| `dolibarr_db` and the project DBs | `mariadb:12.3` | Minor series. Patch updates inside 12.3 are safe and wanted; crossing a major version is the one-way door |
| `vaultwarden` | `vaultwarden/server:latest` | Deliberately unpinned. [`monitoring/vaultwarden-autoupdate.sh`](../monitoring/vaultwarden-autoupdate.sh) pulls it weekly and verifies the result, and a pin would silently freeze security updates for a password vault. See [vaultwarden.md](vaultwarden.md) |
| `restic` | `lobaro/restic-backup-docker:latest` | Nothing to pin to. The repository publishes six tags, the newest version tag is `1.3.1-0.9.6` from 2020, and `latest` has not been pushed since 2021-05-05, so it is frozen in practice |
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
  cfg=$(docker-compose config | awk -v svc="  $s:" '$0==svc{f=1} f&&/image:/{print $2; exit}')
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
docker-compose pull dolibarr
docker-compose up -d dolibarr
docker-compose logs --tail=50 dolibarr
```
