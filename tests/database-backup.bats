#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    export DATABASE_BACKUP_CONTAINERS='dolibarr_db shopware'
    export DATABASE_BACKUP_DIR="$BATS_TEST_TMPDIR/sql-backup"
    export STUB_DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    export CHIMODIAZZ_DEPLOY_LOCK="$BATS_TEST_TMPDIR/deploy.lock"
    export STUB_IMAGE_ID='sha256:0000000000000000000000000000000000000000000000000000000000000000'
    : > "$STUB_DOCKER_LOG"
}

backup_databases() {
    run bash "$REPO_ROOT/monitoring/database-backup.sh" "$@"
}

restore_database() {
    run bash "$REPO_ROOT/monitoring/database-restore-check.sh" "$@"
}

@test "dry run opens no database and creates no directory" {
    backup_databases --dry-run
    [ "$status" -eq 0 ]
    [ ! -d "$DATABASE_BACKUP_DIR" ]
    [ ! -s "$STUB_DOCKER_LOG" ]
}

@test "successful backup publishes readable archives with restrictive permissions" {
    backup_databases
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(stat -c %a "$DATABASE_BACKUP_DIR")" = 700 ]
    local container
    for container in $DATABASE_BACKUP_CONTAINERS; do
        [ "$(stat -c %a "$DATABASE_BACKUP_DIR/$container.tar.gz")" = 600 ]
        tar -tzf "$DATABASE_BACKUP_DIR/$container.tar.gz" | grep -qx dump.sql
        tar -xOzf "$DATABASE_BACKUP_DIR/$container.tar.gz" manifest.tsv | grep -qx $'tables\t2'
        [ ! -f "$DATABASE_BACKUP_DIR/$container.failed" ]
    done
}

@test "a MySQL 8.4 database container is archived with the mysql flavor" {
    DATABASE_BACKUP_CONTAINERS=shopware_db STUB_DB_VERSION=8.4.13 backup_databases
    [ "$status" -eq 0 ]
    tar -xOzf "$DATABASE_BACKUP_DIR/shopware_db.tar.gz" manifest.tsv | grep -qx $'flavor\tmysql'
    tar -xOzf "$DATABASE_BACKUP_DIR/shopware_db.tar.gz" manifest.tsv | grep -qx $'version\t8.4.13'
}

@test "a MariaDB database container is archived with the mariadb flavor" {
    DATABASE_BACKUP_CONTAINERS=dolibarr_db STUB_DB_VERSION=12.3.1-MariaDB backup_databases
    [ "$status" -eq 0 ]
    tar -xOzf "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz" manifest.tsv | grep -qx $'flavor\tmariadb'
}

@test "the client picks mysqldump without its tablespace and GTID output where mariadb-dump is missing" {
    grep -q "else client=mysql dump=mysqldump extra='--no-tablespaces --set-gtid-purged=OFF'; fi" \
        "$REPO_ROOT/monitoring/database-backup.sh"
    grep -q 'exec "\$dump" --no-defaults \$extra ' "$REPO_ROOT/monitoring/database-backup.sh"
}

@test "the default list backs up shopware_db rather than the dockware container" {
    grep -q 'DATABASE_BACKUP_CONTAINERS:-dolibarr_db shopware_db paperless_sdwa5_db paperless_home_db}' \
        "$REPO_ROOT/monitoring/database-backup.sh"
}

@test "probe failure preserves the previous archive and hides database diagnostics" {
    backup_databases
    [ "$status" -eq 0 ]
    local before
    before="$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")"
    export STUB_DATABASE_FAIL=probe
    backup_databases
    [ "$status" -eq 1 ]
    [ "$before" = "$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")" ]
    [ -f "$DATABASE_BACKUP_DIR/dolibarr_db.failed" ]
    [[ "$output" != *'sensitive database diagnostic'* ]]
}

@test "nontransactional tables refuse a falsely consistent archive" {
    export STUB_NONTRANSACTIONAL_TABLES=1
    backup_databases
    [ "$status" -eq 1 ]
    [ ! -f "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz" ]
    [ -f "$DATABASE_BACKUP_DIR/dolibarr_db.failed" ]
    ! grep -q -- '-- dump' "$STUB_DOCKER_LOG" || false
}

@test "duplicate foreign key names fail the backup and keep the previous archive" {
    backup_databases
    [ "$status" -eq 0 ]
    local before
    before="$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")"
    export STUB_DUPLICATE_FOREIGN_KEYS=2
    backup_databases
    [ "$status" -eq 1 ]
    [ "$before" = "$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")" ]
    [ "$(cut -f2 "$DATABASE_BACKUP_DIR/dolibarr_db.failed")" = 'duplicate foreign key names' ]
}

@test "dump failure preserves a good archive and removes private temporary files" {
    backup_databases
    [ "$status" -eq 0 ]
    local before
    before="$(sha256sum "$DATABASE_BACKUP_DIR/shopware.tar.gz")"
    export STUB_DATABASE_FAIL=dump
    backup_databases
    [ "$status" -eq 1 ]
    [ "$before" = "$(sha256sum "$DATABASE_BACKUP_DIR/shopware.tar.gz")" ]
    [ "$(find "$DATABASE_BACKUP_DIR" -mindepth 1 -type d | wc -l)" -eq 0 ]
    [[ "$output" != *'sensitive database diagnostic'* ]]
}

@test "a successful retry clears a previous failure marker" {
    STUB_DATABASE_FAIL=dump backup_databases
    [ "$status" -eq 1 ]
    backup_databases
    [ "$status" -eq 0 ]
    [ ! -f "$DATABASE_BACKUP_DIR/dolibarr_db.failed" ]
}

@test "broken routine metadata gets a labeled rescue archive without replacing a full backup" {
    export DATABASE_BACKUP_CONTAINERS=dolibarr_db
    backup_databases
    [ "$status" -eq 0 ]
    local before
    before="$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")"
    export STUB_DATABASE_FAIL=routine_metadata
    backup_databases
    [ "$status" -eq 1 ]
    [ "$before" = "$(sha256sum "$DATABASE_BACKUP_DIR/dolibarr_db.tar.gz")" ]
    [ -f "$DATABASE_BACKUP_DIR/dolibarr_db.failed" ]
    [ -f "$DATABASE_BACKUP_DIR/dolibarr_db.tables-only.tar.gz" ]
    tar -xOzf "$DATABASE_BACKUP_DIR/dolibarr_db.tables-only.tar.gz" manifest.tsv \
        | grep -qx $'coverage\ttables-only'
    restore_database dolibarr_db --tables-only
    [ "$status" -eq 0 ]
    [[ "$output" == *'Routine metadata remains unverified'* ]]
    unset STUB_DATABASE_FAIL
    backup_databases
    [ "$status" -eq 0 ]
    [ ! -f "$DATABASE_BACKUP_DIR/dolibarr_db.tables-only.tar.gz" ]
    [ ! -f "$DATABASE_BACKUP_DIR/dolibarr_db.failed" ]
}

@test "a failure without any earlier archive does not claim one was preserved" {
    export DATABASE_BACKUP_CONTAINERS=dolibarr_db STUB_DATABASE_FAIL=routine_metadata
    backup_databases
    [ "$status" -eq 1 ]
    [[ "$output" == *'No full archive exists yet'* ]]
    [[ "$output" != *'previous archive was preserved'* ]]
}

@test "unknown options and invalid container names fail before writing files" {
    backup_databases --unknown
    [ "$status" -eq 2 ]
    backup_databases --dry-run unexpected
    [ "$status" -eq 2 ]
    export DATABASE_BACKUP_CONTAINERS='../production'
    backup_databases
    [ "$status" -eq 2 ]
    [ ! -d "$DATABASE_BACKUP_DIR" ]
}

@test "isolated restore has no network or production mounts and cleans its resources" {
    backup_databases
    [ "$status" -eq 0 ]
    restore_database dolibarr_db
    [ "$status" -eq 0 ]
    [[ "$output" == *'Restore verified for dolibarr_db'* ]]
    grep -q -- '--network none' "$STUB_DOCKER_LOG"
    grep -q -- 'CHECK TABLE `records`, `other`' "$STUB_DOCKER_LOG"
    grep -q -- 'rm -f sdwa5-restore-' "$STUB_DOCKER_LOG"
    grep -q -- 'volume rm sdwa5-restore-' "$STUB_DOCKER_LOG"
    ! grep -q -- 'type=bind' "$STUB_DOCKER_LOG" || false
}

@test "MySQL restore uses the exact archived image and names the server socket" {
    backup_databases
    [ "$status" -eq 0 ]
    restore_database shopware
    [ "$status" -eq 0 ]
    grep -q -- '--entrypoint /bin/sh sha256:' "$STUB_DOCKER_LOG"
    grep -q -- 'exec sdwa5-restore-.* mysql --no-defaults --user=root --socket=/var/run/mysqld/mysqld.sock' "$STUB_DOCKER_LOG"
}

@test "restore volumes are never seeded from the image's own data directory" {
    backup_databases
    [ "$status" -eq 0 ]
    restore_database shopware
    [ "$status" -eq 0 ]
    restore_database dolibarr_db
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '^run .*target=/var/lib/mysql,volume-nocopy=true' "$STUB_DOCKER_LOG")" -eq 2 ]
}

@test "MariaDB import waits for the entrypoint's temporary server to hand over" {
    backup_databases
    [ "$status" -eq 0 ]
    : > "$STUB_DOCKER_LOG"
    STUB_RESTORE_INIT_PENDING=1 RESTORE_READY_TIMEOUT=2 restore_database dolibarr_db
    [ "$status" -eq 1 ]
    [[ "$output" == *'did not become ready within 2 seconds'* ]]
    ! grep -q -- '--execute=SELECT 1' "$STUB_DOCKER_LOG" || false
    grep -q -- 'volume rm sdwa5-restore-' "$STUB_DOCKER_LOG"
}

@test "failed SQL imports hide row contents and still remove restore resources" {
    backup_databases
    [ "$status" -eq 0 ]
    export STUB_RESTORE_IMPORT_FAIL=1
    restore_database shopware
    [ "$status" -eq 1 ]
    [[ "$output" != *'sensitive restored row'* ]]
    grep -q -- 'volume rm sdwa5-restore-' "$STUB_DOCKER_LOG"
}

@test "a restored table count mismatch fails verification" {
    backup_databases
    [ "$status" -eq 0 ]
    STUB_RESTORE_TABLES=1 restore_database shopware
    [ "$status" -eq 1 ]
    [[ "$output" == *'table count differs'* ]]
}

@test "a CHECK TABLE error or a non-OK status fails the restore" {
    backup_databases
    [ "$status" -eq 0 ]
    STUB_RESTORE_CHECK_RESULT=$'error\tCorrupt' restore_database shopware
    [ "$status" -eq 1 ]
    [[ "$output" == *'failed CHECK TABLE'* ]]
    STUB_RESTORE_CHECK_RESULT=$'status\tTable is marked as crashed' restore_database shopware
    [ "$status" -eq 1 ]
    STUB_RESTORE_CHECK_RESULT=$'note\tThe storage engine does not support check' restore_database shopware
    [ "$status" -eq 0 ]
}

@test "missing and corrupt archives never start a restore container" {
    restore_database shopware
    [ "$status" -eq 1 ]
    mkdir -p "$DATABASE_BACKUP_DIR"
    printf 'broken' > "$DATABASE_BACKUP_DIR/shopware.tar.gz"
    restore_database shopware
    [ "$status" -ne 0 ]
    ! grep -q '^run ' "$STUB_DOCKER_LOG" || false
}
