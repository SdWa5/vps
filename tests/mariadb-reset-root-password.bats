#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    export STUB_COMPOSE_LOG="$BATS_TEST_TMPDIR/compose.log"
    : > "$STUB_COMPOSE_LOG"
}

reset_root() {
    run bash "$REPO_ROOT/tools/mariadb/reset-root-password.sh" "$@"
}

@test "a stopped service gets the reset script on stdin of a throwaway container" {
    export STUB_COMPOSE_PS=dbid STUB_CONTAINER_dbid=false
    export STUB_COMPOSE_RUN_OUTPUT='Root password set for root@localhost and verified with a login.'
    reset_root dolibarr_db
    [ "$status" -eq 0 ]
    grep -qx 'run --rm --no-deps -T --entrypoint bash dolibarr_db -s' "$STUB_COMPOSE_LOG"
}

@test "a running service is refused, because two servers on one datadir corrupt it" {
    export STUB_COMPOSE_PS=dbid
    reset_root dolibarr_db
    [ "$status" -eq 1 ]
    [[ "$output" == *'Stop dolibarr_db first'* ]]
    ! grep -q '^run' "$STUB_COMPOSE_LOG" || false
}

@test "a run that exits 0 without the success line is not taken as a reset" {
    reset_root dolibarr_db
    [ "$status" -eq 1 ]
    [[ "$output" == *'was not reset'* ]]
}

@test "a failing run is reported as such" {
    export STUB_COMPOSE_RUN_RC=1 STUB_COMPOSE_RUN_OUTPUT='No root account exists; nothing was changed.'
    reset_root dolibarr_db
    [ "$status" -eq 1 ]
    [[ "$output" == *'No root account exists'* ]]
    [[ "$output" == *'was not reset'* ]]
}

@test "missing, invalid and extra arguments fail before compose is asked" {
    reset_root
    [ "$status" -eq 2 ]
    reset_root '../x'
    [ "$status" -eq 2 ]
    reset_root dolibarr_db --now
    [ "$status" -eq 2 ]
    [ ! -s "$STUB_COMPOSE_LOG" ]
    reset_root --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'docker compose stop SERVICE'* ]]
}

# The inner script runs inside the throwaway container. Here it runs against a
# gosu that starts nothing and a mariadb client that answers like a server with
# one root account, writes the statements it is fed to a file and accepts the
# root login only with the expected password.
inner_stubs() {
    local bin="$BATS_TEST_TMPDIR/inner-bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 0\n' > "$bin/gosu"
    cat > "$bin/mariadb" <<'STUB'
#!/usr/bin/env bash
for arg; do
    case "$arg" in
        --execute=SELECT\ Host*) echo localhost; exit 0 ;;
        --user=root) [[ "${MYSQL_PWD:-}" == "$STUB_EXPECT_PW" ]] || exit 1 ;;
        --execute=*) exit 0 ;;
    esac
done
cat > "$STUB_SQL_LOG"
STUB
    chmod +x "$bin/gosu" "$bin/mariadb"
    export PATH="$bin:$PATH" STUB_SQL_LOG="$BATS_TEST_TMPDIR/sql.log"
    unset MARIADB_ROOT_PASSWORD MYSQL_ROOT_PASSWORD MARIADB_ROOT_PASSWORD_FILE MYSQL_ROOT_PASSWORD_FILE
}

inner() {
    run bash "$REPO_ROOT/tools/mariadb/reset-root-password.inner.sh"
}

@test "the inner script takes the root password from a _FILE secret without its newline" {
    inner_stubs
    printf 'from-file\n' > "$BATS_TEST_TMPDIR/root_pw"
    export MYSQL_ROOT_PASSWORD_FILE="$BATS_TEST_TMPDIR/root_pw" STUB_EXPECT_PW=from-file
    inner
    [ "$status" -eq 0 ]
    [[ "$output" == *'Root password set for root@localhost and verified with a login.'* ]]
    grep -qxF "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('from-file');" "$STUB_SQL_LOG"
    [[ "$output" != *from-file* ]]
}

@test "the inner script prefers a plain root password over a _FILE one" {
    inner_stubs
    printf 'from-file' > "$BATS_TEST_TMPDIR/root_pw"
    export MARIADB_ROOT_PASSWORD=plain MARIADB_ROOT_PASSWORD_FILE="$BATS_TEST_TMPDIR/root_pw" STUB_EXPECT_PW=plain
    inner
    [ "$status" -eq 0 ]
    grep -qF "PASSWORD('plain')" "$STUB_SQL_LOG"
}

@test "the inner script refuses an unreadable _FILE and a missing password" {
    inner_stubs
    export MYSQL_ROOT_PASSWORD_FILE="$BATS_TEST_TMPDIR/absent"
    inner
    [ "$status" -eq 1 ]
    [[ "$output" == *'is not readable'* ]]
    unset MYSQL_ROOT_PASSWORD_FILE
    inner
    [ "$status" -eq 1 ]
    [[ "$output" == *'no root password configured'* ]]
    [ ! -e "$STUB_SQL_LOG" ]
}
