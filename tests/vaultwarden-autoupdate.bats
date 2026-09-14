#!/usr/bin/env bats
# Tests for monitoring/vaultwarden-autoupdate.sh

load test_helper

setup() {
    common_setup

    # An isolated compose project, so nothing touches the real /opt/docker.
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    export DATA_DIR="$COMPOSE_DIR/vaultwarden-data"
    mkdir -p "$DATA_DIR"
    echo "db" > "$DATA_DIR/db.sqlite3"

    export DOCKER_COMPOSE=docker-compose
    export STUB_COMPOSE_LOG="$BATS_TEST_TMPDIR/compose.log"
    : > "$STUB_COMPOSE_LOG"

    export STUB_IMAGE_ID="sha256:old"
    export HEALTH_TIMEOUT=5

    # The health monitor is alive unless a test says otherwise.
    mkdir -p "$STATE_DIR"
    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/last-run"
}

@test "dry run reports the state and changes nothing" {
    autoupdate --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"sha256:old"* ]]
    [[ "$output" == *"1.37.2"* ]]
    [ "$(mail_count)" -eq 0 ]
    [ ! -s "$STUB_COMPOSE_LOG" ]
}

@test "an unchanged image exits silently" {
    autoupdate
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
    run ls -d "$DATA_DIR".bak-* 2>/dev/null
    [ "$status" -ne 0 ]
}

@test "an unchanged image still pulls, so drift is actually detected" {
    autoupdate
    grep -q "pull vaultwarden" "$STUB_COMPOSE_LOG"
}

@test "a failed pull reports and leaves the container alone" {
    STUB_PULL_RC=1 autoupdate
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"pull failed"* ]]
}

@test "a stale health monitor is reported" {
    touch -d '-4 hours' "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"health monitoring has stopped"* ]]
}

@test "a health monitor that never ran is reported" {
    rm -f "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"has never run"* ]]
}

@test "a fresh health monitor is not reported" {
    autoupdate
    [ "$(mail_count)" -eq 0 ]
}

# This alarm has no backoff of its own. While the job ran weekly that cost one mail a week, and the
# move to daily would have made it one a day for as long as the condition lasted.

@test "the stale health monitor alarm does not repeat on the next day's run" {
    touch -d '-4 hours' "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]
    autoupdate
    [ "$(mail_count)" -eq 1 ]
}

@test "the stale health monitor alarm comes back after a week" {
    touch -d '-4 hours' "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]
    touch -d '-8 days' "$STATE_DIR/autoupdate-health-alerted"
    autoupdate
    [ "$(mail_count)" -eq 2 ]
}

@test "a recovered health monitor clears the hold, so the next failure alerts at once" {
    # Otherwise a problem that fixes itself and comes back two days later stays silent for five more,
    # which is the same trap vps-health.sh's own backoff avoids by resetting on recovery.
    touch -d '-4 hours' "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]

    date '+%Y-%m-%d %H:%M:%S' > "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 1 ]

    touch -d '-4 hours' "$STATE_DIR/last-run"
    autoupdate
    [ "$(mail_count)" -eq 2 ]
}

@test "a failed alarm delivery does not count as delivered" {
    # The stamp is written only after send_mail returns success, so a broken SMTP path leaves the
    # alarm due rather than swallowing it for a week.
    touch -d '-4 hours' "$STATE_DIR/last-run"
    STUB_MAIL_RC=1 autoupdate
    [ ! -f "$STATE_DIR/autoupdate-health-alerted" ]
    autoupdate
    [[ "$(mail_body)" == *"health monitoring has stopped"* ]]
}

@test "an unknown option is rejected" {
    autoupdate --nonsense
    [ "$status" -eq 2 ]
}

# --- the update path ------------------------------------------------------
#
# The docker stub reads STUB_IMAGE_ID fresh on every call, so writing a new
# value into a file the stub sources is not possible. Instead the image ID is
# switched by a wrapper that flips an env var between the two inspect calls.

@test "a new image is snapshotted, applied and confirmed healthy" {
    cat > "$BATS_TEST_TMPDIR/flip" <<'FLIP'
#!/usr/bin/env bash
# First "docker image inspect" answers old, every later one answers new.
marker="$BATS_TEST_TMPDIR/flipped"
if [[ "${1:-}" == "image" ]]; then
    if [[ -f "$marker" ]]; then echo "sha256:new"; else touch "$marker"; echo "sha256:old"; fi
    exit 0
fi
exec "$STUBS/docker" "$@"
FLIP
    chmod +x "$BATS_TEST_TMPDIR/flip"
    cp "$BATS_TEST_TMPDIR/flip" "$BATS_TEST_TMPDIR/bin_docker"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    mv "$BATS_TEST_TMPDIR/bin_docker" "$BATS_TEST_TMPDIR/bin/docker"
    export STUBS="$BATS_TEST_DIRNAME/stubs"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    autoupdate
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"Vaultwarden updated"* ]]
    run ls -d "$DATA_DIR".bak-*
    [ "$status" -eq 0 ]
    grep -q "up -d vaultwarden" "$STUB_COMPOSE_LOG"
}

@test "an update that never becomes healthy is rolled back and pinned" {
    cat > "$BATS_TEST_TMPDIR/bin_docker" <<'FLIP'
#!/usr/bin/env bash
marker="$BATS_TEST_TMPDIR/flipped"
if [[ "${1:-}" == "image" ]]; then
    if [[ -f "$marker" ]]; then echo "sha256:new"; else touch "$marker"; echo "sha256:old"; fi
    exit 0
fi
exec "$STUBS/docker" "$@"
FLIP
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    mv "$BATS_TEST_TMPDIR/bin_docker" "$BATS_TEST_TMPDIR/bin/docker"
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    export STUBS="$BATS_TEST_DIRNAME/stubs"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    STUB_HTTP_CODE=502 autoupdate
    [ "$status" -eq 1 ]
    [[ "$(mail_body)" == *"rolled back"* ]]
    [ -f "$COMPOSE_DIR/docker-compose.override.yml" ]
    grep -q "sha256:old" "$COMPOSE_DIR/docker-compose.override.yml"
    # The data directory came back from the snapshot.
    [ -f "$DATA_DIR/db.sqlite3" ]
}

# --- snapshot retention ---------------------------------------------------

@test "snapshot retention keeps the newest three" {
    export SNAPSHOTS_TO_KEEP=3
    local i
    for i in 1 2 3 4 5; do
        mkdir -p "${DATA_DIR}.bak-2026010${i}-0000"
        touch -d "2026-01-0${i}" "${DATA_DIR}.bak-2026010${i}-0000"
    done

    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/docker" <<'FLIP'
#!/usr/bin/env bash
marker="$BATS_TEST_TMPDIR/flipped"
if [[ "${1:-}" == "image" ]]; then
    if [[ -f "$marker" ]]; then echo "sha256:new"; else touch "$marker"; echo "sha256:old"; fi
    exit 0
fi
exec "$STUBS/docker" "$@"
FLIP
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
    export STUBS="$BATS_TEST_DIRNAME/stubs"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

    autoupdate
    [ "$status" -eq 0 ]
    run bash -c "ls -1d '${DATA_DIR}'.bak-* | wc -l"
    [ "$output" -eq 3 ]
    # The two oldest are gone, the fresh snapshot survived.
    [ ! -d "${DATA_DIR}.bak-20260101-0000" ]
    [ ! -d "${DATA_DIR}.bak-20260102-0000" ]
}
