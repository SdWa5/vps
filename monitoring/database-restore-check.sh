#!/usr/bin/env bash

set -euo pipefail
umask 077

MONITORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$MONITORING_DIR")}"
DATABASE_BACKUP_DIR="${DATABASE_BACKUP_DIR:-$COMPOSE_DIR/database-backup}"
RESTORE_READY_TIMEOUT="${RESTORE_READY_TIMEOUT:-90}"
WORK_DIR=""
RESTORE_CONTAINER=""
RESTORE_VOLUME=""

cleanup() {
    local result="$?"
    trap - EXIT
    if [[ -n "$RESTORE_CONTAINER" ]] && ! docker rm -f "$RESTORE_CONTAINER" >/dev/null 2>&1; then
        printf 'The isolated restore container could not be removed.\n' >&2
        result=1
    fi
    if [[ -n "$RESTORE_VOLUME" ]] && ! docker volume rm "$RESTORE_VOLUME" >/dev/null 2>&1; then
        printf 'The isolated restore volume could not be removed.\n' >&2
        result=1
    fi
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

main() {
    local source="${1:-}" archive database image flavor tables restored_tables attempt
    local base_tables
    local -a client
    local coverage="${2:-}" archived_coverage
    if [[ "$source" == --help || "$source" == -h ]]; then
        printf 'Usage: database-restore-check.sh CONTAINER [--tables-only]\nRestores a saved archive into a temporary container with no network or production mounts.\n'
        return
    fi
    [[ "$source" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 2
    [[ "$RESTORE_READY_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || return 2
    (( $# == 1 )) || { [[ "$#" == 2 && "$coverage" == --tables-only ]] || return 2; }
    archive="$DATABASE_BACKUP_DIR/$source.tar.gz"
    [[ "$coverage" != --tables-only ]] || archive="$DATABASE_BACKUP_DIR/$source.tables-only.tar.gz"
    [[ -r "$archive" ]] || { printf 'The database archive is missing.\n' >&2; return 1; }
    WORK_DIR="$(mktemp -d)"
    gzip -t "$archive"
    tar -xzf "$archive" -C "$WORK_DIR" -- dump.sql manifest.tsv
    database="$(awk -F '\t' '$1=="database" {print $2}' "$WORK_DIR/manifest.tsv")"
    image="$(awk -F '\t' '$1=="image" {print $2}' "$WORK_DIR/manifest.tsv")"
    flavor="$(awk -F '\t' '$1=="flavor" {print $2}' "$WORK_DIR/manifest.tsv")"
    tables="$(awk -F '\t' '$1=="tables" {print $2}' "$WORK_DIR/manifest.tsv")"
    archived_coverage="$(awk -F '\t' '$1=="coverage" {print $2}' "$WORK_DIR/manifest.tsv")"
    if [[ "$coverage" == --tables-only ]]; then
        [[ "$archived_coverage" == tables-only ]] || return 1
    else
        [[ "$archived_coverage" == full || -z "$archived_coverage" ]] || return 1
    fi
    [[ "$database" =~ ^[A-Za-z0-9_]+$ && "$tables" =~ ^[1-9][0-9]*$ \
        && "$image" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    [[ "$flavor" == mysql || "$flavor" == mariadb ]] || return 1
    docker image inspect "$image" >/dev/null 2>&1 || {
        printf 'The exact database image recorded in the backup is unavailable.\n' >&2
        return 1
    }

    RESTORE_CONTAINER="sdwa5-restore-$(date +%s)-$$"
    RESTORE_VOLUME="$RESTORE_CONTAINER-data"
    docker volume create --label org.sdwa5.restore-check=true "$RESTORE_VOLUME" >/dev/null

    # volume-nocopy keeps Docker from seeding the new volume with whatever the
    # image ships under /var/lib/mysql. The dockware Shopware image ships files
    # there, and mysqld --initialize refuses a non-empty data directory.
    if [[ "$flavor" == mariadb ]]; then
        client=(mariadb --no-defaults --user=root)
        docker run --detach --name "$RESTORE_CONTAINER" --network none --user root \
            --label org.sdwa5.restore-check=true --memory 768m --cpus 1 --pids-limit 256 \
            --mount "type=volume,source=$RESTORE_VOLUME,target=/var/lib/mysql,volume-nocopy=true" \
            --env MARIADB_ALLOW_EMPTY_ROOT_PASSWORD=1 "$image" \
            mariadbd --skip-networking --skip-log-bin --event-scheduler=OFF >/dev/null
    else
        # The client's compiled-in socket path differs between builds, so it
        # is named to match the server started below.
        client=(mysql --no-defaults --user=root --socket=/var/run/mysqld/mysqld.sock)
        docker run --detach --name "$RESTORE_CONTAINER" --network none --user root \
            --label org.sdwa5.restore-check=true --memory 768m --cpus 1 --pids-limit 256 \
            --mount "type=volume,source=$RESTORE_VOLUME,target=/var/lib/mysql,volume-nocopy=true" \
            --tmpfs /var/run/mysqld --entrypoint /bin/sh "$image" -c \
            'set -e; chown mysql:mysql /var/lib/mysql /var/run/mysqld; mysqld --no-defaults --initialize-insecure --user=mysql --datadir=/var/lib/mysql --log-error=/tmp/initialize.log; exec mysqld --no-defaults --user=mysql --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --pid-file=/var/run/mysqld/mysqld.pid --skip-networking --mysqlx=OFF --event-scheduler=OFF --log-error=/tmp/mysql.log' >/dev/null
    fi

    # The MariaDB entrypoint initializes through a temporary server that answers
    # SELECT 1 and then shuts down, so an import started then is cut off. Its
    # log line marks the hand-over to the real server.
    for (( attempt = 1; ; attempt++ )); do
        if { [[ "$flavor" != mariadb ]] \
                || docker logs "$RESTORE_CONTAINER" 2>&1 | grep -q 'init process done'; } \
            && docker exec "$RESTORE_CONTAINER" "${client[@]}" \
                --execute='SELECT 1' >/dev/null 2>&1; then
            break
        fi
        if (( attempt >= RESTORE_READY_TIMEOUT )); then
            printf 'The isolated database did not become ready within %s seconds.\n' \
                "$RESTORE_READY_TIMEOUT" >&2
            return 1
        fi
        sleep 1
    done
    if ! docker exec -i "$RESTORE_CONTAINER" "${client[@]}" \
        < "$WORK_DIR/dump.sql" > "$WORK_DIR/restore.log" 2>&1; then
        printf 'The isolated restore failed. No production database was changed.\n' >&2
        return 1
    fi
    restored_tables="$(docker exec "$RESTORE_CONTAINER" "${client[@]}" \
        --batch --skip-column-names --database="$database" \
        --execute='SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()')"
    [[ "$restored_tables" == "$tables" ]] || {
        printf 'The restored table count differs from the backup manifest.\n' >&2
        return 1
    }
    # CHECK TABLE through the client rather than mysqlcheck, which not every
    # server image ships (Oracle's mysql:8.0 has none). Any error, or a status
    # other than OK, fails the drill.
    base_tables="$(docker exec "$RESTORE_CONTAINER" "${client[@]}" \
        --batch --skip-column-names --database="$database" \
        --execute="SELECT CONCAT('\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`') FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'" \
        2> "$WORK_DIR/check.log")" || {
        printf 'The restored table list could not be read.\n' >&2
        return 1
    }
    if [[ -n "$base_tables" ]]; then
        if ! docker exec "$RESTORE_CONTAINER" "${client[@]}" \
                --batch --skip-column-names --database="$database" \
                --execute="CHECK TABLE ${base_tables//$'\n'/, }" > "$WORK_DIR/check.log" 2>&1 \
            || ! awk -F '\t' '$3 == "error" || ($3 == "status" && $4 != "OK") { bad = 1 } END { exit bad }' \
                "$WORK_DIR/check.log"; then
            printf 'The restored tables failed CHECK TABLE.\n' >&2
            return 1
        fi
    fi
    if [[ "$coverage" == --tables-only ]]; then
        printf 'Table-only restore verified for %s. Routine metadata remains unverified.\n' "$source"
    else
        printf 'Restore verified for %s. SQL import, table count and table checks passed.\n' "$source"
    fi
}

main "$@"
