#!/usr/bin/env bats
# Tests for monitoring/vaultwarden-db-backup.sh

load test_helper

setup() {
    common_setup

    # An isolated compose project, so nothing touches the real /opt/docker.
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    export SOURCE_DB="$COMPOSE_DIR/vaultwarden-data/db.sqlite3"
    export BACKUP_DIR="$COMPOSE_DIR/vaultwarden-db-backup"
    export DEST_DB="$BACKUP_DIR/db.sqlite3"

    mkdir -p "$(dirname "$SOURCE_DB")"
    printf 'SQLite format 3 live' > "$SOURCE_DB"
}

@test "dry run reports the paths and writes nothing" {
    db_backup --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$SOURCE_DB"* ]]
    [[ "$output" == *"$DEST_DB"* ]]
    [[ "$output" == *"Readable:    yes"* ]]
    [ ! -e "$DEST_DB" ]
    [ "$(mail_count)" -eq 0 ]
}

@test "a successful run publishes a verified copy and stays silent" {
    db_backup
    [ "$status" -eq 0 ]
    [ -f "$DEST_DB" ]
    [ "$(mail_count)" -eq 0 ]
}

@test "the published copy is not world readable" {
    db_backup
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$DEST_DB")" = "600" ]
    [ "$(stat -c %a "$BACKUP_DIR")" = "700" ]
}

@test "no temporary file is left behind on success" {
    db_backup
    [ "$status" -eq 0 ]
    [ ! -e "$DEST_DB.tmp" ]
}

@test "a missing sqlite3 mails and fails instead of leaving the gap open" {
    export SQLITE=definitely-not-installed-sqlite3
    db_backup
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"apt install sqlite3"* ]]
}

@test "an unreadable source mails and fails" {
    rm -f "$SOURCE_DB"
    db_backup
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"cannot be read"* ]]
}

@test "a failed dump keeps the previous copy and mails" {
    db_backup
    [ "$status" -eq 0 ]
    local before
    before="$(cat "$DEST_DB")"

    export STUB_SQLITE_BACKUP_FAIL=1
    db_backup
    [ "$status" -eq 1 ]
    [ "$(cat "$DEST_DB")" = "$before" ]
    [ ! -e "$DEST_DB.tmp" ]
    [ "$(mail_count)" -eq 1 ]
}

@test "a dump that fails integrity_check is discarded, not published" {
    export STUB_SQLITE_INTEGRITY="*** in database main ***
Page 4 is never used"
    db_backup
    [ "$status" -eq 1 ]
    [ ! -e "$DEST_DB" ]
    [ ! -e "$DEST_DB.tmp" ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"integrity check"* ]]
}

@test "a corrupt dump does not overwrite the last good copy" {
    db_backup
    [ "$status" -eq 0 ]
    local before
    before="$(cat "$DEST_DB")"

    export STUB_SQLITE_INTEGRITY="row 3 missing from index idx_users"
    export STUB_SQLITE_DUMP_CONTENT="garbage"
    db_backup
    [ "$status" -eq 1 ]
    [ "$(cat "$DEST_DB")" = "$before" ]
}

@test "an unknown option exits 2 without touching anything" {
    db_backup --wat
    [ "$status" -eq 2 ]
    [ ! -e "$DEST_DB" ]
    [ "$(mail_count)" -eq 0 ]
}

@test "help exits 0 and writes nothing" {
    db_backup --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"online backup API"* ]]
    [ ! -e "$DEST_DB" ]
}
