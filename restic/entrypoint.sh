#!/bin/sh
#
# Entrypoint of the restic service. Schedules restic/backup.sh with crond and
# keeps crond in the foreground, so the container lives as long as the schedule.
#
# The image is creativeprojects/resticprofile, used only for the restic, rclone,
# crond and flock it ships. resticprofile itself is not used. Until 2026-10-15
# the service ran lobaro/restic-backup-docker, whose last build was 2021 and
# carried restic 0.12.0. This script and backup.sh replace its /entry.sh and
# /bin/backup and keep their log lines, which monitoring/vps-health.sh reads.
#
# Unlike lobaro's entry script this one never runs `restic init`. lobaro
# initialised a new repository whenever `restic snapshots` failed, so a
# transient Drive or token error at start-up could point the schedule at an
# empty repository. Here a missing repository makes the first backup fail
# loudly instead.
#
# Environment:
#   BACKUP_CRON    cron expression, container time (UTC, no TZ is set)
#   CRONTAB_DIR    where crond reads crontabs (default /var/spool/cron/crontabs)
#   CROND          crond binary (default crond), replaceable for the tests
#
# Busybox crond hands its own environment to every job, so RESTIC_REPOSITORY,
# RESTIC_PASSWORD and the rest reach backup.sh without being written anywhere.

set -eu

: "${BACKUP_CRON:?BACKUP_CRON must be set, for example \"0 4 * * *\"}"
CRONTAB_DIR="${CRONTAB_DIR:-/var/spool/cron/crontabs}"
CROND="${CROND:-crond}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$CRONTAB_DIR"
# The job writes to PID 1's stdout, which is the container log. With
# `init: true` PID 1 is docker-init, whose stdout is that same log.
printf '%s /usr/bin/flock -n /var/run/backup.lock /bin/sh %s/backup.sh > /proc/1/fd/1 2>&1\n' \
    "$BACKUP_CRON" "$SCRIPT_DIR" > "$CRONTAB_DIR/root"

echo "Setup backup cron job with cron expression BACKUP_CRON: ${BACKUP_CRON}"
echo "Container started."
exec "$CROND" -f -l 8
