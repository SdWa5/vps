#!/usr/bin/env bats

setup() {
    export REHEARSAL_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/rehearse-upgrade.sh"
    export REHEARSAL_FIXTURE="$BATS_TEST_TMPDIR/evidence"
    mkdir "$REHEARSAL_FIXTURE"
    printf '24.0.1\n' > "$REHEARSAL_FIXTURE/version.after"
    printf 'users\t2\ninvoices\t17\n' > "$REHEARSAL_FIXTURE/counts.before"
    cp "$REHEARSAL_FIXTURE/counts.before" "$REHEARSAL_FIXTURE/counts.after"
    printf 'Migration successful ... Enjoy !\n' > "$REHEARSAL_FIXTURE/application.log"
    printf '<html><span class="ok">System upgraded</span></html>\n' > "$REHEARSAL_FIXTURE/migration.log"
    printf '400\n' > "$REHEARSAL_FIXTURE/lock.mode"
}

verify_fixture() {
    run bash -c 'source "$REHEARSAL_SCRIPT"; WORK="$REHEARSAL_FIXTURE"; verify_upgrade_evidence'
}

@test "default invocation performs no Docker operation" {
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 97\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$REHEARSAL_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Would rehearse'* ]]
}

@test "normal HTML migration output is accepted" {
    verify_fixture
    [ "$status" -eq 0 ]
}

@test "a healthy application without a completed migration is rejected" {
    printf 'Apache ready and HTTP 200\n' > "$REHEARSAL_FIXTURE/application.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "entrypoint success cannot hide an unchanged database version" {
    printf '23.0.2\n' > "$REHEARSAL_FIXTURE/version.after"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "entrypoint success cannot hide lost business records" {
    printf 'users\t2\ninvoices\t16\n' > "$REHEARSAL_FIXTURE/counts.after"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "a successful automatic rollback is not accepted as an upgrade" {
    printf 'Migration failed ... DB Restored ...\n' >> "$REHEARSAL_FIXTURE/application.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "SQL errors in HTML output fail the migration gate" {
    printf '<div class="error">SQL_ERROR</div>\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "an unlocked installation is rejected" {
    rm "$REHEARSAL_FIXTURE/lock.mode"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "upstream accepted duplicate objects do not fail a completed migration" {
    printf '<!-- Result = DB_ERROR_COLUMN_ALREADY_EXISTS -->\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -eq 0 ]
}

@test "syntax errors remain fatal even when the image reports success" {
    printf 'DB_ERROR_SYNTAX\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "a missing field outside an already-completed DROP remains fatal" {
    printf 'DB_ERROR_NOSUCHFIELD Unknown column in UPDATE\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "an already-completed DROP is accepted without hiding other missing fields" {
    printf '<!-- Result = DB_ERROR_NOSUCHFIELD -->\nDB_ERROR_NOSUCHFIELD Can\x27t DROP COLUMN field; check that it exists\nDB_ERROR_NOSUCHFIELD Can\x27t DROP FOREIGN KEY fk_example; check that it exists\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -eq 0 ]
}

@test "SQL text mentioning error outside an HTML class is accepted" {
    printf '<tr class="normal"><td>INSERT INTO example (error_count)</td></tr>\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -eq 0 ]
}

@test "an actual error class fails even without a DB_ERROR token" {
    printf '<div class="error">Migration incomplete</div>\n' >> "$REHEARSAL_FIXTURE/migration.log"
    verify_fixture
    [ "$status" -ne 0 ]
}

@test "the source version is read from the image's DOLI_VERSION" {
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nprintf "PATH=/usr/bin\\nDOLI_VERSION=23.0.4\\nPHP_VERSION=8.4\\n"\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c 'source "$REHEARSAL_SCRIPT"; image_version sha256:x'
    [ "$status" -eq 0 ]
    [ "$output" = '23.0.4' ]
}
