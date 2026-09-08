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
| Schedule          | Daily at 04:00                     |
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

`monitoring/vaultwarden-db-backup.sh` runs at 03:50, ten minutes before restic, and writes a verified
consistent copy to `vaultwarden-db-backup/db.sqlite3` through SQLite's online backup API. restic then
picks it up as an ordinary file. See [monitoring.md](monitoring.md).

**Restore the vault from `vaultwarden-db-backup/db.sqlite3`, not from `vaultwarden-data/db.sqlite3`.**
The hot copy is still in every snapshot, and it is the one that can be torn.

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

## Notes

- The restic container mounts all of `/opt/docker/` as `/data` read-only.
- `.gitignore` exclusions do NOT affect what restic backs up — restic backs up everything including data dirs and `.env`.
- `rclone.conf` OAuth token auto-refreshes; the `expiry` field in the token will update on next use.
- No restore drill has been run yet, so the repository is unproven end to end. Tracked in
  [TODO.md](../TODO.md).
