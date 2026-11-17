#!/usr/bin/env bash
#
# Check that the sandbox accounts (docs/sandbox.md) stay cut off from the rest of the host.
#
# A sandbox account runs a rootless Docker daemon whose network leaves through slirp4netns, a process
# of that account in the host's network namespace. The firewall's SANDBOX-OUT chain keeps it off
# loopback and the Docker bridges, and prepare-host closed the stack's data to "other". This probes
# both as each sandbox account, so a lost firewall rule or a data directory created world-readable
# shows up within the hour. vps-health.sh runs it every hour as "sandbox" and
# security-recheck.sh --host as "sandbox:host".
#
# It prints one line "STATUS<TAB>message" and exits 0 for every status, 2 for a usage error.
#   CRIT  a git-ignored path or .git of COMPOSE_DIR grants "other" any bit (also without a sandbox
#         account); a sandbox home is not mode 700; a sandbox account connects to a port of
#         SANDBOX_CLOSED_TCP or to a container of SANDBOX_CONTAINER_PROBES, or can read, enter or
#         write a path of SANDBOX_PRIVATE_PATHS
#   WARN  a sandbox account cannot reach SANDBOX_OPEN_TCP, which means a broken probe or no egress
#         rather than a breach
# It prints account names, paths and addresses only.
#
# Usage, on the host as root:
#   monitoring/sandbox-check.sh
#   monitoring/sandbox-check.sh --help
#
# Environment:
#   SANDBOX_GROUP              the group of sandbox accounts (default sandbox)
#   SANDBOX_CLOSED_TCP         HOST:PORT a sandbox must not reach (default: every loopback listener
#                              measured 2026-11-17, and ssh on the public name)
#   SANDBOX_CONTAINER_PROBES   CONTAINER:PORT of the root daemon a sandbox must not reach
#   SANDBOX_OPEN_TCP           HOST:PORT a sandbox must reach, the positive control
#   SANDBOX_PRIVATE_PATHS      paths a sandbox must not read, enter or write
#   PROBE_TIMEOUT              seconds per connection attempt (default 2)

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SANDBOX_CLOSED_TCP="${SANDBOX_CLOSED_TCP:-127.0.0.1:25 127.0.0.1:2019 127.0.0.1:2201 127.0.0.1:2202 127.0.0.1:2211 127.0.0.1:8000 127.0.0.1:8001 127.0.0.1:8002 127.0.0.1:8006 127.0.0.1:8007 127.0.0.1:8008 ::1:25 ::1:2201 sdwa5.org:22}"
SANDBOX_CONTAINER_PROBES="${SANDBOX_CONTAINER_PROBES:-shopware_db:3306 vaultwarden:80}"
SANDBOX_OPEN_TCP="${SANDBOX_OPEN_TCP:-sdwa5.org:443 1.1.1.1:443}"
SANDBOX_PRIVATE_PATHS="${SANDBOX_PRIVATE_PATHS:-$COMPOSE_DIR/.env $COMPOSE_DIR/secrets $COMPOSE_DIR/vaultwarden-data $COMPOSE_DIR/paperless-home-media $COMPOSE_DIR/database-backup /root /var/lib/docker /var/run/docker.sock}"
PROBE_TIMEOUT="${PROBE_TIMEOUT:-2}"

crit=()
warn=()

usage() {
    sed -n '/^# Usage/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# can_connect USER HOST PORT: true when USER opens a TCP connection to HOST:PORT.
can_connect() {
    # shellcheck disable=SC2016 # $1 and $2 expand in the probe shell, not here
    as_sandbox "$1" timeout "$PROBE_TIMEOUT" /bin/bash -c 'exec 3<>"/dev/tcp/$1/$2"' probe "$2" "$3" \
        >/dev/null 2>&1
}

# The first IP address of a root-daemon container, empty when it has none.
container_ip() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" 2>/dev/null \
        | awk '{ print $1 }'
}

check_private_data() {
    local open_paths
    open_paths="$(open_private_paths | paste -sd ' ' -)"
    if [[ -n "$open_paths" ]]; then
        crit+=("open to others: $open_paths")
    fi
}

check_sandbox() {
    local user="$1"
    local home
    local mode
    local entry
    local ip
    local path
    local test_flag

    home="$(getent passwd "$user" | cut -d: -f6)"
    mode="$(stat -c '%a' "$home" 2>/dev/null)"
    [[ "$mode" == 700 ]] || crit+=("$user: home ${home:-?} has mode ${mode:-missing}, not 700")

    for entry in $SANDBOX_CLOSED_TCP; do
        if can_connect "$user" "${entry%:*}" "${entry##*:}"; then
            crit+=("$user reaches $entry")
        fi
    done
    for entry in $SANDBOX_CONTAINER_PROBES; do
        ip="$(container_ip "${entry%:*}")"
        [[ -n "$ip" ]] || continue
        if can_connect "$user" "$ip" "${entry##*:}"; then
            crit+=("$user reaches ${entry%:*} at $ip:${entry##*:}")
        fi
    done
    for path in $SANDBOX_PRIVATE_PATHS; do
        for test_flag in -r -x -w; do
            if as_sandbox "$user" /usr/bin/test "$test_flag" "$path" 2>/dev/null; then
                crit+=("$user passes test $test_flag $path")
            fi
        done
    done
    for entry in $SANDBOX_OPEN_TCP; do
        if ! can_connect "$user" "${entry%:*}" "${entry##*:}"; then
            warn+=("$user cannot reach $entry")
        fi
    done
}

main() {
    local members
    local user
    local count=0

    case "${1:-}" in
        --help|-h) usage; return 0 ;;
        '') ;;
        *) usage >&2; return 2 ;;
    esac

    check_private_data
    members="$(sandbox_members 2>/dev/null)"
    for user in $members; do
        check_sandbox "$user"
        count=$((count + 1))
    done

    if (( ${#crit[@]} )); then
        printf 'CRIT\t%s\n' "$(printf '%s; ' "${crit[@]}" | sed 's/; $//')"
    elif (( ${#warn[@]} )); then
        printf 'WARN\t%s\n' "$(printf '%s; ' "${warn[@]}" | sed 's/; $//')"
    elif (( count == 0 )); then
        printf 'OK\tno sandbox accounts; private data closed\n'
    else
        printf 'OK\t%s sandbox(es): no host loopback, no container network, no private path\n' "$count"
    fi
}

main "$@"
