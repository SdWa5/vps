#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The script reads its images and environment from the repository's
# docker-compose.yml, so these cases follow its shopware and shopware_db services.

setup() {
    export DEV_SCRIPT="$BATS_TEST_DIRNAME/../tools/shopware/dev-instance.sh"
    export COMPOSE_FILE_PATH="$BATS_TEST_DIRNAME/../docker-compose.yml"
    export SDWA5_SHOPWARE_DEV_DIR="$BATS_TEST_TMPDIR/dev"
    export DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
    chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

# A docker that logs every call, one argument per line after the CALL line,
# and answers like a neutralised copy. Each assertion's query can be made to
# return a wrong value: MAIL, FOREIGN_DOMAINS, LOCAL_DOMAINS, SHOPMON, APPS.
fake_docker() {
    cat > "$BATS_TEST_TMPDIR/bin/docker" <<'STUB'
#!/bin/bash
printf 'CALL %s\n' "$*" >> "$DOCKER_LOG"
for arg in "$@"; do printf 'ARG %s\n' "$arg" >> "$DOCKER_LOG"; done
if [[ " $* " == *' -i '* && " $* " == *' mysql '* && " $* " != *'--execute'* ]]; then
    sed 's/^/STDIN /' >> "$DOCKER_LOG"
fi
case "$*" in
    *"configuration_key = 'core.mailerSettings.disableDelivery'"*) printf '%s\n' "${MAIL:-true}" ;;
    *"configuration_key = 'core.staging'"*) printf 'true\n' ;;
    *"NOT LIKE 'http://localhost:8090%'"*) printf '%s\n' "${FOREIGN_DOMAINS:-0}" ;;
    *"url LIKE 'http://localhost:8090%'"*) printf '%s\n' "${LOCAL_DOMAINS:-2}" ;;
    *"name = 'FroshShopmon'"*) printf '%s\n' "${SHOPMON:-0}" ;;
    *'FROM app'*) printf '%s\n' "${APPS:-0}" ;;
    *'system:check'*) exit "${CHECK_FAIL:-0}" ;;
    *'shopware-deployment-helper run'*) exit "${HELPER_FAIL:-0}" ;;
    'inspect --format {{.State.Running}}'*) printf 'true\n' ;;
    'inspect --format {{.State.Status}}'*) printf 'running\n' ;;
    'inspect --format {{.Image}}'*) printf 'sha256:abc\n' ;;
    *'.Internal'*) printf 'none\n' ;;
    'network inspect '*) exit 1 ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

data_with() {
    mkdir -p "$BATS_TEST_TMPDIR/data"
    for dir in "$@"; do mkdir -p "$BATS_TEST_TMPDIR/data/$dir"; printf 'x\n' > "$BATS_TEST_TMPDIR/data/$dir/f"; done
    tar -czf "$BATS_TEST_TMPDIR/data.tar.gz" -C "$BATS_TEST_TMPDIR/data" "$@"
}

archive_with_coverage() {
    mkdir -p "$BATS_TEST_TMPDIR/archive"
    printf 'CREATE DATABASE shopware;\n' > "$BATS_TEST_TMPDIR/archive/dump.sql"
    printf 'database\tshopware\ncoverage\t%s\n' "$1" > "$BATS_TEST_TMPDIR/archive/manifest.tsv"
    tar -czf "$BATS_TEST_TMPDIR/archive.tar.gz" -C "$BATS_TEST_TMPDIR/archive" dump.sql manifest.tsv
}

# An ssh that serves the data for the tar command and the archive for cat,
# and logs each remote command.
fake_ssh() {
    stub ssh "printf '%s\n' \"\$2\" >> '$SSH_LOG'
case \"\$2\" in
    tar*) cat '$BATS_TEST_TMPDIR/data.tar.gz' ;;
    cat*) cat '$BATS_TEST_TMPDIR/archive.tar.gz' ;;
esac"
}

fetched_copy() {
    mkdir -p "$SDWA5_SHOPWARE_DEV_DIR"
    data_with files media thumbnail sitemap
    archive_with_coverage "${1:-full}"
    cp "$BATS_TEST_TMPDIR/data.tar.gz" "$BATS_TEST_TMPDIR/archive.tar.gz" "$SDWA5_SHOPWARE_DEV_DIR/"
}

line_of() { grep -n -F -m1 -- "$1" "$DOCKER_LOG" | cut -d: -f1; }

# The arguments of the first call that contains $1, one per line.
args_of() {
    awk -v needle="$1" '
        /^CALL / { if (found) exit; if (index($0, needle)) { found = 1 }; next }
        found && /^ARG / { sub(/^ARG /, ""); print }' "$DOCKER_LOG"
}

compose_service_image() {
    awk -v service="  $1:" '$0 == service { f = 1; next } f && /^  [a-z_]+:$/ { exit } f && /^ +image:/ { print $2; exit }' "$COMPOSE_FILE_PATH"
}

@test "without a command it prints the usage and does nothing" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *'Shopware mirror of sdwa5.org'* ]]
    [[ "$output" == *'SDWA5_SHOPWARE_ARCHIVE'* ]]
    [[ "$output" != *'set -euo pipefail'* ]]
}

@test "an unknown command fails, and composer moved to image.sh" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT" deploy
    [ "$status" -eq 1 ]
    [[ "$output" == *'unknown command: deploy'* ]]
    run bash "$DEV_SCRIPT" composer install
    [ "$status" -eq 1 ]
    run bash "$DEV_SCRIPT" --help
    [[ "$output" == *'image.sh composer'* ]]
}

@test "the images follow the production compose file" {
    run bash -c 'source "$DEV_SCRIPT"; app_image'
    [[ "$output" == localhost/sdwa5-shopware:* ]]
    [ "$output" = "$(compose_service_image shopware)" ]
    run bash -c 'source "$DEV_SCRIPT"; db_image'
    [[ "$output" == mysql:8.4* ]]
    [ "$output" = "$(compose_service_image shopware_db)" ]
}

@test "explicit images override the compose pins" {
    run env SDWA5_SHOPWARE_DEV_IMAGE=localhost/sdwa5-shopware:6.7.16.0-1 bash -c 'source "$DEV_SCRIPT"; app_image'
    [ "$output" = 'localhost/sdwa5-shopware:6.7.16.0-1' ]
    run env SDWA5_SHOPWARE_DEV_DB_IMAGE=mysql:8.4.14 bash -c 'source "$DEV_SCRIPT"; db_image'
    [ "$output" = 'mysql:8.4.14' ]
}

@test "fetch reads the data and the archive with the new defaults and drops the public/ prefix" {
    data_with files media thumbnail sitemap
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -eq 0 ]
    [ -s "$SDWA5_SHOPWARE_DEV_DIR/data.tar.gz" ]
    [ -s "$SDWA5_SHOPWARE_DEV_DIR/archive.tar.gz" ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/data.tar.gz.part" ]
    [ "$(stat -c %a "$SDWA5_SHOPWARE_DEV_DIR")" = 700 ]
    [ "$(wc -l < "$SSH_LOG")" -eq 2 ]
    grep -qx "tar -C /opt/docker/shopware-data --transform 's,^public/,,' -czf - files media thumbnail sitemap " "$SSH_LOG"
    grep -qx 'cat /opt/docker/database-backup/shopware_db.tar.gz' "$SSH_LOG"
}

@test "fetch takes the dockware paths for the rehearsal" {
    data_with files media thumbnail sitemap
    archive_with_coverage full
    fake_ssh
    run env SDWA5_SHOPWARE_DATA=/opt/docker/shopware-html-data \
        SDWA5_SHOPWARE_DATA_PATHS='files public/media public/thumbnail public/sitemap' \
        SDWA5_SHOPWARE_ARCHIVE=/opt/docker/database-backup/shopware.tar.gz bash "$DEV_SCRIPT" fetch
    [ "$status" -eq 0 ]
    grep -q '^tar -C /opt/docker/shopware-html-data .* files public/media public/thumbnail public/sitemap $' "$SSH_LOG"
    grep -qx 'cat /opt/docker/database-backup/shopware.tar.gz' "$SSH_LOG"
}

@test "fetch deletes the dockware era's copy and integration keys" {
    mkdir -p "$SDWA5_SHOPWARE_DEV_DIR"
    printf 'x' > "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz"
    printf 'x' > "$SDWA5_SHOPWARE_DEV_DIR/integration.env"
    data_with files media thumbnail sitemap
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -eq 0 ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz" ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/integration.env" ]
}

@test "fetch rejects data without one of its paths" {
    data_with files media thumbnail
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [[ "$output" == *'no sitemap/'* ]]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/data.tar.gz" ]
}

@test "fetch rejects a truncated download" {
    stub ssh "printf 'not gzip'"
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/data.tar.gz" ]
}

@test "restore refuses to run without a fetched copy" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'Run fetch first'* ]]
}

@test "restore refuses a tables-only archive" {
    fetched_copy tables-only
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'not a full dump'* ]]
}

@test "restore unpacks the data into five volumes owned by www-data" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    args="$(args_of 'run --rm --network none')"
    for volume in files media thumbnail sitemap theme; do
        grep -qx -- "type=volume,src=sdwa5-shopware-dev-$volume,dst=/data/$volume,volume-nocopy=true" <<<"$args"
    done
    grep -qx -- '--user' <<<"$args"
    grep -qx 'tar -xzf /import/data.tar.gz -C /data && chown -R 82:82 /data' <<<"$args"
}

@test "the database is only on the internal network and stops cleanly" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    grep -q '^CALL network create --internal sdwa5-shopware-dev$' "$DOCKER_LOG"
    db="$(grep '^CALL run --detach --name sdwa5_shopware_dev_db ' "$DOCKER_LOG")"
    [[ "$db" == *'--network sdwa5-shopware-dev '* ]]
    [[ "$db" == *'--stop-timeout 60 '* ]]
    [[ "$db" == *' --mysqlx=OFF' ]]
    [[ "$db" != *'--publish'* ]]
    [[ "$db" != *'-web'* ]]
}

@test "restore imports the archive into the database container" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    grep -qx 'STDIN CREATE DATABASE shopware;' "$DOCKER_LOG"
}

@test "the app runs restricted with the compose env and the mirror's overrides" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    args="$(args_of 'run --detach --name sdwa5-shopware-dev --hostname sdwa5-shopware-dev ')"
    grep -qx -- 'ALL' <<<"$args"
    grep -qx -- 'no-new-privileges:true' <<<"$args"
    grep -qx -- 'sdwa5-shopware-dev' <<<"$args"
    run ! grep -q -- '--publish\|^-p$' <<<"$args"
    # A compose value with a space arrives as one argument.
    grep -qx 'FRANKENPHP_CONFIG=num_threads 5' <<<"$args"
    grep -qx 'APP_URL=http://localhost:8090' <<<"$args"
    grep -qx 'MAILER_DSN=null://null' <<<"$args"
    grep -qx 'DATABASE_URL=mysql://shopware:shopware@sdwa5_shopware_dev_db:3306/shopware' <<<"$args"
    grep -qE '^APP_SECRET=[0-9a-f]{64}$' <<<"$args"
    grep -qx 'type=bind,src=.*/hardening/php/99-php-security-mitigation.ini,dst=/usr/local/etc/php/conf.d/99-php-security-mitigation.ini,readonly' <<<"$args"
    # The overrides follow the compose values, so Docker keeps them.
    [ "$(grep -n '^APP_URL=' <<<"$args" | tail -1 | cut -d: -f2-)" = 'APP_URL=http://localhost:8090' ]
}

@test "the new APP_SECRET is never printed" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [[ "$output" != *'APP_SECRET'* ]]
}

@test "only the proxy publishes, on 127.0.0.1" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$(grep -c -- '^CALL .*--publish' "$DOCKER_LOG")" -eq 1 ]
    grep -q -- '^CALL run --detach --name sdwa5-shopware-dev-proxy .*--publish 127.0.0.1:8090:8080 alpine/socat:.* TCP:sdwa5-shopware-dev:8000$' "$DOCKER_LOG"
}

@test "the helper runs in staging mode in a one-off container before the app starts" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    [[ "$output" == *'Deployment helper took '*'s.'* ]]
    helper="$(line_of 'vendor/bin/shopware-deployment-helper run --skip-assets-install')"
    app="$(line_of 'run --detach --name sdwa5-shopware-dev --hostname')"
    [ -n "$helper" ] && [ "$helper" -lt "$app" ]
    grep -q '^CALL run --rm --network sdwa5-shopware-dev .*SHOPWARE_DEPLOYMENT_STAGING=1 localhost/sdwa5-shopware:[^ ]* vendor/bin/shopware-deployment-helper run --skip-assets-install$' "$DOCKER_LOG"
    [ "$(grep -c '^CALL .*SHOPWARE_DEPLOYMENT_STAGING' "$DOCKER_LOG")" -eq 1 ]
}

@test "a failing helper run stops before the app starts" {
    fetched_copy
    fake_docker
    run env HELPER_FAIL=1 bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    run ! grep -q '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG"
}

@test "each failed assertion dies before the app starts" {
    fetched_copy
    fake_docker
    for case in MAIL=false FOREIGN_DOMAINS=1 LOCAL_DOMAINS=0 SHOPMON=1 APPS=1; do
        rm -f "$DOCKER_LOG"
        run env "$case" bash "$DEV_SCRIPT" restore
        [ "$status" -ne 0 ]
        run ! grep -q '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG"
        run ! grep -q '^CALL run --detach --name sdwa5-shopware-dev-proxy' "$DOCKER_LOG"
    done
}

@test "system:check runs in the app and the proxy starts after it" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    check="$(line_of 'exec sdwa5-shopware-dev php bin/console --no-interaction system:check --context=pre_rollout')"
    proxy="$(line_of 'run --detach --name sdwa5-shopware-dev-proxy')"
    [ -n "$check" ] && [ "$check" -lt "$proxy" ]
}

@test "a failing system:check stops before the proxy" {
    fetched_copy
    fake_docker
    run env CHECK_FAIL=1 bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'system:check failed'* ]]
    run ! grep -q 'sdwa5-shopware-dev-proxy alpine' "$DOCKER_LOG"
}

@test "restore fails on a storefront that answers with an error" {
    fetched_copy
    fake_docker
    stub curl "printf 500"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'storefront answered 500'* ]]
}

@test "up asserts the copy again and only reports a storefront in maintenance mode" {
    fetched_copy
    fake_docker
    stub curl "printf 503"
    run bash "$DEV_SCRIPT" up
    [ "$status" -eq 0 ]
    [[ "$output" == *'The storefront answers 503.'* ]]
    [[ "$output" == *'application	running'* ]]
    grep -q "name = 'FroshShopmon'" "$DOCKER_LOG"
    run ! grep -q 'SHOPWARE_DEPLOYMENT_STAGING' "$DOCKER_LOG"
}

@test "up refuses a copy that fails an assertion" {
    fetched_copy
    fake_docker
    run env MAIL=false bash "$DEV_SCRIPT" up
    [ "$status" -ne 0 ]
    run ! grep -q '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG"
}

@test "purge removes six volumes and the fetched copies" {
    fetched_copy
    fake_docker
    run bash "$DEV_SCRIPT" purge
    [ "$status" -eq 0 ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR" ]
    grep -qx 'CALL volume rm --force sdwa5-shopware-dev-files sdwa5-shopware-dev-media sdwa5-shopware-dev-thumbnail sdwa5-shopware-dev-sitemap sdwa5-shopware-dev-theme sdwa5-shopware-dev-mysql' "$DOCKER_LOG"
}

@test "console passes its arguments to bin/console in the mirror" {
    fake_docker
    run bash "$DEV_SCRIPT" console cache:clear
    [ "$status" -eq 0 ]
    grep -q '^CALL exec -i sdwa5-shopware-dev php bin/console cache:clear$' "$DOCKER_LOG"
}

@test "status reports both containers, their images, mail and staging" {
    fetched_copy
    fake_docker
    run bash "$DEV_SCRIPT" status
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "application	running	$(compose_service_image shopware)	sha256:abc" ]]
    [[ "${lines[1]}" == "database	running	$(compose_service_image shopware_db)	sha256:abc" ]]
    [[ "$output" == *'mails	disabled'* ]]
    [[ "$output" == *'staging	on'* ]]
    [[ "$output" == *'url	http://localhost:8090/'* ]]
}

@test "status of a stopped mirror shows absent on the same line" {
    stub docker "printf '\\n'; exit 1"
    run bash "$DEV_SCRIPT" status
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "application	absent	$(compose_service_image shopware)	absent" ]
    [ "${lines[1]}" = "database	absent	$(compose_service_image shopware_db)	absent" ]
    [ "${lines[2]}" = 'proxy	absent	127.0.0.1:8090' ]
    [ "${lines[3]}" = 'egress	absent' ]
    [ "${#lines[@]}" -eq 4 ]
}
