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
# Usage: shopware-worker.sh [--dry-run|--help]

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

SERVICE="${SERVICE:-shopware}"
CONSOLE="${CONSOLE:-php bin/console}"
# Under the minute the cron gives us, leaving a few seconds so the run ends
# before the next one starts rather than being skipped by flock.
TIME_LIMIT="${SHOPWARE_WORKER_TIME_LIMIT:-25}"
MEMORY_LIMIT="${SHOPWARE_WORKER_MEMORY_LIMIT:-256M}"
# `failed` is consumed too. Shopware's documentation warns that without it a
# failed message is never retried and sits in that transport forever.
TRANSPORTS="${SHOPWARE_WORKER_TRANSPORTS:-async low_priority failed}"

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
  SHOPWARE_WORKER_TIME_LIMIT     seconds per step (default: 25)
  SHOPWARE_WORKER_MEMORY_LIMIT   consumer memory limit (default: 256M)
  SHOPWARE_WORKER_TRANSPORTS     transports to consume (default: async low_priority failed)
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

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    if (( DRY_RUN )); then
        echo "Container:    $SERVICE"
        echo "Running:      $(docker inspect -f '{{.State.Running}}' "$SERVICE" 2>/dev/null || echo 'NOT FOUND')"
        echo "Console:      $CONSOLE"
        echo "Time limit:   ${TIME_LIMIT}s per step"
        echo "Memory limit: $MEMORY_LIMIT"
        echo "Transports:   $TRANSPORTS"
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

    run_console "scheduled tasks" scheduled-task:run --time-limit="$TIME_LIMIT"

    # shellcheck disable=SC2086
    run_console "queue consumer" messenger:consume $TRANSPORTS \
        --time-limit="$TIME_LIMIT" --memory-limit="$MEMORY_LIMIT"
}

main "$@"
