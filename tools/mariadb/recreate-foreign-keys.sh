#!/usr/bin/env bash
#
# Recreate every foreign key of one MariaDB schema under the server that runs it.
#
# MariaDB 12.1 made foreign key names unique per table instead of per database.
# A foreign key created under an older server keeps its old-format name, and
# 12.x no longer sees that name when the same constraint is added again, so a
# second identical constraint is created. Dolibarr adds its constraints both in
# its install key files and in its migrations, and that left the ERP with 15
# such pairs, measured 2026-10-15. A dump of a table with a pair does not
# import (errno 150), so the SQL backup could not be restored.
#
# Neither mariadb-upgrade nor a table rebuild converts the old names, measured
# against mariadb:11.8 and mariadb:12.3. Dropping a constraint and adding it
# back under 12.x does, so this script does that for every foreign key, with
# foreign_key_checks off so each step is an in-place metadata change rather than
# a table copy and a full validation.
#
# It refuses to run while duplicates exist, because the definitions are read
# from information_schema and a pair would be recreated as a pair. Drop one of
# each pair first; DROP FOREIGN KEY removes exactly one of them.
#
# It writes to production, so it is dry-run by default.
#
# Usage, on the host from /opt/docker:
#   tools/mariadb/recreate-foreign-keys.sh CONTAINER           print the SQL it would run
#   tools/mariadb/recreate-foreign-keys.sh CONTAINER --apply   run it and verify the result
#
# The container's MYSQL_USER, MYSQL_PASSWORD (or MYSQL_PASSWORD_FILE) and
# MYSQL_DATABASE are used, the same application account database-backup.sh uses.

set -uo pipefail

usage() {
    sed -n '/^# Usage/,/^# MYSQL_DATABASE/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

query() {
    docker exec -i "$CONTAINER" sh -c '
        MYSQL_PWD="${MYSQL_PASSWORD:-}"
        [ -z "${MYSQL_PASSWORD_FILE:-}" ] || MYSQL_PWD=$(cat "$MYSQL_PASSWORD_FILE")
        export MYSQL_PWD
        exec mariadb --no-defaults --user="$MYSQL_USER" --protocol=TCP --host=127.0.0.1 \
            --skip-ssl-verify-server-cert --batch --skip-column-names --database="$MYSQL_DATABASE"'
}

duplicates() {
    printf '%s\n' "SELECT COUNT(*) FROM (SELECT 1 FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() GROUP BY TABLE_NAME, CONSTRAINT_NAME HAVING COUNT(*) > 1) d;" \
        | query
}

# One line per foreign key: table, name, referenced table, columns, referenced
# columns, delete rule, update rule, same-schema flag, column count.
snapshot() {
    query <<'SQL'
SELECT rc.TABLE_NAME, rc.CONSTRAINT_NAME, rc.REFERENCED_TABLE_NAME,
       GROUP_CONCAT(CONCAT('`', k.COLUMN_NAME, '`') ORDER BY k.ORDINAL_POSITION SEPARATOR ', '),
       GROUP_CONCAT(CONCAT('`', k.REFERENCED_COLUMN_NAME, '`') ORDER BY k.ORDINAL_POSITION SEPARATOR ', '),
       rc.DELETE_RULE, rc.UPDATE_RULE, rc.UNIQUE_CONSTRAINT_SCHEMA = DATABASE(), COUNT(*)
FROM information_schema.REFERENTIAL_CONSTRAINTS rc
JOIN information_schema.KEY_COLUMN_USAGE k
  ON k.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA AND k.TABLE_NAME = rc.TABLE_NAME
 AND k.CONSTRAINT_NAME = rc.CONSTRAINT_NAME AND k.REFERENCED_TABLE_NAME IS NOT NULL
WHERE rc.CONSTRAINT_SCHEMA = DATABASE()
GROUP BY rc.TABLE_NAME, rc.CONSTRAINT_NAME, rc.REFERENCED_TABLE_NAME, rc.DELETE_RULE,
         rc.UPDATE_RULE, rc.UNIQUE_CONSTRAINT_SCHEMA
ORDER BY 1, 2;
SQL
}

# RESTRICT is the default and is left out, so the recreated definition reads the
# same as the original in SHOW CREATE TABLE.
generate() {
    printf 'SET SESSION foreign_key_checks = 0;\n'
    awk -F '\t' '
        $8 != 1 { print "Refusing a cross-schema foreign key: " $1 "." $2 > "/dev/stderr"; bad = 1; next }
        {
            rules = ""
            if ($6 != "RESTRICT") rules = rules " ON DELETE " $6
            if ($7 != "RESTRICT") rules = rules " ON UPDATE " $7
            printf "ALTER TABLE `%s` DROP FOREIGN KEY `%s`, ALGORITHM=INPLACE, LOCK=NONE;\n", $1, $2
            printf "ALTER TABLE `%s` ADD CONSTRAINT `%s` FOREIGN KEY (%s) REFERENCES `%s` (%s)%s, ALGORITHM=INPLACE, LOCK=NONE;\n", $1, $2, $4, $3, $5, rules
        }
        END { exit bad }' || return 1
    printf 'SET SESSION foreign_key_checks = 1;\n'
}

main() {
    local apply=0 count before after sql
    case "${1:-}" in
        --help|-h) usage; return 0 ;;
        '') usage >&2; return 2 ;;
    esac
    CONTAINER="$1"
    [[ "$CONTAINER" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { printf 'Invalid container name.\n' >&2; return 2; }
    case "${2:-}" in
        --apply) apply=1 ;;
        '') ;;
        *) printf 'Unknown option.\n' >&2; return 2 ;;
    esac

    count="$(duplicates)" || { printf 'The database could not be queried.\n' >&2; return 1; }
    if [[ "$count" != 0 ]]; then
        printf '%s duplicate foreign key name(s) exist. Drop one of each pair first.\n' "$count" >&2
        return 1
    fi
    before="$(snapshot)" || { printf 'The foreign keys could not be read.\n' >&2; return 1; }
    [[ -n "$before" ]] || { printf 'The schema has no foreign keys.\n'; return 0; }
    sql="$(generate <<< "$before")" || return 1

    if (( ! apply )); then
        printf '%s\n' "$sql"
        printf -- '-- %s foreign keys. Nothing was changed; --apply runs this.\n' "$(wc -l <<< "$before")" >&2
        return 0
    fi

    printf '%s\n' "$sql" | query || {
        printf 'Recreating stopped at an error. Compare against this snapshot:\n%s\n' "$before" >&2
        return 1
    }
    after="$(snapshot)"
    if [[ "$after" != "$before" ]]; then
        printf 'The recreated foreign keys differ from the snapshot taken before:\n%s\n' "$before" >&2
        return 1
    fi
    printf '%s foreign keys recreated; definitions unchanged.\n' "$(wc -l <<< "$before")"
}

main "$@"
