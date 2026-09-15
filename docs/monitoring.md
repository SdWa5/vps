# Monitoring

Four cron jobs, no dashboard, no extra container, no external monitoring service.
All live in [`monitoring/`](../monitoring/) and are deployed to `/opt/docker/monitoring/`.

| Job | Script | Schedule | Sends mail when |
|-----|--------|----------|-----------------|
| Health check | `vps-health.sh` | hourly, `:17` | something is wrong or has just recovered |
| Vaultwarden database copy | `vaultwarden-db-backup.sh` | daily 03:50 | the dump failed or could not be verified |
| Vaultwarden update | `vaultwarden-autoupdate.sh` | daily 03:00 | an update was applied, an update failed, or the health check stopped running |
| Shopware worker | `shopware-worker.sh` | every minute, under `flock` | the scheduled tasks or the queue consumer failed, or the container is down |

**A healthy system sends nothing.** There is no all-green digest.

## Why this exists

Two incidents, both silent until they became visible as an outage.

- **July 2026** — root `/` filled to 100 %. Nothing was watching disk usage. See
  [maintenance.md](maintenance.md).
- **September 2026** — Vaultwarden sat at 1.36.0 while the Bitwarden clients auto-updated past it.
  The browser extension and the mobile app stopped working, the web vault kept going because it
  ships with the server. See [vaultwarden.md](vaultwarden.md).

Both classes are now checked. Version drift is additionally removed at the source by the daily
auto-update.

## Health check

`monitoring/vps-health.sh`

| Check | Alerts when |
|-------|-------------|
| `disk` | `/` at or above `DISK_WARN` (85 %) as WARN, `DISK_CRIT` (92 %) as CRIT |
| `containers` | any of vaultwarden, shopware, dolibarr, dolibarr_db, dolibarr_cron, restic is missing, stopped or `unhealthy` |
| `backup` | the newest snapshot **in the repository** is older than `BACKUP_MAX_AGE_HOURS` (26), the repository cannot be reached or holds no snapshots at all, or the container log reports an explicitly failed run |
| `vaultwarden_db_backup` | the consistent database copy is missing, or older than `DB_BACKUP_MAX_AGE_HOURS` (26) |
| `http` | `vault.sdwa5.org/alive`, `sdwa5.org`, `erp.sdwa5.org` or `chimodiazz.sdwa5.org` returns anything but 200 |
| `caddy` | `systemctl is-active caddy` is not `active` |
| `firewall` | the IPv4 `INPUT` policy is not `DROP`, fail2ban's jump is gone, a port in `FIREWALL_PORTS` (22 80 443) is no longer accepted, or **`DOCKER-USER` is missing or back to Docker's empty `-j RETURN`**, which leaves every published container port unfiltered. An open IPv6 policy is a WARN rather than a CRIT |
| `shopware_tasks` | the newest Shopware scheduled task ran longer than `SHOPWARE_TASK_MAX_AGE_HOURS` (2) ago, the task list cannot be read, or no task has ever run |
| `vaultwarden_version` | the running version is behind the newest GitHub release **and that release is older than `VAULTWARDEN_DRIFT_GRACE_HOURS` (26)** |
| `git_remote` | `git ls-remote` against the checkout's origin fails, so `/opt/docker` cannot pull |

A container reporting `starting` is not an alert, that is a normal `start_period`. GitHub being
unreachable is not an alert either, otherwise the recipient learns to ignore this mail.

### The checkout's reach to its remote, and why it is asked daily

`git_remote` exists because of a failure that ran unnoticed for three cycles. **A deploy key belongs to
the repository object on the forge, so recreating the repository destroys it**, and the redaction
passes of 2026-09-12, 2026-09-13 and 2026-09-15 each republished by renaming, creating an empty
repository under the old name and deleting the rename. After every one of them `/opt/docker` could no
longer pull, and none of the nine checks asked.

**It does not look broken from the outside**, which is the whole reason a check is needed rather than a
habit. A destroyed deploy key still authenticates and greets with the name of the repository it died
with, so only a call that actually fetches says so. One `git ls-remote` covers three failure modes at
once, namely a destroyed or revoked key, a moved remote, and a host that cannot reach the forge.

**The cadence is asymmetric on purpose.** A success is stamped and the remote is not asked again for
`GIT_REMOTE_MAX_AGE_HOURS` (26), because this check costs an authenticated round trip and watches a
fact that holds for months; hourly would be 24 calls a day for nothing. A **failure is not stamped**,
so while it is broken the call is repeated every run and a recovery shows up within the hour instead
of a day later. `GIT_CHECKOUT_DIR` names the checkout and defaults to the compose root, because the
two are the same directory only by convention.

The Shopware task check exists because that failure is silent in a different way. Shopware's scheduled
tasks stop without any error, and the only symptoms are indirect: a sitemap that stops advancing, a
cache that stops being invalidated, tables that stop being pruned. **Measured 2026-09-08, nothing had
run them since 2026-07-23**, which is 47 days, and nothing noticed. So the check reads
`scheduled-task:list` itself rather than any symptom.

It takes the **newest** last-execution across all tasks rather than the oldest. The intervals range
from 60 seconds to a month, so one task being far behind is normal, while the newest of them being old
means nothing is running at all. The timestamps are ISO 8601 with an offset, so the host's timezone
cannot misread them, which is the same trap the backup check fell into.

**After an outage the scheduler catches up, and that looks like a defect without being one.** On the
first two worker runs after the 47-day gap, `shopware.invalidate_cache` ran twice inside 97 seconds
despite its 300-second interval. The reason is that Shopware clamps a task's next execution to *now*
when `last + interval` is still in the past, which is the normal case for a task 47 days overdue. So
the first run leaves the task immediately due again, and the second one finally puts it in the future.
Measured across three consecutive runs: afterwards `shopware.invalidate_cache` sat at +300 s,
`log_entry.cleanup` at the next day and `app.system_heartbeat` at the next week, and a further run
changed nothing. **Do not chase this if a fresh deployment appears to run everything twice.**

**One portability trap, because it cost a wrong CRIT on the first deploy.** The check parses the task
table with `awk`, and **the host's `awk` is `mawk`, which does not honour interval expressions**.
Measured 2026-09-08: `/^[0-9]{4}-/` matches nothing there while `/^[0-9][0-9][0-9][0-9]-/` matches. The
test suite cannot catch this, because `tests/run.sh` runs bats in an Alpine container whose busybox
`awk` does support intervals, and the workstation has GNU awk. Three implementations are in play and
only the host's decides, so anything written here stays inside POSIX `awk`.

`monitoring/shopware-worker.sh` is what runs those tasks now, every minute under `flock`. Shopware's
own documentation warns that cron-driven workers pile up, because cron does not wait for the previous
run, so `flock -n` makes a run whose predecessor is still going exit immediately. The admin worker is
turned off in `shopware-html-data/config/packages/shopware.yaml`, because Shopware requires that once
a CLI worker exists. See
[shopware/infrastructure.md](shopware/infrastructure.md#runtime-what-runs-shopwares-background-work).

The backup check **asks the repository rather than the container log**, and it is worth saying why,
because it was the log until 2026-09-08 and that produced two false alarms.

* **A container recreation wipes the log**, and an empty log cannot be told apart from a backup that
  never ran. Adding `init: true` to the restic service was enough to fire a CRIT against a repository
  that was entirely healthy.
* **The log prints UTC and the host reads it as Europe/Berlin.** `date -d` on a bare timestamp uses
  the local zone, so every backup was computed **two hours older than it was**. Against a 24-hour
  cycle and a 26-hour threshold that leaves no slack, and it put a false CRIT window at exactly the
  hour the next run starts.

`restic snapshots --json` answers both. It is the authoritative answer to whether a backup exists,
rather than a claim in a log that a recreation can erase, and its timestamps are RFC3339 with an
explicit offset so the host's zone cannot misread them. The newest snapshot is taken as the maximum
of the returned timestamps rather than the last element, so the check does not depend on restic's
ordering. The log is still read, but only as an early warning for an explicitly failed run, and it can
no longer raise an alarm by being absent.

The firewall check exists because that failure is silent. Anything that flushes `INPUT`, including
the firewall unit's own restart, removes fail2ban's jump, and the chain still looks plausible
afterwards. A missing `iptables` binary or an unreadable chain is reported as CRIT rather than
passing, since a check that cannot see its subject has not confirmed anything. All faults it finds
are reported in one line rather than one per run, so a single mail carries the whole picture.

IPv6 is a WARN rather than a CRIT because no AAAA record is published for either hostname, so nothing
resolves to the host over IPv6 and an open v6 policy is a gap that matters once that changes. Inbound
IPv6 does reach the host, including cold after 25 minutes idle, and an `ssh -6` login succeeds, see
the firewall section of [ssh-hardening.md](ssh-hardening.md). Raise this to CRIT if an AAAA record is
ever published, because at that point the v6 rules carry real traffic.

Note what this check does **not** cover. It reads the `INPUT` chain, and a published container port
never traverses `INPUT`, so a container exposed on `0.0.0.0` passes this check while being public.
`DOCKER-USER` is an empty `RETURN` on this host.

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

The job runs at 03:50 **host time**, which is Europe/Berlin, so 01:50 UTC. restic runs at 04:00
**inside its container**, which has no `TZ` and therefore runs UTC. The gap is 2 hours 10 minutes and
not the ten minutes this document used to claim, and it is 3 hours 10 minutes under CET. The ordering
holds in both, so every snapshot does contain a database that is safe to restore, but it holds by
arithmetic across two timezones. Any change to either schedule has to be reasoned about in UTC. The hot copy in `vaultwarden-data/` stays in the snapshot as well. It costs
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

**Three snapshots covered three weeks while the job was weekly and now cover three days.** That is a
deliberate trade and not an oversight: the snapshot exists to undo the update that just happened, and
anything older than that is restic's job. Note the other half of it, which is that
`prune_snapshots()` matches every directory named `vaultwarden-data.bak-*` and cannot tell a hand-made
snapshot from a rotated one. A snapshot somebody wants to keep belongs outside that pattern.

**If a rollback ever fires, `docker-compose.override.yml` must be deleted once the cause is
understood.** While it exists Vaultwarden stays pinned to an old image and drifts behind the clients
again, which is the exact failure this job was built to prevent.

Only Vaultwarden is auto-updated. Shopware, Dolibarr and MariaDB stay manual, tracked in
[TODO.md](../TODO.md).

The job runs daily at 03:00 host time, so 01:00 UTC, the consistent database copy follows at 01:50
UTC and restic runs at 04:00 UTC. The two crons live in different timezones, so that ordering only
reads correctly in UTC, and any change to one of the three schedules has to be reasoned about there.
The intent holds, so the daily backup does capture the post-update state.

### Why daily rather than weekly

**A weekly actor cannot keep up with an hourly detector, and the gap between them is what arrives as
mail.** 1.37.3 was published on 2026-09-13 at 15:03 UTC and its image reached Docker Hub at 14:55
UTC. The weekly job had run at 01:00 UTC that same day, fourteen hours before the image existed, and
correctly did nothing. The next attempt would have been 2026-09-20. `vps-health.sh` found the drift
at 17:17 local time and mailed about it twice before the updater was due again.

So the schedule moved to daily and the version check gained a grace window, and the two numbers are
tied to each other. `VAULTWARDEN_DRIFT_GRACE_HOURS` is 26, which is this job's period plus two hours
of slack, because a release published just after 03:00 waits nearly a full day by design. Below the
window the check reports `OK` and names the wait. Above it the check warns, and **that warning now
means the update job is not working**, which is something to act on, rather than "upstream has
shipped", which is not.

The extra runs cost one `docker-compose pull` a day. An unchanged image exits silently.

## The two jobs watch each other

Without an all-green digest, a health check that silently stopped running looks exactly like a
healthy server. `vps-health.sh` writes `/var/lib/vps-health/last-run` on every run, and the daily
update job mails if that file is missing or older than two hours.

**That alarm has no backoff of its own, so it is rate limited instead.** Weekly, a dead
`vps-health.sh` cost one mail a week; daily would have cost one a day for as long as it lasted, which
is the "mails every day forever" the reminder schedule above exists to prevent. The alarm now repeats
at most every seven days, held by `/var/lib/vps-health/autoupdate-health-alerted`. The stamp is
written only when a mail actually went out, so a failed delivery does not silence the next attempt,
and it is removed the moment the health check reports in again, so a fault that recurs after a
recovery alerts immediately rather than waiting out the old interval.

## Mail delivery

Recipients are every space-separated address in `MONITOR_MAIL_TO`. It defaults to `ripper@sdwa5.org`
alone, and the host adds any further recipient in `/opt/docker/.env`.

**A private address belongs in `.env` and not in this repository.** The default used to carry one
directly in `monitoring/lib.sh`, which would have published it the moment the repository went public,
so it moved to `.env` on 2026-09-08 with the effective recipient list unchanged. `.env` is
gitignored.

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
| `MONITOR_MAIL_TO` | `ripper@sdwa5.org` | space-separated; the host sets its own list in `.env` |

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
install -m 644 -o root -g root monitoring/cron.d/shopware-worker         /etc/cron.d/shopware-worker
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
