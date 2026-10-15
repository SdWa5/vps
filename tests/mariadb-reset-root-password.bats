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
    ! grep -q '^run' "$STUB_COMPOSE_LOG"
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
