#!/usr/bin/env bats

setup() {
    export ENTRYPOINT_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/entrypoint.sh"
    export SQL_FIXTURE="$BATS_TEST_TMPDIR/sql"
    mkdir "$SQL_FIXTURE"
    for name in llx_don-don.sql llx_opensurvey_comments-opensurvey.sql llx_opensurvey_user_studs-opensurvey.sql; do
        printf 'CREATE TABLE example (\n  ip varchar(250) --ip used to create record (for public submission page)\n);\n' > "$SQL_FIXTURE/$name"
    done
}

@test "only the malformed comment whitespace changes" {
    cp "$SQL_FIXTURE/llx_don-don.sql" "$BATS_TEST_TMPDIR/before"
    run bash -c 'source "$ENTRYPOINT_SCRIPT"; normalize_sql_comments "$SQL_FIXTURE"'
    [ "$status" -eq 0 ]
    sed 's/--ip used/-- ip used/' "$BATS_TEST_TMPDIR/before" > "$BATS_TEST_TMPDIR/expected"
    cmp "$BATS_TEST_TMPDIR/expected" "$SQL_FIXTURE/llx_don-don.sql"
}

@test "normalization is safe across container restarts" {
    run bash -c 'source "$ENTRYPOINT_SCRIPT"; normalize_sql_comments "$SQL_FIXTURE"; normalize_sql_comments "$SQL_FIXTURE"'
    [ "$status" -eq 0 ]
}

@test "missing or changed upstream definitions fail before any file changes" {
    cp "$SQL_FIXTURE/llx_don-don.sql" "$BATS_TEST_TMPDIR/before"
    printf 'Unexpected SQL\n' > "$SQL_FIXTURE/llx_opensurvey_comments-opensurvey.sql"
    run bash -c 'source "$ENTRYPOINT_SCRIPT"; normalize_sql_comments "$SQL_FIXTURE"'
    [ "$status" -ne 0 ]
    cmp "$BATS_TEST_TMPDIR/before" "$SQL_FIXTURE/llx_don-don.sql"
}

@test "a future image version requires explicit wrapper review" {
    run env DOLI_VERSION=23.0.5 bash "$ENTRYPOINT_SCRIPT" apache2-foreground
    [ "$status" -ne 0 ]
    [[ "$output" == *'requires Dolibarr 23.0.4'* ]]
}
