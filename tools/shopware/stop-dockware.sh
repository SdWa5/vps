#!/usr/bin/env bash
#
# Stop a dockware container without leaving an unclean InnoDB behind.
#
# dockware's entrypoint ignores SIGTERM, so `docker stop` waits for its timeout
# and then kills the container's MySQL (exit 137). After the host power-off of
# 2026-10-18 the Chimo Diazz shop's crash recovery outran the init script's 30 s
# and the container restarted 16 times. `service mysql stop` inside the
# container failed as well (measured 2026-10-15). This sends SIGTERM to mysqld
# from the host, waits until the process is gone, requires "Shutdown complete"
# in the MySQL error log and only then stops the container.
#
# A container that is not running is left alone. On a timeout or a missing log
# line the container keeps running, so nothing is killed half-way.
#
# Usage, on the host as root:
#   tools/shopware/stop-dockware.sh CONTAINER
#   STOP_TIMEOUT=300 tools/shopware/stop-dockware.sh CONTAINER

set -uo pipefail

STOP_TIMEOUT="${STOP_TIMEOUT:-120}"

usage() {
    sed -n '/^# Usage/,/^# *STOP_TIMEOUT/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Prints the host PID of the container's mysqld, or nothing.
mysqld_pid() {
    docker top "$1" -eo pid,comm | awk '$2 == "mysqld" { print $1; exit }'
}

main() {
    local container pid waited=0
    case "${1:-}" in
        --help|-h) usage; return 0 ;;
        '') usage >&2; return 2 ;;
    esac
    container="$1"
    [[ "$container" =~ ^[a-z0-9_]+$ ]] || { printf 'Invalid container name.\n' >&2; return 2; }
    [[ $# -eq 1 ]] || { printf 'Unknown option.\n' >&2; return 2; }
    [[ "$STOP_TIMEOUT" =~ ^[0-9]+$ ]] || { printf 'STOP_TIMEOUT must be a number of seconds.\n' >&2; return 2; }

    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true* ]]; then
        printf '%s is not running, nothing to stop.\n' "$container"
        return 0
    fi

    pid="$(mysqld_pid "$container")"
    if [[ -n "$pid" ]]; then
        kill -TERM "$pid" || { printf 'Could not signal mysqld (PID %s).\n' "$pid" >&2; return 1; }
        while kill -0 "$pid" 2>/dev/null; do
            if (( waited >= STOP_TIMEOUT )); then
                printf 'mysqld (PID %s) still runs after %s s; %s keeps running.\n' \
                    "$pid" "$STOP_TIMEOUT" "$container" >&2
                return 1
            fi
            sleep 1
            waited=$((waited + 1))
        done
        printf 'mysqld stopped after %s s.\n' "$waited"
    else
        printf 'No mysqld runs in %s.\n' "$container"
    fi

    # The last lines must hold the shutdown marker, also when mysqld was already
    # down, because a crashed server leaves no such line.
    if ! docker exec -u root "$container" tail -n 50 /var/log/mysql/error.log | grep -q 'Shutdown complete'; then
        printf 'No "Shutdown complete" in the MySQL error log; %s keeps running.\n' "$container" >&2
        return 1
    fi
    docker stop "$container" >/dev/null || { printf 'docker stop %s failed.\n' "$container" >&2; return 1; }
    printf '%s stopped with a clean MySQL shutdown.\n' "$container"
}

main "$@"
