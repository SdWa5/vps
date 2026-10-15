#!/usr/bin/env bats
# Tests for restic/backup.sh and restic/entrypoint.sh

load test_helper

setup() {
    common_setup
    export STUB_RESTIC_CALLS="$BATS_TEST_TMPDIR/restic.calls"
    export BACKUP_LOG="$BATS_TEST_TMPDIR/backup-last.log"
    export BACKUP_PATH=/data
    export RESTIC_FORGET_ARGS="--keep-daily 6 --prune"
    unset RESTIC_JOB_ARGS
    : > "$STUB_RESTIC_CALLS"
}

restic_backup() {
    run sh "$REPO_ROOT/restic/backup.sh"
}

@test "a successful run backs up, forgets and logs what vps-health greps for" {
    restic_backup
    [ "$status" -eq 0 ]
    [[ "$output" == *"Backup Successful"* ]]
    [[ "$output" == *"Forget Successful"* ]]
    grep -qx 'backup /data' "$STUB_RESTIC_CALLS"
    grep -qx 'forget --keep-daily 6 --prune' "$STUB_RESTIC_CALLS"
}

@test "restic's own output goes to the log file, not the container log" {
    restic_backup
    [[ "$output" != *"snapshot 0123abcd saved"* ]]
    grep -q 'snapshot 0123abcd saved' "$BACKUP_LOG"
}

@test "a failed backup reports the status, unlocks and skips the retention policy" {
    export STUB_RESTIC_BACKUP_RC=1
    restic_backup
    [ "$status" -eq 1 ]
    [[ "$output" == *"Backup Failed with Status 1"* ]]
    grep -qx 'unlock' "$STUB_RESTIC_CALLS"
    ! grep -q '^forget' "$STUB_RESTIC_CALLS"
}

@test "an incomplete snapshot (exit 3) counts as a failure" {
    export STUB_RESTIC_BACKUP_RC=3
    restic_backup
    [ "$status" -eq 3 ]
    [[ "$output" == *"Backup Failed with Status 3"* ]]
}

@test "the log lines match the pattern monitoring/vps-health.sh reads" {
    export STUB_RESTIC_BACKUP_RC=1
    restic_backup
    grep -qE '^(Backup|Restic) (Successful|Failed)' <<< "$output"
}

@test "a failed forget fails the run although the backup succeeded" {
    export STUB_RESTIC_FORGET_RC=1
    restic_backup
    [ "$status" -eq 1 ]
    [[ "$output" == *"Backup Successful"* ]]
    [[ "$output" == *"Forget Failed with Status 1"* ]]
    grep -qx 'unlock' "$STUB_RESTIC_CALLS"
}

@test "empty RESTIC_FORGET_ARGS skips the retention policy" {
    export RESTIC_FORGET_ARGS=
    restic_backup
    [ "$status" -eq 0 ]
    ! grep -q '^forget' "$STUB_RESTIC_CALLS"
}

@test "RESTIC_JOB_ARGS is split into separate arguments" {
    export RESTIC_JOB_ARGS="--exclude /data/tmp --one-file-system"
    restic_backup
    grep -qx 'backup /data --exclude /data/tmp --one-file-system' "$STUB_RESTIC_CALLS"
}

@test "the entrypoint schedules backup.sh under flock and starts crond in the foreground" {
    export CRONTAB_DIR="$BATS_TEST_TMPDIR/crontabs"
    export CROND=echo
    export BACKUP_CRON="0 4 * * *"
    run sh "$REPO_ROOT/restic/entrypoint.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-f -l 8"* ]]
    grep -qx "0 4 \* \* \* /usr/bin/flock -n /var/run/backup.lock /bin/sh $REPO_ROOT/restic/backup.sh > /proc/1/fd/1 2>&1" \
        "$CRONTAB_DIR/root"
}

@test "the entrypoint refuses to start without a schedule" {
    export CRONTAB_DIR="$BATS_TEST_TMPDIR/crontabs"
    export CROND=echo
    unset BACKUP_CRON
    run sh "$REPO_ROOT/restic/entrypoint.sh"
    [ "$status" -ne 0 ]
    [ ! -e "$CRONTAB_DIR/root" ]
}

@test "the entrypoint never initialises a repository" {
    ! grep -hv '^[[:space:]]*#' "$REPO_ROOT/restic/entrypoint.sh" "$REPO_ROOT/restic/backup.sh" | grep -q 'restic init'
}

@test "the compose service runs the pinned image with these scripts" {
    grep -q 'image: creativeprojects/resticprofile:0.33.1-amd64' "$REPO_ROOT/docker-compose.yml"
    grep -q 'entrypoint: \["/bin/sh", "/opt/restic/entrypoint.sh"\]' "$REPO_ROOT/docker-compose.yml"
    grep -q -- '- ./restic:/opt/restic:ro' "$REPO_ROOT/docker-compose.yml"
}

@test "the repository goes through the service account remote, not the old OAuth remote" {
    grep -q 'RESTIC_REPOSITORY=${RESTIC_REPOSITORY:-rclone:sdwa5backup:restic-backups}' "$REPO_ROOT/docker-compose.yml"
    grep -q 'RCLONE_CONFIG_SDWA5BACKUP_SERVICE_ACCOUNT_FILE=/root/.config/rclone/restic-sa.json' "$REPO_ROOT/docker-compose.yml"
    grep -q 'RCLONE_CONFIG_SDWA5BACKUP_TEAM_DRIVE=${RESTIC_SHARED_DRIVE_ID:-}' "$REPO_ROOT/docker-compose.yml"
    ! grep -q 'rclone:SdWa5:' "$REPO_ROOT/docker-compose.yml"
}
