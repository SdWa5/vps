#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    export STUB_DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    : > "$STUB_DOCKER_LOG"
    export STUB_MYSQL_ERROR_LOG='2026-10-24T14:03:55Z 0 [System] [MY-010910] [Server] /usr/sbin/mysqld: Shutdown complete'
}

teardown() {
    [[ -n "${FAKE_MYSQLD:-}" ]] && kill -KILL "$FAKE_MYSQLD" 2>/dev/null
    return 0
}

# Starts a process that stands in for the container's mysqld. The subshell
# exits at once, so init reaps it and `kill -0` does not see a zombie.
fake_mysqld() {
    FAKE_MYSQLD="$(bash -c "($1 exec sleep 300) >/dev/null 2>&1 & echo \$!")"
    export STUB_DOCKER_TOP="$FAKE_MYSQLD mysqld"
}

stop_dockware() {
    run bash "$REPO_ROOT/tools/shopware/stop-dockware.sh" "$@"
}

@test "mysqld gets SIGTERM and the container stops after the shutdown marker" {
    fake_mysqld ''
    stop_dockware shopware
    [ "$status" -eq 0 ]
    ! kill -0 "$FAKE_MYSQLD" 2>/dev/null || false
    [[ "$output" == *'shopware stopped with a clean MySQL shutdown.'* ]]
    grep -qx 'stop shopware' "$STUB_DOCKER_LOG"
}

@test "a mysqld that outlives the timeout leaves the container running" {
    fake_mysqld 'trap "" TERM;'
    STOP_TIMEOUT=1 stop_dockware shopware
    [ "$status" -eq 1 ]
    [[ "$output" == *'still runs after 1 s'* ]]
    ! grep -q '^stop' "$STUB_DOCKER_LOG" || false
}

@test "no mysqld still needs the shutdown marker, because a crash leaves none" {
    stop_dockware shopware
    [ "$status" -eq 0 ]
    [[ "$output" == *'No mysqld runs in shopware.'* ]]
    grep -qx 'stop shopware' "$STUB_DOCKER_LOG"

    : > "$STUB_DOCKER_LOG"
    STUB_MYSQL_ERROR_LOG='[ERROR] [MY-012574] [InnoDB] Unable to lock ./ibdata1' stop_dockware shopware
    [ "$status" -eq 1 ]
    [[ "$output" == *'No "Shutdown complete"'* ]]
    ! grep -q '^stop' "$STUB_DOCKER_LOG" || false
}

@test "a container that is not running is left alone" {
    export STUB_CONTAINER_chimodiazz_shopware=false
    stop_dockware chimodiazz_shopware
    [ "$status" -eq 0 ]
    [[ "$output" == *'not running, nothing to stop'* ]]
    ! grep -qE '^(top|exec|stop)' "$STUB_DOCKER_LOG" || false
}

@test "missing, invalid and extra arguments fail before docker is asked" {
    stop_dockware
    [ "$status" -eq 2 ]
    stop_dockware '../x'
    [ "$status" -eq 2 ]
    stop_dockware shopware --now
    [ "$status" -eq 2 ]
    STOP_TIMEOUT=soon stop_dockware shopware
    [ "$status" -eq 2 ]
    [ ! -s "$STUB_DOCKER_LOG" ]
    stop_dockware --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'tools/shopware/stop-dockware.sh CONTAINER'* ]]
}
