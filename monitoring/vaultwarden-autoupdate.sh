#!/usr/bin/env bash
#
# Daily Vaultwarden update.
#
# Bitwarden browser extensions and mobile apps auto-update from the stores. A
# server left behind stops working with them while the bundled web vault keeps
# going, which is exactly the September 2026 outage. This job removes that drift.
#
# Only Vaultwarden is updated. Shopware, Dolibarr and MariaDB stay manual.
#
# Runs from /etc/cron.d/vaultwarden-autoupdate daily at 03:00 host time, which is
# 01:00 UTC, so it lands before the consistent database copy at 01:50 UTC and the
# restic backup at 04:00 UTC. Every snapshot therefore holds the post-update state.
# The three schedules live in two timezones, so that ordering only reads correctly
# in UTC.
#
# It was weekly until 2026-09-14, and weekly could not keep up. 1.37.3 was
# published fourteen hours after that week's run, so the server would have stayed
# behind the Bitwarden clients until the following Sunday while the hourly health
# check mailed about it.
#
# Usage:
#   vaultwarden-autoupdate.sh              pull, snapshot, update, verify
#   vaultwarden-autoupdate.sh --dry-run    report what would happen, change nothing
#   vaultwarden-autoupdate.sh --help

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

SERVICE="${SERVICE:-vaultwarden}"
IMAGE="${IMAGE:-vaultwarden/server:latest}"
DATA_DIR="${DATA_DIR:-$COMPOSE_DIR/vaultwarden-data}"
HEALTH_URL="${HEALTH_URL:-https://vault.sdwa5.org/alive}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
SNAPSHOTS_TO_KEEP="${SNAPSHOTS_TO_KEEP:-3}"
# vps-health.sh runs hourly. Anything older than this means it stopped.
HEALTH_STALE_SECONDS="${HEALTH_STALE_SECONDS:-7200}"
# **THIS JOB BECAME DAILY AND THIS ALARM HAS NO BACKOFF OF ITS OWN, SO IT NEEDED A LIMIT.**
# While the job ran weekly, a dead vps-health.sh cost one mail a week. Daily would make it one a day
# for as long as the condition lasts, which is exactly the "mails every day forever" that
# vps-health.sh's own reminder schedule exists to prevent. Seven days keeps the old cadence while the
# detection window drops from a week to a day.
HEALTH_ALERT_INTERVAL_SECONDS="${HEALTH_ALERT_INTERVAL_SECONDS:-604800}"
HEALTH_ALERT_STAMP="${HEALTH_ALERT_STAMP:-$STATE_DIR/autoupdate-health-alerted}"

DRY_RUN=0

image_id() {
    docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null
}

# The container prints "Vaultwarden <server>" and "Web-Vault <web vault>".
# Only the first one is the release version.
running_version() {
    docker exec "$SERVICE" /vaultwarden --version 2>/dev/null \
        | grep -oE '^Vaultwarden [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}'
}

# True at most once per HEALTH_ALERT_INTERVAL_SECONDS. The stamp is written only when a mail actually
# went out, so a failed delivery does not silence the next attempt.
health_alert_due() {
    local last

    [[ -f "$HEALTH_ALERT_STAMP" ]] || return 0
    last="$(stat -c %Y "$HEALTH_ALERT_STAMP" 2>/dev/null)" || return 0
    (( $(now) - last >= HEALTH_ALERT_INTERVAL_SECONDS ))
}

# Records that the alarm was delivered, so the next run can hold off. mtime is the payload, and it is
# set explicitly rather than left to touch's idea of now, because FAKE_NOW drives this in tests.
mark_health_alert_sent() {
    mkdir -p "$(dirname "$HEALTH_ALERT_STAMP")" 2>/dev/null
    : > "$HEALTH_ALERT_STAMP"
    touch -d "@$(now)" "$HEALTH_ALERT_STAMP" 2>/dev/null
}

# The two cron jobs watch each other. Without an all-green digest, a health
# script that silently stopped running looks exactly like a healthy server, so
# this job reports the silence instead.
#
# The condition is re-evaluated every run and only the *mail* is rate limited, so recovery is noticed
# at once: once vps-health.sh writes its stamp again, this returns without touching anything and the
# next failure alerts immediately rather than waiting out the old interval.
check_health_monitor() {
    local age

    if [[ ! -f "$LAST_RUN_FILE" ]]; then
        health_alert_due || return
        if send_mail "[sdwa5] health monitoring has never run" \
"vaultwarden-autoupdate.sh could not find $LAST_RUN_FILE on $(hostname).

vps-health.sh has never completed a run, so nothing is watching disk space,
containers, backups or Vaultwarden version drift.

This alarm repeats at most every $(( HEALTH_ALERT_INTERVAL_SECONDS / 86400 )) days.

Check: systemctl status cron; cat /etc/cron.d/vps-health"; then
            mark_health_alert_sent
        else
            log "health monitoring has never run"
        fi
        return
    fi

    age=$(( $(now) - $(stat -c %Y "$LAST_RUN_FILE") ))
    if (( age < HEALTH_STALE_SECONDS )); then
        rm -f "$HEALTH_ALERT_STAMP"
        return
    fi

    health_alert_due || return

    if send_mail "[sdwa5] health monitoring has stopped" \
"vps-health.sh on $(hostname) last completed $(( age / 3600 ))h ago, at $(cat "$LAST_RUN_FILE").
It runs hourly, so it has stopped.

Nothing is watching disk space, containers, backups or Vaultwarden version drift.

This alarm repeats at most every $(( HEALTH_ALERT_INTERVAL_SECONDS / 86400 )) days.

Check: systemctl status cron; cat /etc/cron.d/vps-health; /opt/docker/monitoring/vps-health.sh --dry-run"; then
        mark_health_alert_sent
    else
        log "health monitoring has stopped"
    fi
}

snapshot() {
    local dir
    dir="${DATA_DIR}.bak-$(date +%Y%m%d-%H%M)"
    cp -a "$DATA_DIR" "$dir" || return 1
    echo "$dir"
}

prune_snapshots() {
    local old
    # shellcheck disable=SC2012
    old="$(ls -1dt "${DATA_DIR}".bak-* 2>/dev/null | tail -n +$(( SNAPSHOTS_TO_KEEP + 1 )))"
    [[ -z "$old" ]] && return 0
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && rm -rf "$dir" && log "Pruned old snapshot $dir"
    done <<< "$old"
}

wait_for_health() {
    local waited=0 code
    while (( waited < HEALTH_TIMEOUT )); do
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null)"
        [[ "$code" == "200" ]] && return 0
        sleep 5
        waited=$(( waited + 5 ))
    done
    return 1
}

# Roll back to the image that was running before, and to the data directory as
# it was. Vaultwarden migrations are forward-only, so the snapshot is the only
# way back.
rollback() {
    local previous_image="$1" snapshot_dir="$2"

    log "Rolling back to $previous_image"

    cat > "$COMPOSE_DIR/docker-compose.override.yml" <<OVERRIDE
# Written by monitoring/vaultwarden-autoupdate.sh after a failed update.
# Remove this file once the problem is understood, otherwise Vaultwarden stays
# pinned to an old image and will drift behind the Bitwarden clients again.
version: '3.9'
services:
  $SERVICE:
    image: $previous_image
OVERRIDE

    ( cd "$COMPOSE_DIR" && $DOCKER_COMPOSE stop "$SERVICE" ) >&2
    rm -rf "$DATA_DIR"
    cp -a "$snapshot_dir" "$DATA_DIR"
    ( cd "$COMPOSE_DIR" && $DOCKER_COMPOSE up -d "$SERVICE" ) >&2
}

usage() {
    cat <<'USAGE'
vaultwarden-autoupdate.sh - daily Vaultwarden update

Pulls vaultwarden/server:latest. If the image is unchanged, exits silently.
Otherwise snapshots vaultwarden-data/, recreates the container and verifies that
the public /alive endpoint answers 200. On failure it restores the snapshot, pins
the previous image in docker-compose.override.yml and mails an alert.

Also verifies that vps-health.sh is still running, and mails if it has stopped.
That alarm repeats at most every 7 days for as long as the condition lasts.

  vaultwarden-autoupdate.sh              pull, snapshot, update, verify
  vaultwarden-autoupdate.sh --dry-run    report what would happen, change nothing
  vaultwarden-autoupdate.sh --help       this text
USAGE
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    (( DRY_RUN )) || check_health_monitor

    local before after old_version new_version snapshot_dir
    before="$(image_id)"
    old_version="$(running_version)"

    if (( DRY_RUN )); then
        echo "Service:          $SERVICE"
        echo "Image:            $IMAGE"
        echo "Local image ID:   ${before:-none}"
        echo "Running version:  ${old_version:-unknown}"
        echo "Data dir:         $DATA_DIR"
        echo "Health URL:       $HEALTH_URL"
        echo "Would run:        $DOCKER_COMPOSE pull $SERVICE, then compare image IDs"
        exit 0
    fi

    if ! ( cd "$COMPOSE_DIR" && $DOCKER_COMPOSE pull "$SERVICE" ) >&2; then
        send_mail "[sdwa5] Vaultwarden update: pull failed" \
"docker-compose pull $SERVICE failed on $(hostname). Vaultwarden is untouched and still running $old_version." \
            || log "pull failed"
        exit 1
    fi

    after="$(image_id)"
    if [[ "$before" == "$after" ]]; then
        log "Vaultwarden $old_version is already the latest image, nothing to do"
        exit 0
    fi

    log "New image pulled, snapshotting $DATA_DIR"
    if ! snapshot_dir="$(snapshot)"; then
        send_mail "[sdwa5] Vaultwarden update aborted: snapshot failed" \
"Could not copy $DATA_DIR on $(hostname). The update was not applied, Vaultwarden still runs $old_version." \
            || log "snapshot failed"
        exit 1
    fi

    ( cd "$COMPOSE_DIR" && $DOCKER_COMPOSE up -d "$SERVICE" ) >&2

    if ! wait_for_health; then
        rollback "$before" "$snapshot_dir"
        send_mail "[sdwa5] Vaultwarden update FAILED, rolled back" \
"The new $IMAGE image did not become healthy within ${HEALTH_TIMEOUT}s on $(hostname).

$HEALTH_URL never returned 200.

Rolled back to image $before and restored the data directory from $snapshot_dir.
Vaultwarden is pinned in docker-compose.override.yml. Remove that file once the
problem is understood, otherwise the server drifts behind the Bitwarden clients
again and the extension will stop working.

Logs: docker logs vaultwarden" \
            || log "update failed and was rolled back"
        exit 1
    fi

    new_version="$(running_version)"
    prune_snapshots

    log "Vaultwarden updated from ${old_version:-unknown} to ${new_version:-unknown}"
    send_mail "[sdwa5] Vaultwarden updated to ${new_version:-unknown}" \
"Vaultwarden on $(hostname) was updated from ${old_version:-unknown} to ${new_version:-unknown}.

$HEALTH_URL returned 200 after the restart.
Snapshot of the previous data directory: $snapshot_dir (newest $SNAPSHOTS_TO_KEEP are kept).

If the browser extension or the mobile app misbehaves after this, log out inside
the client and log back in. A stale session can survive a server version jump." \
        || log "update succeeded, mail failed"
}

main "$@"
