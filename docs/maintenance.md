# Maintenance

Operational runbooks for the SdWa5 VPS (Contabo, `/`= 99 GB).

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
docker compose up -d                                              # recreates changed services
docker inspect --format '{{.HostConfig.LogConfig}}' shopware      # expect: {json-file map[max-file:3 max-size:10m]}
```

To change the cap, edit the single `x-logging` block at the top of `docker-compose.yml` and recreate.
