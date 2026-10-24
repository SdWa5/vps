#!/usr/bin/env bats

setup() {
    export DEV_SCRIPT="$BATS_TEST_DIRNAME/../tools/shopware/dev-instance.sh"
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

# A docker that logs every call with its stdin and answers like a healthy
# mirror. SHOP_ID_SUGGESTED=1 makes the first shop ID check suggest a change,
# SHOPMON_ACTIVE=1 reports FroshShopmon as active.
fake_docker() {
    cat > "$BATS_TEST_TMPDIR/bin/docker" <<'STUB'
#!/bin/bash
printf 'CALL %s\n' "$*" >> "$DOCKER_LOG"
if [[ " $* " == *' -i '* ]]; then sed 's/^/STDIN /' >> "$DOCKER_LOG"; fi
case "$*" in
    *'app:shop-id:check'*)
        count_file="$BATS_TEST_TMPDIR/shop-id-checks"
        count="$(cat "$count_file" 2>/dev/null || printf 0)"
        printf '%s' "$((count + 1))" > "$count_file"
        if [[ "${SHOP_ID_SUGGESTED:-0}" == 1 && "$count" == 0 ]]; then
            printf '[WARNING] Shop ID change suggested\n'
        elif [[ "${SHOP_ID_DELETED:-0}" == 1 && "$count" != 0 ]]; then
            printf '[OK] No shop ID has been generated yet.\n'
        else
            printf '[OK] Shop ID change not suggested.\n'
        fi ;;
    *'app:shop-id:change'*) exit 1 ;;
    *'integration:create'*)
        printf 'SHOPWARE_ACCESS_KEY_ID=SWIATESTKEY\nSHOPWARE_SECRET_ACCESS_KEY=topsecretvalue\n' ;;
    *'service/deactivate'*) exit "${SERVICES_API_FAIL:-0}" ;;
    *'self_managed = 1'*) printf '1\n' ;;
    *"name = 'FroshShopmon'"*) printf '%s\n' "${SHOPMON_ACTIVE:-0}" ;;
    *'system:config:get'*) printf 'core.mailerSettings.disableDelivery => true\n' ;;
    *'--version'*) printf 'Shopware 6.7.11.1 (env: prod, debug: false)\n' ;;
    'inspect --format {{.State.Running}}'*) printf 'true\n' ;;
    'inspect --format {{.State.Status}}'*) printf 'running\n' ;;
    *'.Internal'*) printf 'none\n' ;;
    'network inspect '*) exit 1 ;;
    *'grep -q ^# sdwa5 dev mirror'*) exit "${ENV_MARKER_MISSING:-0}" ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

shop_files_with() {
    mkdir -p "$BATS_TEST_TMPDIR/html"
    for file in "$@"; do printf 'x\n' > "$BATS_TEST_TMPDIR/html/$file"; done
    tar -czf "$BATS_TEST_TMPDIR/html.tar.gz" -C "$BATS_TEST_TMPDIR/html" .
}

archive_with_coverage() {
    mkdir -p "$BATS_TEST_TMPDIR/archive"
    printf 'CREATE DATABASE shopware;\n' > "$BATS_TEST_TMPDIR/archive/dump.sql"
    printf 'database\tshopware\ncoverage\t%s\n' "$1" > "$BATS_TEST_TMPDIR/archive/manifest.tsv"
    tar -czf "$BATS_TEST_TMPDIR/archive.tar.gz" -C "$BATS_TEST_TMPDIR/archive" dump.sql manifest.tsv
}

# An ssh that serves the shop files for the tar command and the archive for
# cat, and logs each remote command.
fake_ssh() {
    stub ssh "printf '%s\n' \"\$2\" >> '$SSH_LOG'
case \"\$2\" in
    tar*) cat '$BATS_TEST_TMPDIR/html.tar.gz' ;;
    cat*) cat '$BATS_TEST_TMPDIR/archive.tar.gz' ;;
esac"
}

fetched_copy() {
    mkdir -p "$SDWA5_SHOPWARE_DEV_DIR"
    shop_files_with composer.lock
    archive_with_coverage "${1:-full}"
    cp "$BATS_TEST_TMPDIR/html.tar.gz" "$BATS_TEST_TMPDIR/archive.tar.gz" "$SDWA5_SHOPWARE_DEV_DIR/"
}

line_of() { grep -n -F -m1 -- "$1" "$DOCKER_LOG" | cut -d: -f1; }

@test "without a command it prints the usage and does nothing" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *'Shopware mirror of sdwa5.org'* ]]
    [[ "$output" == *'SDWA5_SHOPWARE_ARCHIVE'* ]]
    [[ "$output" != *'set -euo pipefail'* ]]
}

@test "an unknown command fails" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT" deploy
    [ "$status" -eq 1 ]
    [[ "$output" == *'unknown command: deploy'* ]]
}

@test "a service name that is not lowercase alphanumeric is refused" {
    run env SDWA5_SHOPWARE_DEV_SERVICE='../x' bash "$DEV_SCRIPT" status
    [ "$status" -eq 2 ]
}

@test "the image follows the production compose file" {
    run bash -c 'source "$DEV_SCRIPT"; app_image'
    [ "$status" -eq 0 ]
    [[ "$output" == dockware/shopware:* ]]
    [ "$output" = "$(awk '/^  shopware:$/{f=1} f&&/image:/{print $2; exit}' "$BATS_TEST_DIRNAME/../docker-compose.yml")" ]
}

@test "an explicit image overrides the compose pin" {
    run env SDWA5_SHOPWARE_DEV_IMAGE=dockware/shopware:6.7.15.1 bash -c 'source "$DEV_SCRIPT"; app_image'
    [ "$output" = 'dockware/shopware:6.7.15.1' ]
}

@test "the PHP version follows the production compose file" {
    run bash -c 'source "$DEV_SCRIPT"; php_version'
    [ "$status" -eq 0 ]
    [ "$output" = 8.5 ]
}

@test "an explicit PHP version overrides the compose value, and an invalid one is refused" {
    run env SDWA5_SHOPWARE_DEV_PHP=8.4 bash -c 'source "$DEV_SCRIPT"; php_version'
    [ "$output" = 8.4 ]
    run env SDWA5_SHOPWARE_DEV_PHP='8.5; id' bash -c 'source "$DEV_SCRIPT"; php_version'
    [ "$status" -ne 0 ]
    [[ "$output" == *'is not MAJOR.MINOR'* ]]
}

@test "the mirror switches to the compose PHP and mounts the mitigation ini read-only" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    app="$(grep '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG")"
    [[ "$app" == *'--env PHP_VERSION=8.5 '* ]]
    [[ "$app" == *'/hardening/php/99-php-security-mitigation.ini,dst=/etc/php/8.5/fpm/conf.d/99-php-security-mitigation.ini,readonly '* ]]
}

@test "an empty PHP version keeps the image's own PHP" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    SDWA5_SHOPWARE_DEV_PHP='' run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    ! grep '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG" | grep -q -e PHP_VERSION -e mitigation || false
}

@test "composer runs on the mirror's PHP version" {
    fake_docker
    run bash "$DEV_SCRIPT" composer audit --locked
    [ "$status" -eq 0 ]
    grep -q -- '--entrypoint php8.5 .* /usr/local/bin/composer --no-interaction audit --locked$' "$DOCKER_LOG"
}

@test "a service without an image in the compose file is refused" {
    run env SDWA5_SHOPWARE_DEV_SERVICE=no_such_shop bash -c 'source "$DEV_SCRIPT"; app_image'
    [ "$status" -ne 0 ]
    [[ "$output" == *'no image for service no_such_shop'* ]]
}

@test "the service names the containers, volumes and data directory" {
    unset SDWA5_SHOPWARE_DEV_DIR
    run env SDWA5_SHOPWARE_DEV_SERVICE=other_shop bash -c 'source "$DEV_SCRIPT"; printf "%s %s %s" "$APP" "$HTML_VOLUME" "$DEV_DIR"'
    [ "$output" = "sdwa5-other-shop-dev sdwa5-other-shop-dev-html $HOME/.local/share/sdwa5-other-shop-dev" ]
}

@test "fetch keeps both copies and only reads on the host" {
    shop_files_with composer.lock .env
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -eq 0 ]
    [ -s "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz" ]
    [ -s "$SDWA5_SHOPWARE_DEV_DIR/archive.tar.gz" ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz.part" ]
    [ "$(stat -c %a "$SDWA5_SHOPWARE_DEV_DIR")" = 700 ]
    [ "$(wc -l < "$SSH_LOG")" -eq 2 ]
    grep -q '^tar -C /opt/docker/shopware-html-data .* -czf - \.$' "$SSH_LOG"
    grep -qx 'cat /opt/docker/database-backup/shopware.tar.gz' "$SSH_LOG"
}

@test "fetch leaves caches, logs and dated env backups on the host" {
    shop_files_with composer.lock
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    grep -q -- '--exclude=./var/cache --exclude=./var/log' "$SSH_LOG"
    grep -q -- "--exclude='./.env\*.before-\*'" "$SSH_LOG"
}

@test "fetch rejects shop files without a composer.lock" {
    shop_files_with composer.json
    archive_with_coverage full
    fake_ssh
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [[ "$output" == *'no composer.lock'* ]]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz" ]
}

@test "fetch rejects a truncated download" {
    stub ssh "printf 'not gzip'"
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR/html.tar.gz" ]
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

@test "restore neutralises the copy before the proxy publishes it" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    proxy="$(line_of 'run --detach --name sdwa5-shopware-dev-proxy')"
    [ -n "$proxy" ]
    for step in 'APP_URL=http://localhost:8090' 'MAILER_DSN=null://null' \
        'system:config:set --json core.mailerSettings.disableDelivery true' \
        'UPDATE sales_channel_domain' 'cache:clear'; do
        [ "$(line_of "$step")" -lt "$proxy" ]
    done
    [ "$(line_of 'STDIN CREATE DATABASE shopware;')" -lt "$proxy" ]
    [[ "$output" == *'mails	disabled'* ]]
}

@test "Shopware itself runs on an internal network and publishes nothing" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    grep -q '^CALL network create --internal sdwa5-shopware-dev$' "$DOCKER_LOG"
    app="$(grep '^CALL run --detach --name sdwa5-shopware-dev ' "$DOCKER_LOG")"
    [[ "$app" == *'--network sdwa5-shopware-dev '* ]]
    [[ "$app" != *'--publish'* ]]
    grep -q -- '--publish 127.0.0.1:8090:8080 alpine/socat:' "$DOCKER_LOG"
}

@test "the files volume is not seeded with the image's demo shop" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    run bash "$DEV_SCRIPT" restore
    ! grep 'dst=/var/www/html' "$DOCKER_LOG" | grep -v -q 'volume-nocopy=true'
    grep -q -- '--network none --user root --entrypoint tar' "$DOCKER_LOG"
}

@test "the new APP_SECRET is random and never printed" {
    fetched_copy
    fake_docker
    run bash -c 'source "$DEV_SCRIPT"; write_env_local'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q '^STDIN APP_SECRET=[0-9a-f]\{64\}$' "$DOCKER_LOG"
    grep -q '^STDIN DATABASE_URL=mysql://root:root@127.0.0.1:3306/shopware$' "$DOCKER_LOG"
}

@test "only http domains move, so the headless placeholder stays" {
    fetched_copy
    fake_docker
    run bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -eq 0 ]
    grep -q "^STDIN  WHERE url REGEXP '^https?://';$" "$DOCKER_LOG"
}

@test "an active Shopmon is deactivated" {
    fetched_copy
    fake_docker
    run env SHOPMON_ACTIVE=1 bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -eq 0 ]
    grep -q 'plugin:deactivate FroshShopmon' "$DOCKER_LOG"
}

@test "an inactive Shopmon is left alone" {
    fetched_copy
    fake_docker
    run bash -c 'source "$DEV_SCRIPT"; neutralise'
    ! grep -q 'plugin:deactivate' "$DOCKER_LOG"
}

@test "a suggested shop ID change gets a shop ID of its own despite the failing registration" {
    fetched_copy
    fake_docker
    run env SHOP_ID_SUGGESTED=1 bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -eq 0 ]
    grep -q 'app:shop-id:change reinstall-apps' "$DOCKER_LOG"
    [ "$(cat "$BATS_TEST_TMPDIR/shop-id-checks")" = 2 ]
}

@test "a shop without apps may end up without a shop ID" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    SHOP_ID_SUGGESTED=1 SHOP_ID_DELETED=1 run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    grep -q 'app:shop-id:change reinstall-apps' "$DOCKER_LOG"
}

@test "without a suggested change the shop ID stays" {
    fetched_copy
    fake_docker
    run bash -c 'source "$DEV_SCRIPT"; neutralise'
    ! grep -q 'app:shop-id:change' "$DOCKER_LOG"
}

@test "the service apps are deactivated through the API with keys that are never printed" {
    fetched_copy
    fake_docker
    run bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -eq 0 ]
    [[ "$output" != *'topsecretvalue'* ]]
    [ "$(stat -c %a "$SDWA5_SHOPWARE_DEV_DIR/integration.env")" = 600 ]
    ! grep '^CALL' "$DOCKER_LOG" | grep -q 'topsecretvalue'
    grep -q '^STDIN SHOPWARE_SECRET_ACCESS_KEY=topsecretvalue$' "$DOCKER_LOG"
    [ "$(line_of 'service/deactivate')" -lt "$(line_of 'cache:clear')" ]
}

@test "a service whose state Shopware manages is not deactivated" {
    # Shopware answers 400 SERVICE__STATE_CHANGE_NOT_PERMITTED for it, which
    # stopped every restore from 2026-10-18 on. The filter runs inside the
    # container, so its condition is checked in the source.
    grep -q 'active\\"\] && (\\$s\[\\"state_change_permitted\\"\] ?? true)' "$DEV_SCRIPT"
}

@test "an existing integration is reused" {
    fetched_copy
    fake_docker
    printf 'SHOPWARE_ACCESS_KEY_ID=old\n' > "$SDWA5_SHOPWARE_DEV_DIR/integration.env"
    run bash -c 'source "$DEV_SCRIPT"; deactivate_services'
    [ "$status" -eq 0 ]
    ! grep -q 'integration:create' "$DOCKER_LOG"
}

@test "a failing services API stops the neutralisation" {
    fetched_copy
    fake_docker
    run env SERVICES_API_FAIL=1 bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -ne 0 ]
    [[ "$output" == *'could not be deactivated'* ]]
    ! grep -q 'cache:clear' "$DOCKER_LOG"
}

@test "restore drops the integration of the replaced database" {
    fetched_copy
    fake_docker
    stub curl "printf 200"
    printf 'SHOPWARE_ACCESS_KEY_ID=stale\n' > "$SDWA5_SHOPWARE_DEV_DIR/integration.env"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -eq 0 ]
    grep -q 'integration:create' "$DOCKER_LOG"
    ! grep -q 'STDIN SHOPWARE_ACCESS_KEY_ID=stale' "$DOCKER_LOG"
    [[ "$output" == *'services	1 active'* ]]
}

@test "restore fails on a storefront that answers with an error" {
    fetched_copy
    fake_docker
    stub curl "printf 500"
    run bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'storefront answered 500'* ]]
}

@test "up only reports a storefront in maintenance mode" {
    fetched_copy
    fake_docker
    stub curl "printf 503"
    run bash "$DEV_SCRIPT" up
    [ "$status" -eq 0 ]
    [[ "$output" == *'The storefront answers 503.'* ]]
    [[ "$output" == *'application	running'* ]]
}

@test "up refuses a mirror whose env was never neutralised" {
    fetched_copy
    fake_docker
    run env ENV_MARKER_MISSING=1 bash "$DEV_SCRIPT" up
    [ "$status" -ne 0 ]
    [[ "$output" == *'not neutralised'* ]]
    ! grep -q 'sdwa5-shopware-dev-proxy alpine' "$DOCKER_LOG"
}

@test "purge removes the fetched copies" {
    fetched_copy
    fake_docker
    run bash "$DEV_SCRIPT" purge
    [ "$status" -eq 0 ]
    [ ! -e "$SDWA5_SHOPWARE_DEV_DIR" ]
    grep -q 'volume rm --force sdwa5-shopware-dev-html sdwa5-shopware-dev-mysql' "$DOCKER_LOG"
}

@test "composer runs beside the mirror on the proxy's network, without scripts" {
    fake_docker
    SDWA5_SHOPWARE_DEV_PHP='' run bash "$DEV_SCRIPT" composer require shopware/core:v6.7.15.1
    [ "$status" -eq 0 ]
    call="$(grep '^CALL run --rm' "$DOCKER_LOG")"
    [[ "$call" == *'--network sdwa5-shopware-dev-web '* ]]
    [[ "$call" == *'--entrypoint composer '* ]]
    [[ "$call" == *' --no-interaction require shopware/core:v6.7.15.1 --no-scripts' ]]
}

@test "composer adds no script flag to commands that run none" {
    fake_docker
    run bash "$DEV_SCRIPT" composer audit --locked
    [ "$status" -eq 0 ]
    grep -q -- ' --no-interaction audit --locked$' "$DOCKER_LOG"
}

@test "composer refuses to run without a mirror" {
    stub docker "case \"\$*\" in 'volume inspect'*) exit 1 ;; esac; exit 97"
    run bash "$DEV_SCRIPT" composer install
    [ "$status" -ne 0 ]
    [[ "$output" == *'Run fetch and restore first'* ]]
}

@test "console passes its arguments to bin/console in the mirror" {
    fake_docker
    run bash "$DEV_SCRIPT" console system:update:finish
    [ "$status" -eq 0 ]
    grep -q 'exec --user www-data --workdir /var/www/html sdwa5-shopware-dev php bin/console --no-interaction system:update:finish$' "$DOCKER_LOG"
}

@test "status of a stopped mirror shows absent on the same line" {
    stub docker "printf '\\n'; exit 1"
    run bash "$DEV_SCRIPT" status
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "application	absent	$(bash -c 'source "$DEV_SCRIPT"; app_image')" ]
    [ "${lines[1]}" = 'proxy	absent	127.0.0.1:8090' ]
    [ "${lines[2]}" = 'egress	absent' ]
    [ "${#lines[@]}" -eq 3 ]
}
