# Monitoring

Three cron jobs, no dashboard, no extra container, no external monitoring service.
All live in [`monitoring/`](../monitoring/) and are deployed to `/opt/docker/monitoring/`.

| Job | Script | Schedule | Sends mail when |
|-----|--------|----------|-----------------|
| Health check | `vps-health.sh` | hourly, `:17` | something is wrong or has just recovered |
| Vaultwarden database copy | `vaultwarden-db-backup.sh` | daily 03:50 | the dump failed or could not be verified |
| Vaultwarden update | `vaultwarden-autoupdate.sh` | Sunday 03:00 | an update was applied, an update failed, or the health check stopped running |

**A healthy system sends nothing.** There is no all-green digest.

## Why this exists

Two incidents, both silent until they became visible as an outage.

- **July 2026** — root `/` filled to 100 %. Nothing was watching disk usage. See
  [maintenance.md](maintenance.md).
- **September 2026** — Vaultwarden sat at 1.36.0 while the Bitwarden clients auto-updated past it.
  The browser extension and the mobile app stopped working, the web vault kept going because it
  ships with the server. See [vaultwarden.md](vaultwarden.md).

Both classes are now checked. Version drift is additionally removed at the source by the weekly
auto-update.

## Health check

`monitoring/vps-health.sh`

| Check | Alerts when |
|-------|-------------|
| `disk` | `/` at or above `DISK_WARN` (85 %) as WARN, `DISK_CRIT` (92 %) as CRIT |
| `containers` | any of vaultwarden, shopware, dolibarr, dolibarr_db, dolibarr_cron, restic is missing, stopped or `unhealthy` |
| `backup` | the last restic run failed, or finished more than `BACKUP_MAX_AGE_HOURS` (26) ago |
| `vaultwarden_db_backup` | the consistent database copy is missing, or older than `DB_BACKUP_MAX_AGE_HOURS` (26) |
| `http` | `vault.sdwa5.org/alive`, `sdwa5.org` or `erp.sdwa5.org` returns anything but 200 |
| `caddy` | `systemctl is-active caddy` is not `active` |
| `firewall` | the IPv4 `INPUT` policy is not `DROP`, fail2ban's jump is gone, or a port in `FIREWALL_PORTS` (22 80 443) is no longer accepted. An open IPv6 policy is a WARN rather than a CRIT |
| `vaultwarden_version` | the running version is behind the newest GitHub release |

A container reporting `starting` is not an alert, that is a normal `start_period`. GitHub being
unreachable is not an alert either, otherwise the recipient learns to ignore this mail.

The firewall check exists because that failure is silent. Anything that flushes `INPUT`, including
the firewall unit's own restart, removes fail2ban's jump, and the chain still looks plausible
afterwards. A missing `iptables` binary or an unreadable chain is reported as CRIT rather than
passing, since a check that cannot see its subject has not confirmed anything. All faults it finds
are reported in one line rather than one per run, so a single mail carries the whole picture.

IPv6 is a WARN rather than a CRIT because no AAAA record is published for either hostname, so nothing
resolves to the host over IPv6 and an open v6 policy is a gap that matters once that changes. Whether
inbound IPv6 reaches the host at all is unverified, see the firewall section of
[ssh-hardening.md](ssh-hardening.md). Raise this to CRIT if an AAAA record is ever published.

### Reminder backoff

An unchanged problem does not mail every day forever. The interval doubles from one day and caps at
30 days:

| Mail | initial | 1st reminder | 2nd | 3rd | 4th | 5th | 6th and later |
|------|---------|--------------|-----|-----|-----|-----|---------------|
| Sent after | immediately | 1 d | 2 d | 4 d | 8 d | 16 d | every 30 d |

So a known, accepted condition costs six mails in the first month and one a month after that.

Three things break the backoff and alert immediately:

- the status escalates, for example WARN to CRIT
- the message changes shape, for example a second container dies
- the problem recovers and comes back later, which resets the counter to zero

State lives in `/var/lib/vps-health/state`, one tab-separated record per check holding the status, a
message fingerprint, `first_seen`, `last_notified` and `notify_count`.

### Usage

```bash
/opt/docker/monitoring/vps-health.sh              # what cron runs
/opt/docker/monitoring/vps-health.sh --dry-run    # print every result, send nothing, write nothing
/opt/docker/monitoring/vps-health.sh --test-mail  # prove the mail path works
/opt/docker/monitoring/vps-health.sh --help
```

Rehearse a real alert by forcing a threshold:

```bash
DISK_WARN=1 /opt/docker/monitoring/vps-health.sh --dry-run
```

Silence a check you have accepted by overriding its threshold in `/opt/docker/.env`, for example
`DISK_WARN=95`. Removing a check entirely means editing `run_checks` in the script.

## Vaultwarden database backup

`monitoring/vaultwarden-db-backup.sh`

restic mounts `/opt/docker` read-only and copies `vaultwarden-data/db.sqlite3` while Vaultwarden is
writing to it. SQLite in WAL mode spreads a commit across the database file and the write-ahead log,
so a copy taken between the two can restore into a torn transaction. Nothing warns about it, and the
damage only surfaces on the day the restore is actually needed.

This job removes that. It writes a consistent copy through SQLite's own online backup API, which
reads through SQLite rather than copying bytes, so the write-ahead log is folded in and the result is
one restorable file.

1. Dump `vaultwarden-data/db.sqlite3` to `vaultwarden-db-backup/db.sqlite3.tmp`.
2. Verify the dump with `PRAGMA integrity_check`.
3. Only then rename it over `vaultwarden-db-backup/db.sqlite3`.

Any failure keeps the previous verified copy in place and mails. A dump that fails its integrity
check is discarded rather than published, because a copy that cannot be read back is not a backup.

Vaultwarden keeps serving throughout. The backup API takes a read lock per page batch instead of
stopping the container, so unlike the update job this one needs no downtime.

The job runs at 03:50, ten minutes before restic at 04:00, so every snapshot contains a database that
is safe to restore. The hot copy in `vaultwarden-data/` stays in the snapshot as well. It costs
nothing and sits next to the consistent one, so a restore has both.

`sqlite3` has to be installed on the host. Without it the job mails and exits non-zero rather than
leaving the gap silently open.

```bash
/opt/docker/monitoring/vaultwarden-db-backup.sh              # what cron runs
/opt/docker/monitoring/vaultwarden-db-backup.sh --dry-run    # report the paths, write nothing
/opt/docker/monitoring/vaultwarden-db-backup.sh --help
```

Restore from a snapshot with the consistent copy rather than the hot one:

```bash
docker exec restic restic restore latest --target /tmp/restore
sqlite3 /tmp/restore/data/vaultwarden-db-backup/db.sqlite3 'PRAGMA integrity_check;'
```

## Vaultwarden auto-update

`monitoring/vaultwarden-autoupdate.sh`

1. Pull `vaultwarden/server:latest` and compare image IDs. Unchanged means exit, silently.
2. Snapshot `vaultwarden-data/` to `vaultwarden-data.bak-<timestamp>`. The newest 3 are kept.
3. `docker-compose up -d vaultwarden`.
4. Poll `https://vault.sdwa5.org/alive` for up to 60 s expecting 200.
5. Success sends a short report naming the old and the new version.
6. Failure restores the snapshot, pins the previous image in `docker-compose.override.yml`, brings
   that back up and mails a loud alert.

Vaultwarden runs forward-only database migrations, so a downgrade is not supported and the snapshot
is the only way back. `vaultwarden-data/` is under 10 MB, so keeping three costs nothing.

**If a rollback ever fires, `docker-compose.override.yml` must be deleted once the cause is
understood.** While it exists Vaultwarden stays pinned to an old image and drifts behind the clients
again, which is the exact failure this job was built to prevent.

Only Vaultwarden is auto-updated. Shopware, Dolibarr and MariaDB stay manual, tracked in
[TODO.md](../TODO.md).

The job runs Sunday 03:00, one hour before the restic backup at 04:00, so the daily backup always
captures the post-update state.

## The two jobs watch each other

Without an all-green digest, a health check that silently stopped running looks exactly like a
healthy server. `vps-health.sh` writes `/var/lib/vps-health/last-run` on every run, and the weekly
update job mails if that file is missing or older than two hours.

## Mail delivery

Recipients are `ripper@sdwa5.org`, overridable through
`MONITOR_MAIL_TO`.

Mail goes out through `curl` to `smtps://smtp.gmail.com:465` as `ripper@sdwa5.org`, reusing the
Gmail app password Vaultwarden already sends from. The local exim4 would deliver direct-to-MX from a
Contabo address and land in Gmail's spam folder, which for an alerting channel is the same as not
sending at all.

The password is handed to `curl` through a config file on stdin, so it never appears in the process
list.

### Configuration

`/opt/docker/.env`, see [`.env.example`](../.env.example):

| Key | Default | Meaning |
|-----|---------|---------|
| `MONITOR_SMTP_PASSWORD` | — | required, Gmail app password for `MONITOR_SMTP_USER` |
| `MONITOR_SMTP_USER` | `ripper@sdwa5.org` | SMTP login and envelope sender |
| `MONITOR_SMTP_HOST` | `smtp.gmail.com` | |
| `MONITOR_SMTP_PORT` | `465` | implicit TLS |
| `MONITOR_MAIL_TO` | both addresses above | space-separated |

Vaultwarden already holds the same app password. Copy it across without ever printing it:

```bash
python3 -c 'import json;print("MONITOR_SMTP_PASSWORD="+json.load(open("/opt/docker/vaultwarden-data/config.json"))["smtp_password"])' >> /opt/docker/.env
chmod 600 /opt/docker/.env
```

Rotating the Gmail app password means updating it in both places, the Vaultwarden admin panel and
`/opt/docker/.env`.

## Installation

```bash
cd /opt/docker
git pull --ff-only
apt install sqlite3
install -m 644 -o root -g root monitoring/cron.d/vps-health              /etc/cron.d/vps-health
install -m 644 -o root -g root monitoring/cron.d/vaultwarden-db-backup   /etc/cron.d/vaultwarden-db-backup
install -m 644 -o root -g root monitoring/cron.d/vaultwarden-autoupdate  /etc/cron.d/vaultwarden-autoupdate
mkdir -p /var/lib/vps-health
/opt/docker/monitoring/vaultwarden-db-backup.sh
/opt/docker/monitoring/vps-health.sh --test-mail
```

Cron output goes to the journal under the tags `vps-health` and `vaultwarden-autoupdate`, which is
already size-capped by the runbook in [maintenance.md](maintenance.md), so nothing new needs
rotating:

```bash
journalctl -t vps-health -n 50
journalctl -t vaultwarden-db-backup -n 50
journalctl -t vaultwarden-autoupdate -n 50
```

## Tests

```bash
tests/run.sh          # bats suite plus shellcheck, both in Docker
```

The suite stubs `docker`, `docker-compose`, `curl`, `sqlite3`, `systemctl`, `df` and `hostname`, and drives the
clock through `FAKE_NOW`, so the whole backoff schedule is verified in under a second without
waiting days and without touching a real host. `tests/run.sh` installs GNU coreutils into the
throwaway bats container, because the Alpine base ships busybox `date`, which cannot parse the
timestamps the scripts read out of the restic log.

## Limitations

Both jobs run on the monitored host. If the VPS is off, or cron is dead, or the network is gone, no
mail arrives and the silence is indistinguishable from health. An external dead-man's switch would
close that gap. It was deliberately not added, see [TODO.md](../TODO.md).
