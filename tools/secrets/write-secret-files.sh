#!/usr/bin/env bash
#
# Writes the compose file secrets of docker-compose.yml's `secrets:` block.
#
# A secret that moves from .env to a file must keep its exact value, because
# MariaDB and Paperless read their passwords only when a database is first
# initialized and Dolibarr's conf.php and restic's repository already depend on
# them. So a moved value is copied from the running container, not from .env:
# docker inspect shows what Compose actually resolved, quoting and `$` handling
# included. Each file is then compared byte for byte with the value as the
# container's own environment shows it (`docker exec ... printenv`), which is a
# second, independent read.
#
# Files are written mode 400 into a mode 700 directory, owned by whoever runs
# this (root on the host), without a trailing newline. Paperless's init copies a
# file's bytes as they are, newline included, so a newline would change the value.
# Nothing is printed but names and results, never a value or a hash of one.
# An existing file is left alone when it already holds the value and refused
# otherwise, so a second run is harmless and nothing is overwritten.
#
# Usage, on the host from /opt/docker:
#   tools/secrets/write-secret-files.sh [--dir DIR] SPEC...
#   SPEC is NAME=CONTAINER:VARIABLE  the value VARIABLE has in CONTAINER now
#        or NAME=random              a new random value, 43 URL-safe characters
#   DIR defaults to the secrets/ directory next to docker-compose.yml.

set -euo pipefail

usage() {
    sed -n '/^# Usage/,/^#   DIR/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# config_value CONTAINER VARIABLE: the value from docker inspect, written to
# stdout without a newline. Fails when the variable is absent.
config_value() {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$1" \
        | awk -v k="$2" 'index($0, k "=") == 1 { printf "%s", substr($0, length(k) + 2); f = 1; exit }
            END { exit !f }'
}

# process_value CONTAINER VARIABLE: the same value as the container's
# environment reports it, without printenv's newline.
process_value() {
    docker exec "$1" printenv "$2" | head -c -1
}

random_value() {
    head -c 32 /dev/urandom | base64 | tr -d '\n=' | tr '+/' '-_'
}

write_one() {
    local dir="$1" spec="$2" name source container variable tmp target

    name="${spec%%=*}"
    source="${spec#*=}"
    [[ "$spec" == *=* && "$name" =~ ^[a-z0-9][a-z0-9_]*$ && -n "$source" ]] \
        || { printf 'Invalid spec %s.\n' "${spec%%=*}" >&2; return 2; }
    target="$dir/$name"
    tmp="$(mktemp "$dir/.$name.XXXXXX")"

    if [[ "$source" == random ]]; then
        if [[ -e "$target" ]]; then
            rm -f -- "$tmp"
            printf '%s: exists, left unchanged\n' "$name"
            return 0
        fi
        random_value > "$tmp"
    else
        container="${source%%:*}"
        variable="${source#*:}"
        [[ "$source" == *:* && -n "$container" && "$variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
            || { rm -f -- "$tmp"; printf 'Invalid source for %s.\n' "$name" >&2; return 2; }
        config_value "$container" "$variable" > "$tmp" \
            || { rm -f -- "$tmp"; printf '%s: %s has no %s.\n' "$name" "$container" "$variable" >&2; return 1; }
        cmp -s "$tmp" <(process_value "$container" "$variable") \
            || { rm -f -- "$tmp"; printf '%s: the two reads of %s in %s differ, nothing written.\n' "$name" "$variable" "$container" >&2; return 1; }
    fi
    [[ -s "$tmp" ]] || { rm -f -- "$tmp"; printf '%s: the value is empty, nothing written.\n' "$name" >&2; return 1; }

    if [[ -e "$target" ]]; then
        if cmp -s "$tmp" "$target"; then
            rm -f -- "$tmp"
            printf '%s: already holds the value\n' "$name"
            return 0
        fi
        rm -f -- "$tmp"
        printf '%s: exists with a different value, not overwritten.\n' "$name" >&2
        return 1
    fi
    chmod 400 "$tmp"
    mv -- "$tmp" "$target"
    if [[ "$source" == random ]]; then
        printf '%s: written, new random value\n' "$name"
    else
        printf '%s: written, matches %s %s\n' "$name" "$container" "$variable"
    fi
}

main() {
    local dir spec rc=0

    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/secrets"
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        --dir) dir="${2:?--dir needs a directory}"; shift 2 ;;
    esac
    (( $# )) || { usage >&2; return 2; }

    umask 077
    mkdir -p -- "$dir"
    chmod 700 "$dir"
    for spec in "$@"; do
        write_one "$dir" "$spec" || rc=$?
    done
    return "$rc"
}

main "$@"
