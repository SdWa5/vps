#!/usr/bin/env bats
# Tests for monitoring/sandbox-check.sh
#
# The probes run through as_sandbox, so the setpriv stub answers them: STUB_SANDBOX_OPEN holds what a
# sandbox account reaches, STUB_SANDBOX_ACCESS the paths it may read, enter or write.

load test_helper

setup() {
    common_setup
    unset SANDBOX_CHECK
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    mkdir -p "$COMPOSE_DIR"
    SANDBOX_HOME="$BATS_TEST_TMPDIR/home/chimodiazz"
    mkdir -p "$SANDBOX_HOME"
    chmod 700 "$SANDBOX_HOME"
    export STUB_GETENT_GROUP='sandbox:x:998:chimodiazz'
    export STUB_GETENT_PASSWD="chimodiazz:x:1001:1001::$SANDBOX_HOME:/usr/sbin/nologin"
    export STUB_SANDBOX_OPEN="sdwa5.org:443 1.1.1.1:443"
    export STUB_SANDBOX_ACCESS=""
    export SANDBOX_CONTAINER_PROBES=""
    export STUB_SETPRIV_LOG="$BATS_TEST_TMPDIR/setpriv.log"
    : > "$STUB_SETPRIV_LOG"
}

check() {
    run "$REPO_ROOT/monitoring/sandbox-check.sh" "$@"
}

@test "an isolated sandbox is OK and every probe ran as the account" {
    check
    [ "$status" -eq 0 ]
    [ "$output" = $'OK\t1 sandbox(es): no host loopback, no container network, no private path' ]
    grep -qF -- '--reuid=chimodiazz' "$STUB_SETPRIV_LOG"
    grep -qF -- 'probe 127.0.0.1 2019' "$STUB_SETPRIV_LOG"
    grep -qF -- 'probe ::1 25' "$STUB_SETPRIV_LOG"
}

@test "without sandbox accounts only the private data is checked" {
    unset STUB_GETENT_GROUP
    check
    [ "$output" = $'OK\tno sandbox accounts; private data closed' ]
    [ ! -s "$STUB_SETPRIV_LOG" ]
}

@test "a reachable loopback listener is critical" {
    export STUB_SANDBOX_OPEN="sdwa5.org:443 1.1.1.1:443 127.0.0.1:2019"
    check
    [ "$status" -eq 0 ]
    [ "$output" = $'CRIT\tchimodiazz reaches 127.0.0.1:2019' ]
}

@test "a reachable root-daemon container is critical" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nprintf "172.18.0.5 \\n"\n' > "$BATS_TEST_TMPDIR/bin/docker"
    chmod 755 "$BATS_TEST_TMPDIR/bin/docker"
    export SANDBOX_CONTAINER_PROBES="shopware_db:3306"
    export STUB_SANDBOX_OPEN="sdwa5.org:443 1.1.1.1:443 172.18.0.5:3306"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" check
    [[ "$output" == $'CRIT\tchimodiazz reaches shopware_db at 172.18.0.5:3306' ]]
}

@test "a readable private path is critical" {
    export SANDBOX_PRIVATE_PATHS="/root /var/run/docker.sock"
    export STUB_SANDBOX_ACCESS="/var/run/docker.sock"
    check
    [[ "$output" == CRIT* ]]
    [[ "$output" == *"chimodiazz passes test -w /var/run/docker.sock"* ]]
    [[ "$output" != *"/root"* ]]
}

@test "a sandbox home open to others is critical" {
    chmod 755 "$SANDBOX_HOME"
    check
    [[ "$output" == $'CRIT\tchimodiazz: home '"$SANDBOX_HOME"' has mode 755, not 700' ]]
}

@test "private data open to others is critical, also without sandbox accounts" {
    unset STUB_GETENT_GROUP
    mkdir -p "$COMPOSE_DIR/.git"
    chmod 755 "$COMPOSE_DIR/.git"
    check
    [ "$output" = $'CRIT\topen to others: .git' ]
}

@test "a failed positive control is a warning, not a breach" {
    export STUB_SANDBOX_OPEN="sdwa5.org:443"
    check
    [ "$output" = $'WARN\tchimodiazz cannot reach 1.1.1.1:443' ]
}

@test "an unknown option is a usage error" {
    check --bogus
    [ "$status" -eq 2 ]
}
