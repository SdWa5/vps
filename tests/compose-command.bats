#!/usr/bin/env bats
# Tests for tools/compose.sh, the choice between Compose v2 and v1.

load test_helper

setup() {
    common_setup
    unset DOCKER_COMPOSE
    export STUB_COMPOSE_LOG="$BATS_TEST_TMPDIR/compose.log"
    : > "$STUB_COMPOSE_LOG"
}

pick() {
    run bash -c '. "$REPO_ROOT/tools/compose.sh" && printf "%s\n" "$DOCKER_COMPOSE"'
}

@test "without the v2 plugin it falls back to docker-compose" {
    pick
    [ "$status" -eq 0 ]
    [ "$output" = docker-compose ]
}

@test "with the v2 plugin it uses docker compose" {
    export STUB_COMPOSE_PLUGIN=1
    pick
    [ "$output" = "docker compose" ]
}

@test "a DOCKER_COMPOSE set by the caller wins" {
    export STUB_COMPOSE_PLUGIN=1 DOCKER_COMPOSE=docker-compose
    pick
    [ "$output" = docker-compose ]
}

@test "monitoring scripts reach Compose v2 through lib.sh" {
    export STUB_COMPOSE_PLUGIN=1
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    mkdir -p "$COMPOSE_DIR/vaultwarden-data"
    echo db > "$COMPOSE_DIR/vaultwarden-data/db.sqlite3"
    export STUB_IMAGE_ID="sha256:old"
    mkdir -p "$STATE_DIR"
    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/last-run"
    autoupdate
    grep -qx "pull vaultwarden" "$STUB_COMPOSE_LOG"
}

@test "the MariaDB reset names the Compose command the host has" {
    export STUB_COMPOSE_PLUGIN=1 STUB_COMPOSE_PS=dbid
    run bash "$REPO_ROOT/tools/mariadb/reset-root-password.sh" dolibarr_db
    [ "$status" -eq 1 ]
    [[ "$output" == *'Stop dolibarr_db first: docker compose stop dolibarr_db'* ]]
    grep -qx "ps -q dolibarr_db" "$STUB_COMPOSE_LOG"
}
