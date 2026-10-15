#!/usr/bin/env bash
# Rehearse the SdWa5 ERP upgrade and rollback using disposable copies only.
# The caller first creates a fresh full archive with database-backup.sh.
# This script never stops, changes, or connects to the production database.
# Its root-only evidence directory retains the source archive and private logs.
# Usage: bash tools/dolibarr/rehearse-upgrade.sh [--apply ARCHIVE]

set -euo pipefail
umask 077

REPO_ROOT="${COMPOSE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TARGET_IMAGE="dolibarr/dolibarr:23.0.4"
TARGET_VERSION="23.0.4"
WORK=""
APP=""
DB=""
NETWORK=""
PHASE="preflight"
EVIDENCE=""

fail() { printf '%s\n' "$*" >&2; return 1; }

cleanup() {
    local result="$?"
    trap - EXIT
    if [[ -n "$WORK" && -n "$EVIDENCE" ]]; then
        [[ -z "$APP" ]] || docker logs "$APP" > "$WORK/final-application.log" 2>&1 || true
        cp "$WORK"/*.log "$EVIDENCE/" 2>/dev/null || true
        cp "$WORK"/version.after "$WORK"/counts.* "$WORK"/lock.mode "$EVIDENCE/" 2>/dev/null || true
    fi
    [[ -z "$APP" ]] || docker rm -f "$APP" >/dev/null 2>&1 || result=1
    [[ -z "$DB" ]] || docker rm -f "$DB" >/dev/null 2>&1 || result=1
    [[ -z "$NETWORK" ]] || docker network rm "$NETWORK" >/dev/null 2>&1 || result=1
    [[ -z "$WORK" ]] || rm -rf -- "$WORK"
    if (( result != 0 )); then
        printf 'Rehearsal failed during %s. Production was not changed.\n' "$PHASE" >&2
    fi
    [[ -z "$EVIDENCE" ]] || printf 'Private evidence directory: %s\n' "$EVIDENCE"
    exit "$result"
}

# All credentials stay inside the disposable database container.
database() {
    docker exec -i "$DB" sh -c '
        MYSQL_PWD=$(cat /run/secrets/rehearsal-password)
        export MYSQL_PWD
        exec mariadb --no-defaults --user=root "$@"
    ' sh "$@"
}

counts() {
    database --batch --skip-column-names --database="$DATABASE" --execute="
        SELECT 'users',COUNT(*) FROM llx_user UNION ALL
        SELECT 'thirdparties',COUNT(*) FROM llx_societe UNION ALL
        SELECT 'invoices',COUNT(*) FROM llx_facture UNION ALL
        SELECT 'bank',COUNT(*) FROM llx_bank;"
}

version() {
    database --batch --skip-column-names --database="$DATABASE" \
        --execute="SELECT value FROM llx_const WHERE name='MAIN_VERSION_LAST_UPGRADE' AND entity=0;"
}

start_application() {
    local image="$1"
    local -a startup=()
    local -a app_command=(apache2-foreground)
    if [[ "$image" == "$TARGET_IMAGE_ID" ]]; then
        startup=(--entrypoint /bin/bash --mount "type=bind,src=${REHEARSAL_ENTRYPOINT:-$REPO_ROOT/tools/dolibarr/entrypoint.sh},dst=/opt/sdwa5-dolibarr-entrypoint.sh,readonly")
        app_command=(/opt/sdwa5-dolibarr-entrypoint.sh apache2-foreground)
    fi
    docker run --detach --pull never --name "$APP" --network "$NETWORK" \
        --memory 512m --cpus 1 --pids-limit 256 \
        --env-file "$WORK/application.env" \
        --env DOLI_DB_HOST=database --env "DOLI_DB_NAME=$DATABASE" --env DOLI_DB_USER=root \
        --env DOLI_INIT_DEMO=0 --env DOLI_INSTALL_AUTO=1 --env DOLI_CRON=0 \
        --env DOLI_URL_ROOT=http://localhost \
        --mount "type=bind,src=$WORK/documents,dst=/var/www/documents" \
        --mount "type=bind,src=$WORK/custom,dst=/var/www/html/custom" \
        "${startup[@]}" "$image" "${app_command[@]}" \
        > "$WORK/application-id.log" 2>> "$WORK/docker.log"
}

wait_for_application() {
    local attempt code
    for (( attempt=0; attempt<180; attempt++ )); do
        code="$(docker exec "$APP" curl --silent --output /dev/null --max-time 2 \
            --write-out '%{http_code}' http://127.0.0.1/ 2>> "$WORK/readiness.log" || true)"
        [[ "$code" != 200 ]] || return 0
        [[ "$(docker inspect --format '{{.State.Running}}' "$APP")" == true ]] || return 1
        sleep 1
    done
    return 1
}

# A web health check can pass even when the entrypoint's migration failed.
# Keep each independent gate so the offline tests can exercise false successes.
verify_upgrade_evidence() {
    local unexpected missing_fields
    [[ "$(cat "$WORK/version.after")" == "$TARGET_VERSION" ]] || return 1
    cmp -s "$WORK/counts.before" "$WORK/counts.after" || return 1
    grep -q 'Migration successful' "$WORK/application.log" || return 1
    ! grep -Eiq 'Migration failed|Dump failed|DB Restored|Fatal error|Parse error|SQLSTATE' \
        "$WORK/application.log" "$WORK/migration.log" || return 1
    ! grep -Eiq 'class="[^"]*(error|fatal)[^"]*"' "$WORK/migration.log" || return 1
    # run_sql explicitly accepts duplicate objects/records and repeated DROP
    # operations. Syntax errors and other SQL failures remain fatal here.
    unexpected="$(grep -Eo 'DB_ERROR[A-Z0-9_]*|SQL_ERROR[A-Z0-9_]*' "$WORK/migration.log" \
        | grep -Ev '^DB_ERROR_(COLUMN_ALREADY_EXISTS|TABLE_ALREADY_EXISTS|PRIMARY_KEY_ALREADY_EXISTS|KEY_NAME_ALREADY_EXISTS|RECORD_ALREADY_EXISTS|NOSUCHFIELD)$' || true)"
    [[ -z "$unexpected" ]] || return 1
    missing_fields="$(grep 'DB_ERROR_NOSUCHFIELD' "$WORK/migration.log" \
        | grep -Ev '<!-- Result = DB_ERROR_NOSUCHFIELD -->|DB_ERROR_NOSUCHFIELD Can.t DROP (COLUMN|INDEX|FOREIGN KEY)' || true)"
    [[ -z "$missing_fields" ]] || return 1
    [[ "$(cat "$WORK/lock.mode")" == 400 ]] || return 1
}

main() {
    if [[ "${1:-}" != --apply ]]; then
        (( $# == 0 )) || [[ "$1" == --help && $# == 1 ]] || return 2
        printf 'Would rehearse %s with copied documents and a full ERP archive.\n' "$TARGET_IMAGE"
        printf 'Production containers remain running. No image is pulled.\n'
        printf 'Apply with: bash %s --apply ARCHIVE\n' "${BASH_SOURCE[0]}"
        return
    fi
    [[ $# == 2 && -r "$2" ]] || return 2
    [[ $EUID == 0 ]] || { fail 'Run the applied rehearsal as root on the VPS.'; return 1; }
    local archive="$2" source_image database_image wanted_image attempt before_version tables
    source_image="$(docker inspect --format '{{.Image}}' dolibarr)"
    database_image="$(docker inspect --format '{{.Image}}' dolibarr_db)"
    wanted_image="$(docker image inspect --format '{{.Id}}' "$TARGET_IMAGE")"
    TARGET_IMAGE_ID="$wanted_image"
    [[ "$source_image" =~ ^sha256:[a-f0-9]{64}$ && "$database_image" =~ ^sha256:[a-f0-9]{64}$ \
        && "$wanted_image" =~ ^sha256:[a-f0-9]{64}$ ]] || return 1
    [[ "$source_image" != "$wanted_image" ]] || { fail 'The target is already deployed.'; return 1; }

    EVIDENCE="$(mktemp -d /var/tmp/sec05-evidence.XXXXXX)"
    WORK="$(mktemp -d /var/tmp/sec05-rehearsal.XXXXXX)"
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    cp -- "$archive" "$EVIDENCE/pre-upgrade.tar.gz"
    chmod 600 "$EVIDENCE/pre-upgrade.tar.gz"
    gzip -t "$EVIDENCE/pre-upgrade.tar.gz"
    mkdir "$WORK/archive" "$WORK/db" "$WORK/post"
    tar -xzf "$EVIDENCE/pre-upgrade.tar.gz" -C "$WORK/archive" -- dump.sql manifest.tsv
    DATABASE="$(awk -F '\t' '$1=="database" {print $2}' "$WORK/archive/manifest.tsv")"
    [[ "$DATABASE" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    [[ "$(awk -F '\t' '$1=="image" {print $2}' "$WORK/archive/manifest.tsv")" == "$database_image" ]] || return 1
    [[ "$(awk -F '\t' '$1=="coverage" {print $2}' "$WORK/archive/manifest.tsv")" == full ]] || return 1
    printf 'source_image\t%s\ntarget_image\t%s\ndatabase_image\t%s\n' \
        "$source_image" "$wanted_image" "$database_image" > "$EVIDENCE/images.tsv"
    cp -a "$REPO_ROOT/dolibarr-documents-data" "$WORK/documents.before"
    cp -a "$REPO_ROOT/dolibarr-custom-data" "$WORK/custom.before"
    cp -a "$WORK/documents.before" "$WORK/documents"
    cp -a "$WORK/custom.before" "$WORK/custom"
    openssl rand -hex 32 > "$WORK/password"
    { printf 'DOLI_DB_PASSWORD='; cat "$WORK/password"; \
        printf 'DOLI_ADMIN_PASSWORD='; cat "$WORK/password"; } > "$WORK/application.env"
    NETWORK="sec05-$(date +%s)-$$"
    DB="${NETWORK}_db"
    APP="${NETWORK}_web"
    docker network create --internal "$NETWORK" > "$WORK/network.log"
    PHASE="isolated database import"
    printf 'Importing the archive into an isolated copy.\n'
    docker run --detach --pull never --name "$DB" --network "$NETWORK" --network-alias database \
        --memory 768m --cpus 1 --pids-limit 256 \
        --env MYSQL_ROOT_PASSWORD_FILE=/run/secrets/rehearsal-password --env MARIADB_ROOT_HOST=% \
        --mount "type=bind,src=$WORK/password,dst=/run/secrets/rehearsal-password,readonly" \
        --mount "type=bind,src=$WORK/db,dst=/var/lib/mysql" \
        "$database_image" --event-scheduler=OFF > "$WORK/database-id.log" 2>> "$WORK/docker.log"
    for (( attempt=0; attempt<120; attempt++ )); do
        if docker logs "$DB" 2>&1 | grep -q 'init process done' \
            && database --execute='SELECT 1' > /dev/null 2>&1; then break; fi
        sleep 1
    done
    (( attempt < 120 )) || return 1
    database < "$WORK/archive/dump.sql" > "$WORK/import.log" 2>&1
    counts > "$WORK/counts.before"
    before_version="$(version)"
    [[ "$before_version" == 23.0.2 ]] || { fail 'The copied database is not version 23.0.2.'; return 1; }

    PHASE="target migration"
    printf 'Testing the target image migration.\n'
    rm -f -- "$WORK/documents/install.lock"
    start_application "$wanted_image"
    wait_for_application
    docker logs "$APP" > "$WORK/application.log" 2>&1
    cp "$WORK/documents/migration_error.html" "$WORK/migration.log"
    version > "$WORK/version.after"
    counts > "$WORK/counts.after"
    stat -c '%a' "$WORK/documents/install.lock" > "$WORK/lock.mode"
    verify_upgrade_evidence
    [[ "$(docker exec "$APP" printenv DOLI_VERSION)" == "$TARGET_VERSION" ]] || return 1
    docker exec "$APP" php -r '$s=@fsockopen("1.1.1.1",443,$e,$m,2); if ($s) { fclose($s); exit(1); }'
    printf 'Migration, business-record counts, lock and egress gates passed.\n'

    PHASE="upgraded archive restore"
    docker exec -i "$DB" sh -c '
        MYSQL_PWD=$(cat /run/secrets/rehearsal-password); export MYSQL_PWD
        exec mariadb-dump --no-defaults --user=root --single-transaction --routines --events \
            --triggers --hex-blob --databases "$1"
    ' sh "$DATABASE" > "$WORK/post/dump.sql" 2> "$WORK/dump.log"
    tables="$(database --batch --skip-column-names --database="$DATABASE" \
        --execute='SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE();')"
    printf 'database\t%s\nimage\t%s\nflavor\tmariadb\ntables\t%s\ncoverage\tfull\n' \
        "$DATABASE" "$database_image" "$tables" > "$WORK/post/manifest.tsv"
    tar -czf "$WORK/post/$DB.tar.gz" -C "$WORK/post" dump.sql manifest.tsv
    DATABASE_BACKUP_DIR="$WORK/post" bash "$REPO_ROOT/monitoring/database-restore-check.sh" "$DB"

    PHASE="old image and empty-schema rollback"
    printf 'Testing rollback into an empty application schema.\n'
    docker rm -f "$APP" > /dev/null
    database --execute="DROP DATABASE \`$DATABASE\`;"
    database < "$WORK/archive/dump.sql" > "$WORK/rollback.log" 2>&1
    rm -rf -- "$WORK/documents" "$WORK/custom"
    cp -a "$WORK/documents.before" "$WORK/documents"
    cp -a "$WORK/custom.before" "$WORK/custom"
    start_application "$source_image"
    wait_for_application
    [[ "$(version)" == "$before_version" ]] || return 1
    [[ "$(docker exec "$APP" printenv DOLI_VERSION)" == "$before_version" ]] || return 1
    counts > "$WORK/counts.rollback"
    cmp -s "$WORK/counts.before" "$WORK/counts.rollback"
    cp "$WORK/counts.before" "$EVIDENCE/business-counts.tsv"
    printf 'The isolated migration, full archive restore and application rollback passed.\n' \
        | tee "$EVIDENCE/result.txt"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
