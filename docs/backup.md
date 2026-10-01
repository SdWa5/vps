# Backup

Two independent backups exist, and only one of them was documented until 2026-09-08.

| | restic | Contabo Auto Backup |
|---|---|---|
| Scope | `/opt/docker` | the whole VM |
| Destination | Google Drive | Contabo |
| Schedule | daily 04:00 | daily, in a 07:00 to 18:00 UTC+2 window |
| Retention | 6 daily, 3 weekly, 11 monthly, 2 yearly | 10 daily |
| Size | per-file, deduplicated | about 18.4 GB per image |
| Restore | file level | whole VM |
| Controlled by | this repository | the Contabo panel only |

They fail differently, which is the point. restic dies if the rclone token expires, the Google Drive
quota fills or the container stops, and none of that touches Contabo's. Contabo's dies with the
account or the provider, and restores only as a whole machine.

## Contabo Auto Backup

Read from the panel on 2026-09-08. Ten images were present, `vmd157801-BU-…`, dated 2026-08-29 to
2026-09-07, growing from 18.08 GB to 18.39 GB, so a rolling **ten daily restore points** and no
weekly or monthly tier.

Two things follow from the timing, and both are lucky rather than designed.

**It runs after the consistent Vaultwarden dump.** `vaultwarden-db-backup.sh` writes its verified copy
at 03:50, and Contabo images the VM somewhere between 07:00 and 18:00, so every image contains a
consistent `vaultwarden-db-backup/db.sqlite3` that is at most a few hours older than the image
itself. A whole-VM image taken while SQLite is running captures `vaultwarden-data/db.sqlite3` hot, and
that copy can be torn exactly as restic's could. **Restore the vault from the dump, not from the hot
file**, which is the same rule as for restic.

**It is not driven from this repository and nothing here monitors it.** `vps-health.sh` cannot see it.
A silently failing Auto Backup would look identical to a working one from inside the host.

Automated backups via **Restic** + **rclone** to Google Drive.

## Configuration

| Setting           | Value                              |
|-------------------|------------------------------------|
| Schedule          | Daily at **04:00 UTC**, which is 06:00 CEST / 05:00 CET — the restic container has no `TZ` set and runs UTC |
| Source            | `/data` (= `/opt/docker/` read-only mount) |
| Repository        | `rclone:SdWa5:restic-backups` (Google Drive) |
| Retention         | 6 daily, 3 weekly, 11 monthly, 2 yearly |
| Restic password   | `RESTIC_PASSWORD` in `.env`        |
| rclone config     | `/opt/docker/rclone-config/rclone.conf` |

## The Vaultwarden database is copied consistently first

restic mounts `/opt/docker` read-only and copies files while they are being written. For
`vaultwarden-data/db.sqlite3` that is not safe. SQLite in WAL mode spreads a commit across the
database file and the write-ahead log, so a snapshot taken between the two can restore into a torn
transaction, and nothing warns about it until the restore is needed.

`monitoring/vaultwarden-db-backup.sh` writes a verified consistent copy to
`vaultwarden-db-backup/db.sqlite3` through SQLite's online backup API, and restic then picks it up as
an ordinary file. See [monitoring.md](monitoring.md).

**The two jobs are scheduled in different timezones, and the gap is not ten minutes.** The database
copy is `50 3 * * *` in `/etc/cron.d/vaultwarden-db-backup`, which is host cron and therefore
Europe/Berlin, so 01:50 UTC. restic is `0 4 * * *` inside a container with no `TZ`, so 04:00 UTC. The
real gap is 2 hours 10 minutes, and it is 3 hours 10 minutes under CET. The ordering is correct in
both, so nothing is broken, but it holds by arithmetic that nobody checked rather than by design. Any
change to either schedule has to be reasoned about in UTC.

**Restore the vault from `vaultwarden-db-backup/db.sqlite3`, never from
`vaultwarden-data/db.sqlite3`,** and the reason is stronger than "the hot copy might be torn":

- The live database is in **WAL mode**, measured 2026-09-08, with a 552 KB `db.sqlite3-wal` beside it.
  A commit lives across the main file and the log.
- Every snapshot captures all three of `db.sqlite3`, `db.sqlite3-wal` and `db.sqlite3-shm`, and restic
  reads files one after another rather than atomically. So the trio in a snapshot can be mutually
  inconsistent even though each file is individually fine.
- **A main file restored without its `-wal` opens cleanly and silently presents an earlier state.**
  Measured in the drill below: the hot copy restored on its own passed `PRAGMA integrity_check` with
  `ok`. So `integrity_check` is not evidence that a hot restore is complete, which is exactly what
  makes it dangerous.
- `vaultwarden-db-backup/db.sqlite3` has none of this, because `.backup` reads through SQLite and
  folds the write-ahead log in, producing one consistent file.

## rclone remote

Remote `[SdWa5]` — Google Drive (OAuth2). Config file at `rclone-config/rclone.conf` contains OAuth client credentials and refresh token. **Never commit this file.**

## Operations

```bash
# Check backup status / last run
docker logs restic

# Manual backup now
docker exec restic /bin/backup

# List snapshots
docker exec restic restic snapshots

# Restore (example: restore latest to /tmp/restore)
docker exec restic restic restore latest --target /tmp/restore

# Verify the restored Vaultwarden database before trusting it
sqlite3 /tmp/restore/data/vaultwarden-db-backup/db.sqlite3 'PRAGMA integrity_check;'

# Check repo integrity
docker exec restic restic check
```

A restic restore brings `shopware-html-data/auth.json` back with the rest of `/opt/docker`, since
`RESTIC_BACKUP_ARGS` sets no excludes, for every snapshot from 2026-10-02 on. A rebuild
from the git repository alone does not, because that file is gitignored. Its composer token for
`packages.shopware.com` then has to come from Vaultwarden before `composer install`, or the three Store
plugins fail to download, see [shopware/plugins.md](shopware/plugins.md).

## Retention groups, and why there are eleven of them

`restic forget` groups snapshots by **`host,paths`** by default, and restic records `os.Hostname()`
on every snapshot. In a container that is the **container ID**, which changes on every recreation. So
each time the restic container was recreated, the next backup started a brand-new retention group
with its own full allowance of 6 daily, 3 weekly, 11 monthly and 2 yearly.

Measured 2026-09-08:

| | |
|---|---|
| Distinct hostnames in the repository | **11**, each a past container ID |
| Snapshots held | 61 |
| Snapshots one group would hold | 17 |
| Repository raw-data size | 100.889 GiB across 176 717 blobs |
| Drive folder size | 106.230 GiB in 22 655 objects |
| Shared Drive quota | 100 TiB, of which 99.870 TiB free |

`hostname: sdwa5-vps` is now pinned in [docker-compose.yml](../docker-compose.yml), so recreating the
container no longer starts a group. From here the policy means what it says.

**The 44 extra snapshots are deliberately left alone, and that is a decision rather than an
oversight.** `--group-by paths` in `RESTIC_FORGET_ARGS` would apply the policy across all eleven
groups at once, and with `--prune` already in those args it would delete 44 snapshots on the next run.
It is not worth doing:

* **Storage is not a constraint.** 106 GiB against a 100 TiB quota is a tenth of a percent. The
  saving would be invisible.
* **More history is safer than less** for a backup. Deleting 44 restore points to make a policy tidy
  trades away the only thing the repository exists to provide.
* The real cost of the extra groups is that `prune` walks more data, so a run takes longer. Runtime is
  not a constraint here either, at 47 seconds measured.

So the fix is only to stop creating new groups. If the old ones are ever to be merged, that is a
deliberate one-off `forget --group-by paths` with the snapshot list read first, not a change to the
cron's arguments.

## Restore drill

**First run 2026-09-08, and it passed.** The repository had never been restored from, so it was
unproven end to end. Re-run it after any change to the backup path, and otherwise once a quarter.

Restoring through the existing container is deliberate: it already holds `RESTIC_REPOSITORY`,
`RESTIC_PASSWORD` and the rclone config, so the drill never handles the repository password.

```bash
# 1. Restore just the vault database into a scratch directory inside the container.
docker exec restic sh -c 'rm -rf /tmp/drill && mkdir -p /tmp/drill'
docker exec restic restic restore latest --target /tmp/drill \
    --include /data/vaultwarden-db-backup/db.sqlite3

# 2. Bring it out to where sqlite3 is. The container has no sqlite3; the host does.
mkdir -p /root/restore-drill
docker cp restic:/tmp/drill/data/vaultwarden-db-backup/db.sqlite3 /root/restore-drill/

# 3. Verify. integrity_check alone is not enough, so count rows as well.
cd /root/restore-drill
sqlite3 db.sqlite3 'PRAGMA integrity_check;'
sqlite3 db.sqlite3 'SELECT COUNT(*) FROM users;'
sqlite3 db.sqlite3 'SELECT COUNT(*) FROM ciphers;'
sqlite3 db.sqlite3 'SELECT MAX(version) FROM __diesel_schema_migrations;'

# 4. Delete the restore. It is a full copy of the vault.
rm -rf /root/restore-drill
docker exec restic sh -c 'rm -rf /tmp/drill'
```

**Step 4 is not tidiness.** The restored file is every credential the association has, in a directory
nothing else protects, and it is inside the tree restic itself backs up if placed under
`/opt/docker`. Restore to `/root` and delete it when done.

### What the first drill measured

Snapshot `b672181d`, taken 2026-09-07 04:00 UTC.

| | Result |
|---|---|
| Restore wall time | **6 seconds** for the vault database alone |
| Whole-snapshot restore size | 8.065 GiB across 56 403 files, so a full restore is a different order of magnitude |
| `PRAGMA integrity_check` | `ok` |
| `PRAGMA quick_check` | `ok` |
| Tables | 29 |
| Rows | 4 users, 450 ciphers, 1 organization, 5 collections |
| Schema migration | `20260505120000` |
| Live vault at the time | 4 users, **455** ciphers — five added after the snapshot, which is the expected daily drift rather than a fault |
| `emergency_access` | **0 rows**, which independently confirms the open item on emergency access enrolment |

The hot copy `vaultwarden-data/db.sqlite3` was restored in the same run purely to test it, and it also
returned `ok` without its `-wal`. That is the finding recorded above: a clean `integrity_check` says
nothing about whether a hot restore is complete.

### Not drilled, and why

The **Contabo Auto Backup** restores only as an entire VM image, so testing it means replacing the
running host. It is accepted as an untested path rather than left looking merely undone. It stays
worth having as a second, independent copy — it is the only one that survives losing the Google
account.

## Notes

- The restic container mounts all of `/opt/docker/` as `/data` read-only.
- `.gitignore` exclusions do NOT affect what restic backs up — restic backs up everything including data dirs and `.env`.
- `rclone.conf` OAuth token auto-refreshes; the `expiry` field in the token will update on next use.
- The restic container accumulates **zombie processes**. Measured 108 on 2026-09-08 after 51 days up.
  Its PID 1 is `tail -fn0 /var/log/cron.log` with no init, so nothing reaps the `rclone` children each
  run spawns. `init: true` on the service fixes it. Harmless at this rate against a `kernel.pid_max`
  of 4194304, but it is an unbounded leak.
- The container runs **restic 0.12.0, built 2021**, because the image has not been rebuilt since. See
  the image note in [TODO.md](../TODO.md).
