#!/usr/bin/env bash
#
# Set the MariaDB root password of one compose service back to the value its
# MYSQL_ROOT_PASSWORD (or MARIADB_ROOT_PASSWORD) carries.
#
# The image applies that variable only when it initialises an empty datadir, so
# a later change in .env never reaches the database. The ERP's root login failed
# that way, measured 2026-10-14. This starts a throwaway container of the same
# service on the stopped datadir, with grants off and networking off, sets the
# password of every existing root account, and proves it with a root login
# before it shuts down. It creates no account and never prints the password.
#
# The service must be stopped first, because two servers on one datadir corrupt
# it. Downtime is the time this runs, ca. 1 minute.
#
# Usage, on the host from /opt/docker (`docker-compose` where Compose v2 is missing):
#   docker compose stop SERVICE
#   tools/mariadb/reset-root-password.sh SERVICE
#   docker compose up -d SERVICE

set -uo pipefail

# shellcheck source=tools/compose.sh
. "$(dirname "${BASH_SOURCE[0]}")/../compose.sh"

usage() {
    sed -n '/^# Usage/,/^# *docker compose up/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local service id output status
    case "${1:-}" in
        --help|-h) usage; return 0 ;;
        '') usage >&2; return 2 ;;
    esac
    service="$1"
    [[ "$service" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { printf 'Invalid service name.\n' >&2; return 2; }
    [[ $# -eq 1 ]] || { printf 'Unknown option.\n' >&2; return 2; }

    id="$($DOCKER_COMPOSE ps -q "$service")" || { printf 'The service could not be listed.\n' >&2; return 1; }
    if [[ -n "$id" && "$(docker inspect -f '{{.State.Running}}' "$id")" == true* ]]; then
        printf 'Stop %s first: %s stop %s\n' "$service" "$DOCKER_COMPOSE" "$service" >&2
        return 1
    fi
    # The success line is required, because a run that never received the
    # script on stdin would exit 0 without having done anything.
    output="$($DOCKER_COMPOSE run --rm --no-deps -T --entrypoint bash "$service" -s \
        < "$(dirname "${BASH_SOURCE[0]}")/reset-root-password.inner.sh" 2>&1)"
    status=$?
    [[ -z "$output" ]] || printf '%s\n' "$output"
    if (( status != 0 )) || [[ "$output" != *'verified with a login.'* ]]; then
        printf 'The root password was not reset.\n' >&2
        return 1
    fi
}

main "$@"
