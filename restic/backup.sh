#!/bin/sh
#
# One restic backup run of /data, followed by the retention policy.
#
# Scheduled by restic/entrypoint.sh. Run it by hand with
#   docker exec restic /bin/sh /opt/restic/backup.sh
#
# The summary lines on stdout keep the wording of lobaro/restic-backup-docker's
# /bin/backup, because monitoring/vps-health.sh greps the container log for
# "^(Backup|Restic) (Successful|Failed)". restic's own output goes to
# BACKUP_LOG instead, so the container log stays readable.
#
# Environment:
#   RESTIC_REPOSITORY, RESTIC_PASSWORD   read by restic itself
#   RESTIC_JOB_ARGS      extra arguments for `restic backup` (word-split)
#   RESTIC_FORGET_ARGS   arguments for `restic forget`; empty skips retention
#   BACKUP_PATH          what to back up (default /data)
#   BACKUP_LOG           restic output of the last run (default /var/log/backup-last.log)
#
# Exit status: 0 when backup and forget succeeded, otherwise the first failing
# restic status. restic exits 3 when it saved a snapshot but could not read
# some files. That counts as a failure here, as it did with lobaro.

set -u

BACKUP_PATH="${BACKUP_PATH:-/data}"
BACKUP_LOG="${BACKUP_LOG:-/var/log/backup-last.log}"

start="$(date +%s)"
echo "Starting Backup at $(date +"%Y-%m-%d %H:%M:%S")"
echo "Starting Backup at $(date)" > "$BACKUP_LOG"

# RESTIC_JOB_ARGS is deliberately unquoted so it can carry several arguments.
# shellcheck disable=SC2086
restic backup "$BACKUP_PATH" ${RESTIC_JOB_ARGS:-} >> "$BACKUP_LOG" 2>&1
rc=$?
echo "Finished backup at $(date)" >> "$BACKUP_LOG"
if [ "$rc" -eq 0 ]; then
    echo "Backup Successful"
else
    echo "Backup Failed with Status ${rc}"
    restic unlock >> "$BACKUP_LOG" 2>&1
fi

if [ "$rc" -eq 0 ] && [ -n "${RESTIC_FORGET_ARGS:-}" ]; then
    echo "Forget about old snapshots based on RESTIC_FORGET_ARGS = ${RESTIC_FORGET_ARGS}"
    # shellcheck disable=SC2086
    restic forget ${RESTIC_FORGET_ARGS} >> "$BACKUP_LOG" 2>&1
    frc=$?
    echo "Finished forget at $(date)" >> "$BACKUP_LOG"
    if [ "$frc" -eq 0 ]; then
        echo "Forget Successful"
    else
        echo "Forget Failed with Status ${frc}"
        restic unlock >> "$BACKUP_LOG" 2>&1
        rc="$frc"
    fi
fi

end="$(date +%s)"
echo "Finished Backup at $(date +"%Y-%m-%d %H:%M:%S") after $((end - start)) seconds"
exit "$rc"
