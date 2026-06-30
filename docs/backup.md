# Backup

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

# Check repo integrity
docker exec restic restic check
```

## Notes

- The restic container mounts all of `/opt/docker/` as `/data` read-only.
- `.gitignore` exclusions do NOT affect what restic backs up — restic backs up everything including data dirs and `.env`.
- `rclone.conf` OAuth token auto-refreshes; the `expiry` field in the token will update on next use.
