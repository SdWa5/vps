#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# deploy.sh runs against a temporary COMPOSE_DIR with a stub
# monitoring/database-backup.sh, and against a docker stub that logs every call.

setup() {
    export DEPLOY_SCRIPT="$BATS_TEST_DIRNAME/../tools/shopware/deploy.sh"
    export REPO="$BATS_TEST_DIRNAME/.."
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    export DATABASE_BACKUP_DIR="$BATS_TEST_TMPDIR/backup"
    export SHOPWARE_DEPLOY_LOCK="$BATS_TEST_TMPDIR/worker.lock"
    export SHOPWARE_DEPLOY_LOCK_WAIT=1
    export DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    mkdir -p "$BATS_TEST_TMPDIR/bin" "$COMPOSE_DIR/monitoring" "$DATABASE_BACKUP_DIR"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    cat > "$COMPOSE_DIR/docker-compose.yml" <<'YAML'
services:
  shopware:
    image: localhost/sdwa5-shopware:6.7.15.1-2
  shopware_db:
    image: mysql:8.4
YAML
    # BACKUP_FAIL=1 fails the backup, BACKUP_OLD=1 leaves an archive from before the run.
    cat > "$COMPOSE_DIR/monitoring/database-backup.sh" <<'STUB'
#!/bin/bash
printf 'CALL backup %s\n' "$DATABASE_BACKUP_CONTAINERS" >> "$DOCKER_LOG"
[[ "${BACKUP_FAIL:-0}" == 1 ]] && exit 1
if [[ "${BACKUP_OLD:-0}" == 1 ]]; then
    touch -d '2020-01-01' "$DATABASE_BACKUP_DIR/shopware_db.tar.gz"
else
    touch "$DATABASE_BACKUP_DIR/shopware_db.tar.gz"
fi
STUB
    chmod +x "$COMPOSE_DIR/monitoring/database-backup.sh"
    fake_docker
}

# IMAGE_MISSING, NOT_INSTALLED, HELPER_FAIL and CHECK_FAIL fail their call,
# MAINTENANCE sets the count of sales channels in maintenance.
fake_docker() {
    cat > "$BATS_TEST_TMPDIR/bin/docker" <<'STUB'
#!/bin/bash
printf 'CALL %s\n' "$*" >> "$DOCKER_LOG"
case "$*" in
    'image inspect '*) exit "${IMAGE_MISSING:-0}" ;;
    *'shopware-deployment-helper is-installed') exit "${NOT_INSTALLED:-0}" ;;
    *'shopware-deployment-helper run '*) exit "${HELPER_FAIL:-0}" ;;
    *'system:check'*) exit "${CHECK_FAIL:-0}" ;;
    'exec shopware_db sh -c '*) printf '%s\n' "${MAINTENANCE:-0}" ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

line_of() { grep -n -F -m1 -- "$1" "$DOCKER_LOG" | cut -d: -f1; }

ONE_OFF='compose run --rm --no-deps -T --name shopware-deploy shopware'

@test "--help exits 0 and an argument exits 2" {
    run bash "$DEPLOY_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'never installs a shop'* ]]
    run bash "$DEPLOY_SCRIPT" now
    [ "$status" -eq 2 ]
}

@test "a missing image dies before any up" {
    run env IMAGE_MISSING=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'localhost/sdwa5-shopware:6.7.15.1-2 is not on this host'* ]]
    run ! grep -q 'compose up' "$DOCKER_LOG"
}

@test "a lock the worker holds dies before any up" {
    exec 8>"$SHOPWARE_DEPLOY_LOCK"
    flock 8
    run bash "$DEPLOY_SCRIPT"
    exec 8>&-
    [ "$status" -eq 1 ]
    [[ "$output" == *'the worker still holds'* ]]
    run ! grep -q 'compose up' "$DOCKER_LOG"
}

@test "a database without an installed shop dies before the backup" {
    run env NOT_INSTALLED=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'never installs one'* ]]
    run ! grep -q 'CALL backup' "$DOCKER_LOG"
}

@test "a failing backup dies before the helper runs" {
    run env BACKUP_FAIL=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'backup of shopware_db failed'* ]]
    run ! grep -q 'deployment-helper run' "$DOCKER_LOG"
}

@test "a backup that leaves an older archive dies before the helper runs" {
    run env BACKUP_OLD=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'no fresh backup'* ]]
    run ! grep -q 'deployment-helper run' "$DOCKER_LOG"
}

@test "the happy path runs every step in order through one-off containers" {
    run bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Deployed localhost/sdwa5-shopware:6.7.15.1-2.'* ]]
    grep -qx 'CALL backup shopware_db' "$DOCKER_LOG"
    db="$(line_of 'compose up -d --no-deps shopware_db')"
    ping="$(line_of 'exec shopware_db mysqladmin')"
    installed="$(line_of "$ONE_OFF vendor/bin/shopware-deployment-helper is-installed")"
    backup="$(line_of 'CALL backup')"
    helper="$(line_of "$ONE_OFF vendor/bin/shopware-deployment-helper run --skip-assets-install")"
    check="$(line_of "$ONE_OFF php bin/console system:check --context=pre_rollout --no-interaction")"
    up="$(line_of 'compose up -d --no-deps --wait --wait-timeout 360 shopware')"
    [ -n "$db" ] && [ -n "$up" ]
    [ "$db" -lt "$ping" ] && [ "$ping" -lt "$installed" ] && [ "$installed" -lt "$backup" ]
    [ "$backup" -lt "$helper" ] && [ "$helper" -lt "$check" ] && [ "$check" -lt "$up" ]
    run ! grep -q 'restart' "$DOCKER_LOG"
}

@test "a failing helper run stops before the switch" {
    run env HELPER_FAIL=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'old container still serves'* ]]
    run ! grep -q 'compose up -d --no-deps --wait' "$DOCKER_LOG"
}

@test "a failing system:check stops before the switch" {
    run env CHECK_FAIL=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'system:check failed'* ]]
    run ! grep -q 'compose up -d --no-deps --wait' "$DOCKER_LOG"
}

@test "maintenance mode skips system:check and still switches" {
    run env MAINTENANCE=1 bash "$DEPLOY_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Skipping system:check: a sales channel is in maintenance mode.'* ]]
    run ! grep -q 'system:check' "$DOCKER_LOG"
    grep -q 'compose up -d --no-deps --wait' "$DOCKER_LOG"
}

@test "the helper config refuses a fresh install and compiles the theme synchronously" {
    config="$REPO/shopware-html-data/.shopware-project.yml"
    grep -qE '^    pre-install: \|$' "$config"
    grep -qE '^      exit 1$' "$config"
    grep -qE '^    force-theme-compile-sync: true$' "$config"
}

@test "only the mirror sets SHOPWARE_DEPLOYMENT_STAGING" {
    cd "$REPO"
    run grep -rl SHOPWARE_DEPLOYMENT_STAGING docker-compose*.yml shopware monitoring tools
    [ "$output" = 'tools/shopware/dev-instance.sh' ]
}
