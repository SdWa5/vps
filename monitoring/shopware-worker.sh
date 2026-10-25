#!/usr/bin/env bash
#
# Runs Shopware's scheduled tasks and consumes its message queue.
#
# Shopware needs a process to do both. Without one its scheduled tasks simply
# stop, and nothing says so. Measured on 2026-09-08: nothing had run since
# 2026-07-23, so every task's next execution was 47 days in the past,
# shopware.invalidate_cache was dead on a 300-second interval, every cleanup
# task was dead, the sitemap's lastmod was frozen at 2026-07-22 and 9 messages
# sat unconsumed. There was no host cron entry, no container crontab entry
# beyond Debian's own, no worker process and no worker service in the compose
# file. The likely mechanism was Shopware's admin worker, which only runs tasks
# while somebody has the administration open in a browser.
#
# This is the CLI worker Shopware's own documentation asks for, and
# shopware-html-data/config/packages/shopware.yaml turns the admin worker off so
# the two do not both run.
#
# Runs every minute from /etc/cron.d/shopware-worker under `flock -n`. The lock
# is not decoration: Shopware's documentation warns that cron-driven workers
# pile up, because cron does not wait for the previous run and a message that
# outlives the time limit keeps its worker alive. `flock -n` makes a run whose
# predecessor is still going exit immediately instead.
#
# Silent when it works. One mail when it does not, because an all-green digest
# every minute trains the recipient to ignore the mail.
#
# A database that has just started gets a grace period. Measured on 2026-10-15,
# when the VPS rebooted at 02:26: both shop containers were up at 02:27, the
# worker ran at 02:27:15, and mysqld inside the dockware images of that time only
# started at 02:27:43 and 02:27:56, so both shops mailed `Connection refused`
# although nothing was broken. Since SEC-31 the sdwa5.org shop's database is its
# own container, shopware_db, while a dockware shop such as Chimo Diazz still
# runs its database inside the shop container and sets
# SHOPWARE_WORKER_DB_CONTAINER to that container. Inside the grace period after
# the database container's start, a run whose database does not answer yet exits
# quietly. Outside it nothing changes, so a real outage right after a start stays
# silent for at most SHOPWARE_WORKER_BOOT_GRACE seconds.
#
# Usage: shopware-worker.sh [--dry-run|--help]

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

SERVICE="${SERVICE:-shopware}"
DB_CONTAINER="${SHOPWARE_WORKER_DB_CONTAINER:-shopware_db}"
CONSOLE="${CONSOLE:-php bin/console}"
# Under the minute the cron gives us, leaving a few seconds so the run ends
# before the next one starts rather than being skipped by flock.
TIME_LIMIT="${SHOPWARE_WORKER_TIME_LIMIT:-25}"
MEMORY_LIMIT="${SHOPWARE_WORKER_MEMORY_LIMIT:-256M}"
# `failed` is consumed too. Shopware's documentation warns that without it a
# failed message is never retried and sits in that transport forever.
TRANSPORTS="${SHOPWARE_WORKER_TRANSPORTS:-async low_priority failed}"
# Matches the healthcheck's start_period in docker-compose.yml.
BOOT_GRACE="${SHOPWARE_WORKER_BOOT_GRACE:-300}"
# mysqladmin exits 0 whenever the server answers, even with "Access denied", so
# the ping needs no credentials. Over TCP, because www-data could not open the
# socket in dockware. Measured on both dockware containers on 2026-10-16: 0
# against the server, 1 against a closed port.
DB_PING="${SHOPWARE_WORKER_DB_PING:-mysqladmin --no-defaults -h 127.0.0.1 --connect-timeout=3 ping}"

DRY_RUN=0

usage() {
    cat <<'USAGE'
shopware-worker.sh - run Shopware's scheduled tasks and consume its queue

Runs every minute from /etc/cron.d/shopware-worker under flock. Silent on
success, one mail on failure.

Usage:
  shopware-worker.sh            run both steps
  shopware-worker.sh --dry-run  report what would run, change nothing
  shopware-worker.sh --help     this text

Environment overrides (also honoured from the compose .env):
  SERVICE                        container name (default: shopware)
  SHOPWARE_WORKER_DB_CONTAINER   database container (default: shopware_db);
                                 a dockware shop names its own container
  SHOPWARE_WORKER_TIME_LIMIT     seconds per step (default: 25)
  SHOPWARE_WORKER_MEMORY_LIMIT   consumer memory limit (default: 256M)
  SHOPWARE_WORKER_TRANSPORTS     transports to consume (default: async low_priority failed)
  SHOPWARE_WORKER_BOOT_GRACE     seconds after a database start in which a
                                 database that does not answer yet is no
                                 failure (default: 300)
USAGE
}

fail() {
    local subject="$1" body="$2"
    send_mail "[sdwa5] $subject" "$body" || log "$subject"
    exit 1
}

# Run one console command inside the container. Output is captured so a success
# stays silent and a failure can be mailed with its reason attached.
run_console() {
    local label="$1"
    shift

    local out rc
    # CONSOLE is "php bin/console" and has to split into two arguments, so the
    # word splitting here is the point rather than an oversight.
    # shellcheck disable=SC2086
    out="$(docker exec "$SERVICE" $CONSOLE "$@" 2>&1)"
    rc=$?

    if (( rc != 0 )); then
        fail "Shopware $label failed on $(hostname)" \
"$CONSOLE $* exited $rc in container $SERVICE.

$out

Check: docker ps --filter name=$SERVICE; docker exec $SERVICE $CONSOLE $*"
    fi

    log "$label ok"
}

# Seconds since the database container started, or nothing when that cannot be
# read. The database is what boots slowly, and a restarted shop container alone
# answers at once. An unreadable start time counts as old, so the doubt ends in
# a mail rather than in silence.
container_age() {
    local started epoch
    started="$(docker inspect -f '{{.State.StartedAt}}' "$DB_CONTAINER" 2>/dev/null)" || return 0
    epoch="$(date -d "$started" +%s 2>/dev/null)" || return 0
    echo $(( $(date +%s) - epoch ))
}

database_answers() {
    # shellcheck disable=SC2086
    docker exec "$DB_CONTAINER" $DB_PING >/dev/null 2>&1
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    if (( DRY_RUN )); then
        echo "Container:    $SERVICE"
        echo "Database:     $DB_CONTAINER"
        echo "Running:      $(docker inspect -f '{{.State.Running}}' "$SERVICE" 2>/dev/null || echo 'NOT FOUND')"
        echo "Console:      $CONSOLE"
        echo "Time limit:   ${TIME_LIMIT}s per step"
        echo "Memory limit: $MEMORY_LIMIT"
        echo "Transports:   $TRANSPORTS"
        echo "Boot grace:   ${BOOT_GRACE}s after a database start"
        echo "Would run:    scheduled-task:run --time-limit=$TIME_LIMIT"
        echo "Would run:    messenger:consume $TRANSPORTS --time-limit=$TIME_LIMIT --memory-limit=$MEMORY_LIMIT"
        exit 0
    fi

    if ! docker inspect -f '{{.State.Running}}' "$SERVICE" 2>/dev/null | grep -q true; then
        fail "Shopware container $SERVICE is not running on $(hostname)" \
"shopware-worker.sh cannot run the scheduled tasks or consume the queue while
the container is down, so both stop silently until it is back.

Check: docker ps -a --filter name=$SERVICE"
    fi

    local age
    age="$(container_age)"
    if [[ -n "$age" ]] && (( age < BOOT_GRACE )) && ! database_answers; then
        log "database $DB_CONTAINER not answering ${age}s after start, inside the ${BOOT_GRACE}s grace period; skipped"
        exit 0
    fi

    run_console "scheduled tasks" scheduled-task:run --time-limit="$TIME_LIMIT"

    # shellcheck disable=SC2086
    run_console "queue consumer" messenger:consume $TRANSPORTS \
        --time-limit="$TIME_LIMIT" --memory-limit="$MEMORY_LIMIT"
}

main "$@"
