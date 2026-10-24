#!/usr/bin/env bash

set -uo pipefail
umask 077

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
load_env

DATABASE_BACKUP_DIR="${DATABASE_BACKUP_DIR:-$COMPOSE_DIR/database-backup}"
DATABASE_BACKUP_CONTAINERS="${DATABASE_BACKUP_CONTAINERS:-dolibarr_db shopware paperless_sdwa5_db paperless_home_db}"
DATABASE_BACKUP_TIMEOUT="${DATABASE_BACKUP_TIMEOUT:-900}"
CHIMODIAZZ_DEPLOY_LOCK="${CHIMODIAZZ_DEPLOY_LOCK:-/run/lock/chimodiazz-deploy.lock}"
WORK_DIR=""

cleanup() {
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

database_client() {
    local container="$1" operation="$2"

    if [[ "$container" == *_db ]]; then
        timeout "$DATABASE_BACKUP_TIMEOUT" docker exec -i --user root "$container" sh -s -- "$operation" <<'CLIENT'
set -eu
test -n "${MYSQL_USER:-}" && test -n "${MYSQL_DATABASE:-}"
MYSQL_PWD="${MYSQL_PASSWORD:-}"
if [ -n "${MYSQL_PASSWORD_FILE:-}" ]; then
    MYSQL_PWD=$(cat "$MYSQL_PASSWORD_FILE")
fi
export MYSQL_PWD
if [ "$1" = probe ]; then
    exec mariadb --no-defaults --user="$MYSQL_USER" --protocol=TCP --host=127.0.0.1 \
        --batch --skip-column-names --database="$MYSQL_DATABASE" \
        --execute="SELECT DATABASE(), VERSION(), COUNT(*), COALESCE(SUM(TABLE_TYPE = 'BASE TABLE' AND ENGINE <> 'InnoDB'), 0), (SELECT COUNT(*) FROM (SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() GROUP BY TABLE_NAME, CONSTRAINT_NAME HAVING COUNT(*) > 1) d) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()"
fi
routine_option=--routines
[ "$1" != dump-tables ] || routine_option=--skip-routines
exec mariadb-dump --no-defaults --user="$MYSQL_USER" --protocol=TCP --host=127.0.0.1 \
    --single-transaction --quick --skip-lock-tables "$routine_option" --events --triggers --hex-blob \
    --databases "$MYSQL_DATABASE"
CLIENT
    else
        timeout "$DATABASE_BACKUP_TIMEOUT" docker exec -i --user root "$container" \
            php -d display_errors=stderr -- "$operation" \
            < "$MONITORING_DIR/shopware-database-client.php"
    fi
}

backup_failed() {
    local container="$1" stage="$2"
    printf '%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$stage" \
        > "$DATABASE_BACKUP_DIR/$container.failed"
    if [[ -s "$DATABASE_BACKUP_DIR/$container.tar.gz" ]]; then
        log "Database backup failed for $container at $stage. The previous archive was preserved."
    else
        log "Database backup failed for $container at $stage. No full archive exists yet."
    fi
    cleanup
    WORK_DIR=""
    return 1
}

backup_one() {
    local container="$1" probe database version tables nontransactional duplicates image flavor archive
    local coverage=full
    WORK_DIR="$(mktemp -d "$DATABASE_BACKUP_DIR/.$container.XXXXXX")" || return 1

    if ! probe="$(database_client "$container" probe 2> "$WORK_DIR/error.log")"; then
        backup_failed "$container" 'connection check'
        return 1
    fi
    IFS=$'\t' read -r database version tables nontransactional duplicates <<< "$probe"
    if [[ ! "$database" =~ ^[A-Za-z0-9_]+$ || ! "$tables" =~ ^[1-9][0-9]*$ \
        || "$nontransactional" != 0 ]]; then
        backup_failed "$container" 'transactional table check'
        return 1
    fi
    # A table carrying the same foreign key name twice dumps fine and then fails
    # to import with errno 150, so the archive would look good and restore
    # nothing. See tools/mariadb/recreate-foreign-keys.sh for how this arises.
    if [[ "$duplicates" != 0 ]]; then
        backup_failed "$container" 'duplicate foreign key names'
        return 1
    fi

    image="$(docker inspect --format '{{.Image}}' "$container" 2> "$WORK_DIR/error.log")" || {
        backup_failed "$container" 'image check'
        return 1
    }
    [[ "$image" =~ ^sha256:[a-f0-9]{64}$ ]] || {
        backup_failed "$container" 'image identity check'
        return 1
    }
    flavor=mysql
    [[ "$container" == *_db ]] && flavor=mariadb

    if ! database_client "$container" dump > "$WORK_DIR/dump.sql" 2> "$WORK_DIR/error.log"; then
        if [[ "$flavor" == mariadb ]] && grep -q 'Column count of mysql.proc is wrong' "$WORK_DIR/error.log"; then
            coverage='tables-only'
            if ! database_client "$container" dump-tables > "$WORK_DIR/dump.sql" 2> "$WORK_DIR/error.log"; then
                backup_failed "$container" 'table-only rescue dump'
                return 1
            fi
        else
            backup_failed "$container" 'SQL dump'
            return 1
        fi
    fi
    [[ -s "$WORK_DIR/dump.sql" ]] || { backup_failed "$container" 'empty SQL dump'; return 1; }

    printf 'database\t%s\nversion\t%s\ntables\t%s\nimage\t%s\nflavor\t%s\ncoverage\t%s\n' \
        "$database" "$version" "$tables" "$image" "$flavor" "$coverage" > "$WORK_DIR/manifest.tsv"
    archive="$WORK_DIR/backup.tar.gz"
    if ! tar -czf "$archive" -C "$WORK_DIR" dump.sql manifest.tsv \
        || ! gzip -t "$archive" || ! tar -tzf "$archive" >/dev/null; then
        backup_failed "$container" 'archive check'
        return 1
    fi
    chmod 600 "$archive" || return 1
    local destination="$DATABASE_BACKUP_DIR/$container.tar.gz"
    [[ "$coverage" != tables-only ]] || destination="$DATABASE_BACKUP_DIR/$container.tables-only.tar.gz"
    if ! mv -f -- "$archive" "$destination"; then
        backup_failed "$container" 'publication'
        return 1
    fi
    if [[ "$coverage" == tables-only ]]; then
        backup_failed "$container" 'routine metadata; a table-only rescue archive was published separately'
        return 1
    fi
    # A full archive supersedes an earlier rescue copy, which restic still holds.
    rm -f -- "$DATABASE_BACKUP_DIR/$container.failed" "$DATABASE_BACKUP_DIR/$container.tables-only.tar.gz"
    cleanup
    WORK_DIR=""
}

main() {
    local container failures=0
    (( $# <= 1 )) || return 2
    case "${1:-}" in
        --help|-h)
            printf 'Usage: database-backup.sh [--dry-run|--help]\nWrites atomic transactional SQL archives for the configured containers.\n'
            return 0 ;;
        --dry-run)
            printf 'Containers: %s\nDestination: %s\nNo files or database connections were changed.\n' \
                "$DATABASE_BACKUP_CONTAINERS" "$DATABASE_BACKUP_DIR"
            return 0 ;;
        '') ;;
        *) printf 'Unknown option.\n' >&2; return 2 ;;
    esac

    for container in $DATABASE_BACKUP_CONTAINERS; do
        [[ "$container" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || return 2
    done
    [[ -n "$DATABASE_BACKUP_CONTAINERS" ]] || return 2
    mkdir -p "$DATABASE_BACKUP_DIR" && chmod 700 "$DATABASE_BACKUP_DIR" || return 1
    exec 9> "$DATABASE_BACKUP_DIR/.lock"
    flock -n 9 || return 0

    if [[ " $DATABASE_BACKUP_CONTAINERS " == *' chimodiazz_shopware '* ]]; then
        exec 8> "$CHIMODIAZZ_DEPLOY_LOCK"
        if ! flock -w 120 8; then
            backup_failed chimodiazz_shopware 'deployment lock'
            return 1
        fi
    fi

    for container in $DATABASE_BACKUP_CONTAINERS; do
        backup_one "$container" || failures=1
    done
    return "$failures"
}

main "$@"
