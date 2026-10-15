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
| Repository        | `rclone:sdwa5backup:restic-backups`, Shared Drive "SdWa5 Backup" |
| Retention         | 6 daily, 3 weekly, 11 monthly, 2 yearly |
| Restic password   | `RESTIC_PASSWORD` in `.env`        |
| rclone remote     | `sdwa5backup`, defined by `RCLONE_CONFIG_SDWA5BACKUP_*` in `docker-compose.yml` |
| Identity          | service account `restic-backup`, key `/opt/docker/rclone-config/restic-sa.json` (mode 600) |

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

## Consistent SQL database archives

`monitoring/database-backup.sh` takes application-database dumps from `dolibarr_db`, `shopware` and
`chimodiazz_shopware` at **03:40 Europe/Berlin**. Restic's 04:00 UTC run follows in both winter and summer.
The job is silent on success. Failures are logged and recorded for the existing health alert.

Each archive under the gitignored `database-backup/` contains `dump.sql` and `manifest.tsv`. The manifest
records the schema, database version, table count, engine family and running image ID. The directory is
mode 700 and the archives are mode 600. Credentials pass directly from the running container's
configuration to its native client. They are not command-line arguments or monitoring output.

The ERP uses its application account. Shopware resolves its effective environment with the application's
installed Dotenv and DBAL libraries, so local environment overrides are respected. The helper and client
run inside the application container. No additional production dependency is installed.

The job checks that base tables use InnoDB, then dumps data, triggers, routines and events with
`--single-transaction`. It refuses nontransactional tables instead of claiming a consistent snapshot.
Do not run schema changes while a dump runs. The job shares the Chimo deployment lock to exclude that
automatic deployment. Ordinary InnoDB application writes continue. The database clients document the
snapshot and DDL limits in [MariaDB's dump reference](https://mariadb.com/docs/server/clients-and-utilities/backup-restore-and-import-clients/mariadb-dump)
and [MySQL's dump reference](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html).

A completed dump is packaged and checked before one atomic rename replaces the previous archive.
Failures preserve the previous archive and leave a failure marker. A successful retry clears the marker.
The current archive is replaced locally; historical versions remain in restic snapshots. This job does
not change the restic retention policy or delete existing restore points.

If MariaDB reports an incompatible routine catalog, the job additionally attempts a transactional
table-only rescue dump. It saves a separate ".tables-only.tar.gz" archive with that limitation in its
manifest. It never replaces a full archive with this rescue copy. The job still fails and the health
alert remains active until a complete backup succeeds, which also deletes the superseded rescue copy.
Earlier copies remain in restic. A table-only archive includes table data,
triggers and events, but does not prove that stored procedures or functions can be recovered.
Use the explicit `--tables-only` option to verify this rescue archive. Repairing system tables or
changing authentication is a separate maintenance operation.

The job also fails before dumping when a table carries the same foreign key name twice. Such a dump
completes but does not import (`errno: 150 "Foreign key constraint is incorrectly formed"`), so the
archive would look good and restore nothing. MariaDB 12.1 made foreign key names unique per table
([MDEV-28933](https://jira.mariadb.org/browse/MDEV-28933)). A key created under an older server keeps
its old-format name, which 12.x no longer matches when the same constraint is added again. Dolibarr adds
many constraints both in its key files and in its migrations, and that left 15 pairs in the ERP,
measured 2026-10-15.

Neither `mariadb-upgrade` nor a table rebuild converts the old names. Dropping each key and adding it
back under 12.x does, and `tools/mariadb/recreate-foreign-keys.sh` does that for one container. It is
dry-run by default, refuses while a duplicate exists, and compares every definition before and after.
All 225 ERP keys were recreated this way on 2026-10-15, and a repeated `ADD CONSTRAINT` is rejected
again since. When the guard fires, drop one key of each pair first, because `DROP FOREIGN KEY`
removes exactly one of them, then run the tool.

```bash
tools/mariadb/recreate-foreign-keys.sh dolibarr_db
tools/mariadb/recreate-foreign-keys.sh dolibarr_db --apply
```

Every MariaDB service sets `MARIADB_AUTO_UPGRADE=1`. Without it the image's entrypoint skips
`mariadb-upgrade` after a version bump. That is how the ERP's `mysql.proc` stayed in the 11.8 format
under 12.3 and `mariadb-dump --routines` failed with `Column count of mysql.proc is wrong`, measured
2026-10-14 (`mariadb_upgrade_info` still read 11.8.2). With it, the first start on a new version
backs up the `mysql` schema to `system_mysql_backup_<old version>.sql.zst` in the datadir, runs the
upgrade with grants off and then starts normally. No root login is needed for that.

The root password in `.env` reaches the database only when an empty datadir is initialised. When the
two have drifted apart, `tools/mariadb/reset-root-password.sh` sets every existing root account back
to the configured value. It runs a throwaway container of the stopped service with grants and
networking off, proves the new password with a root login and never prints it.

```bash
docker compose stop dolibarr_db
tools/mariadb/reset-root-password.sh dolibarr_db
docker compose up -d dolibarr_db
```

```bash
monitoring/database-backup.sh --dry-run
monitoring/database-backup.sh
monitoring/database-restore-check.sh dolibarr_db
monitoring/database-restore-check.sh shopware
monitoring/database-restore-check.sh chimodiazz_shopware
```

The restore check imports the archive into a new temporary database using the exact image recorded in
its manifest. The image must be available locally. The container has no network, no published ports,
disabled scheduled SQL events and no production mounts. It uses only a new disposable data volume.
SQL import, table count and `CHECK TABLE` on every base table must pass. The check runs through the
SQL client, because not every server image ships `mysqlcheck`. The new volume is mounted with
`volume-nocopy`, since the dockware Shopware image ships files under `/var/lib/mysql` that Docker would
otherwise copy in and that make `mysqld --initialize` abort. For MariaDB the import waits for the
entrypoint's "init process done" line, because its temporary bootstrap server answers queries and
then shuts down. `RESTORE_READY_TIMEOUT` (90 seconds) bounds that wait. The scratch files, container
and volume are removed on exit, including failed imports. A failed cleanup is reported rather than silently ignored.
Only the isolated server permits a passwordless local root connection.

These checks prove the tested SQL restore path. They do not test whole-VM recovery, every application
workflow or synchronization between a database and separately copied media/documents. Application
credentials and other service state still come from the protected restic backup or the vault.

To test a restic copy, restore `/data/database-backup` from a chosen snapshot into a private scratch
directory, then set `DATABASE_BACKUP_DIR` to that directory for the same three restore commands.
Delete the restored scratch copy afterward because it contains application data.

## rclone remote

The remote `sdwa5backup` is a Google Drive remote defined entirely through environment variables in
`docker-compose.yml`, so it needs no entry in `rclone.conf`. It authenticates as the service account
`restic-backup` in the Google Cloud project `pro-icon-447800-e5` of the organisation sdwa5.org. The
account holds no IAM role. Its only Drive access is membership as **Content manager** of the Shared
Drive "SdWa5 Backup", whose ID is `RESTIC_SHARED_DRIVE_ID` in `.env`. Its own My Drive is empty.

Measured on 2026-10-15 before the switch: the service account listed exactly one Shared Drive, "SdWa5
Backup", and nothing in its own drive. Its predecessor, the OAuth remote `[SdWa5]` with scope
`drive`, listed the owner's whole My Drive (113 GB, of which the repository was 109 GB) and four
Shared Drives, two of them private. A stolen token from this host therefore exposed far more than
the backups. That token was revoked through Google's revoke endpoint on 2026-10-15 (HTTP 200, a
probe afterwards failed with `invalid_grant`), and its section was removed from `rclone.conf`.

The key file `rclone-config/restic-sa.json` is a long-lived credential and is gitignored with the
rest of `rclone-config/`. **Never commit it, never print it.** The organisation enforces
`iam.disableServiceAccountKeyCreation`. The key was created during a temporary project-level override
that was removed again right after. A replacement key needs the same override, by an account with
Organisation Policy Administrator on sdwa5.org. Revoke an old key under the service account's
**Keys** tab once its replacement works.

Switched on 2026-10-15 at 14:10 CEST by setting `RESTIC_REPOSITORY` in `.env`. Before the switch,
`restic check --read-data-subset 2%` through the service account found no errors, all 69 snapshots
were listed, and the vault restore drill passed (integrity `ok`, 6 users, 472 ciphers, 44 seconds with
a cold cache). The first backup after the switch, snapshot `f65ba272`, took 286 seconds including
`forget --prune`, and `vps-health.sh --dry-run` reported every check `OK`.

The repository was copied server-side from the owner's My Drive (`rclone copy --drive-server-side-across-configs`,
22 945 files, 109.17 GiB, 0 errors, 12:41 to 13:59 CEST on 2026-10-15), and `rclone check --one-way`
compared checksums afterwards with 0 differences. The My Drive copy stays
untouched as a fallback until the grace period noted in the changelog ends.

## Operations

```bash
# Check backup status / last run
docker logs restic

# Manual backup now
docker exec restic /bin/sh /opt/restic/backup.sh

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

`dolibarr-secrets/` behaves the same way. A restic restore brings BankSync's `paypal.json` back, and
a rebuild from git alone needs it from Vaultwarden, see [dolibarr.md](dolibarr.md#module-secrets).

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
| Rows | users, ciphers, organizations and collections all present |
| Schema migration | `20260505120000` |
| Live vault at the time | same users and organizations, a few more ciphers added after the snapshot, which is the expected daily drift rather than a fault |

The hot copy `vaultwarden-data/db.sqlite3` was restored in the same run purely to test it, and it also
returned `ok` without its `-wal`. That is the finding recorded above: a clean `integrity_check` says
nothing about whether a hot restore is complete.

### The drill after the image switch

Rerun on 2026-10-15 after the restic service moved to `creativeprojects/resticprofile:0.33.1-amd64`, so
restic 0.19.1 and rclone 1.75.2 against the same Drive repository. A manual run of
[`restic/backup.sh`](../restic/backup.sh) wrote snapshot `688240b9` (8.922 GiB) in 258 seconds
including `forget --prune`, which repacked 404 packs and left 109.133 GiB in the repository.

| | Result |
|---|---|
| Restore wall time | **8 seconds** for the vault database alone |
| `PRAGMA integrity_check` | `ok` |
| Users, ciphers | 6 and 472, the same as the live consistent copy at that moment |
| Schema migration | `20260902120000` |
| `vps-health.sh --dry-run` | every check `OK`, backup `Newest restic snapshot 0h ago` |

### Not drilled, and why

The **Contabo Auto Backup** restores only as an entire VM image, so testing it means replacing the
running host. It is accepted as an untested path rather than left looking merely undone. It stays
worth having as a second, independent copy — it is the only one that survives losing the Google
account.

## Notes

- The restic container mounts all of `/opt/docker/` as `/data` read-only.
- `.gitignore` exclusions do NOT affect what restic backs up — restic backs up everything including data dirs and `.env`.
- The restic container accumulates **zombie processes**. Measured 108 on 2026-09-08 after 51 days up.
  The old image's PID 1 was `tail -fn0 /var/log/cron.log` with no init, so nothing reaped the `rclone`
  children each run spawned. `init: true` on the service fixes it and stays with the new image. Harmless at this rate against a `kernel.pid_max`
  of 4194304, but it is an unbounded leak.
- The container runs **restic 0.19.1 and rclone 1.75.2** from the pinned
  `creativeprojects/resticprofile:0.33.1-amd64` image since 2026-10-15. Only the binaries are used.
  [`restic/entrypoint.sh`](../restic/entrypoint.sh) writes the crontab and runs crond in the foreground,
  [`restic/backup.sh`](../restic/backup.sh) runs `backup` and then `forget`, and both keep the log lines
  of the former `lobaro/restic-backup-docker` image, so `vps-health.sh` reads them unchanged. restic's own
  output of the last run is in `/var/log/backup-last.log` inside the container.
- The repository stays at **format version 1**. restic 0.19 reads and writes it without upgrading it.
  Measured 2026-10-15 on a throwaway repository, restic 0.12.0 still listed, checked and restored it
  after 0.19.1 had backed up and pruned, so going back to the old image stays possible. `restic migrate
  upgrade_repo_v2` would end that and needs its own decision.
- Unlike the old image, nothing here runs `restic init`. lobaro initialised a repository whenever
  `restic snapshots` failed at start-up, so a transient Drive error could have started an empty one.
