#!/usr/bin/env bash
#
# A local Shopware mirror of sdwa5.org, for rehearsing updates and plugin work.
#
# It runs the production image (docs/shopware/image.md) against a copy of the
# shop's data and of the newest production database archive, and deploys it
# with the same deployment helper call as tools/shopware/deploy.sh. It never
# writes to production: `fetch` reads the data and one archive over ssh, and
# every other command acts on local containers and volumes.
#
# The copy holds real customer data, so the fetched archives live in a private
# directory outside the repository, and the copy is made harmless before
# anything can reach it:
#   - Shopware and its database sit on an internal Docker network without
#     egress, so no mail, webhook or Shopmon report can leave it. A socat
#     container publishes it on 127.0.0.1 only, and it starts last.
#   - MAILER_DSN=null://null.
#   - Shopware's staging mode, which the helper run alone applies with
#     SHOPWARE_DEPLOYMENT_STAGING=1: mail delivery off, every domain on the
#     local URL, FroshShopmon off, and every app with an app server and the
#     shop ID deleted (shopware-html-data/config/packages/staging.yaml). The
#     result is asserted in the database before the application starts.
#   - A new APP_SECRET, so a token minted here is not valid in production.
#
# The database credentials below protect nothing, because the database sits on
# a network without a gateway and publishes no port.
#
# Usage:
#   tools/shopware/dev-instance.sh fetch      copy the shop data and the newest archive
#   tools/shopware/dev-instance.sh restore    rebuild the mirror from that copy
#   tools/shopware/dev-instance.sh up         start the mirror again
#   tools/shopware/dev-instance.sh down       stop and remove its containers, keep the data
#   tools/shopware/dev-instance.sh status     containers, images, mail, staging and URL
#   tools/shopware/dev-instance.sh purge      remove containers, volumes and fetched copies
#   tools/shopware/dev-instance.sh console ARGS    run bin/console inside the mirror
#   tools/shopware/dev-instance.sh --help
# Composer runs through tools/shopware/image.sh composer.
#
# Environment:
#   SDWA5_SHOPWARE_DEV_IMAGE     application image, default the shopware service's,
#                                set it to rehearse an update
#   SDWA5_SHOPWARE_DEV_DB_IMAGE  database image, default the shopware_db service's
#   SDWA5_SHOPWARE_DEV_DIR       data directory, default ~/.local/share/sdwa5-shopware-dev
#   SDWA5_SHOPWARE_DEV_PORT      local port, default 8090
#   SDWA5_SHOPWARE_SSH           production host, default root@sdwa5.org
#   SDWA5_SHOPWARE_DATA          shop data on the host, default /opt/docker/shopware-data
#   SDWA5_SHOPWARE_DATA_PATHS    paths below it, default "files media thumbnail sitemap";
#                                a public/ prefix is dropped in the copy
#   SDWA5_SHOPWARE_ARCHIVE       archive path on the host,
#                                default /opt/docker/database-backup/shopware_db.tar.gz

set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFIX="sdwa5-shopware-dev"
DEV_DIR="${SDWA5_SHOPWARE_DEV_DIR:-$HOME/.local/share/$PREFIX}"
DEV_PORT="${SDWA5_SHOPWARE_DEV_PORT:-8090}"
DEV_SSH="${SDWA5_SHOPWARE_SSH:-root@sdwa5.org}"
DEV_DATA_REMOTE="${SDWA5_SHOPWARE_DATA:-/opt/docker/shopware-data}"
DEV_DATA_PATHS="${SDWA5_SHOPWARE_DATA_PATHS:-files media thumbnail sitemap}"
DEV_ARCHIVE_REMOTE="${SDWA5_SHOPWARE_ARCHIVE:-/opt/docker/database-backup/shopware_db.tar.gz}"
APP="$PREFIX"
# The _db suffix lets monitoring/database-backup.sh run against it.
DB="sdwa5_shopware_dev_db"
PROXY="$PREFIX-proxy"
NETWORK="$PREFIX"
WEB_NETWORK="$PREFIX-web"
# Volume name suffix and mount point in the application container.
DATA_VOLUMES=(files:/var/www/html/files media:/var/www/html/public/media
    thumbnail:/var/www/html/public/thumbnail sitemap:/var/www/html/public/sitemap
    theme:/var/www/html/public/theme)
MYSQL_VOLUME="$PREFIX-mysql"
# Pinned like every other image, and only ever forwards inbound connections.
PROXY_IMAGE="alpine/socat:1.8.1.1"
LOCAL_URL="http://localhost:$DEV_PORT"

# compose_image and deployment_helper come from the lib. die() below replaces the lib's.
# shellcheck source=tools/shopware/lib.sh
source "$REPO_ROOT/tools/shopware/lib.sh"

usage() { sed -n '3,/^[^#]/{/^#/p}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'dev-instance.sh: %s\n' "$*" >&2; exit 1; }

app_image() {
    local image="${SDWA5_SHOPWARE_DEV_IMAGE:-$(compose_image shopware)}"
    [[ -n "$image" ]] || die "docker-compose.yml has no image for service shopware."
    printf '%s' "$image"
}

db_image() {
    local image="${SDWA5_SHOPWARE_DEV_DB_IMAGE:-$(compose_image shopware_db)}"
    [[ -n "$image" ]] || die "docker-compose.yml has no image for service shopware_db."
    printf '%s' "$image"
}

# Every `- KEY=value` of the shopware service's environment, one per line,
# without the YAML quotes. A value may contain spaces.
compose_environment() {
    awk '
        $0 == "  shopware:" { found = 1; next }
        found && /^  [a-z_]+:$/ { exit }
        found && /^    environment:$/ { env = 1; next }
        env && /^      - / { sub(/^      - /, ""); gsub(/^"|"$/, ""); print; next }
        env && /^ *#/ { next }
        env { env = 0 }' "$REPO_ROOT/docker-compose.yml"
}

database_name() {
    tar -xzOf "$DEV_DIR/archive.tar.gz" manifest.tsv | awk -F '\t' '$1 == "database" { print $2 }'
}

database() {
    docker exec -i --env MYSQL_PWD=root "$DB" mysql --no-defaults --protocol=TCP --host=127.0.0.1 --user=root "$@"
}

# One value of a query on the shop's database.
query() {
    database --batch --skip-column-names --database="$(database_name)" --execute="$1"
}

console() {
    docker exec "$APP" php bin/console --no-interaction "$@"
}

remove_containers() {
    docker rm -f "$PROXY" "$APP" "$DB" >/dev/null 2>&1 || true
}

ensure_networks() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --internal "$NETWORK" >/dev/null
    docker network inspect "$WEB_NETWORK" >/dev/null 2>&1 || docker network create "$WEB_NETWORK" >/dev/null
}

volume_names() {
    local entry
    for entry in "${DATA_VOLUMES[@]}"; do printf '%s\n' "$PREFIX-${entry%%:*}"; done
    printf '%s\n' "$MYSQL_VOLUME"
}

# The database credentials matter only on a fresh volume, where the image's
# entrypoint creates the server with them.
start_database() {
    local attempt
    ensure_networks
    docker run --detach --name "$DB" --hostname "$DB" --network "$NETWORK" --stop-timeout 60 \
        --mount "type=volume,src=$MYSQL_VOLUME,dst=/var/lib/mysql" \
        --env MYSQL_ROOT_PASSWORD=root --env MYSQL_DATABASE="$(database_name)" \
        --env MYSQL_USER=shopware --env MYSQL_PASSWORD=shopware \
        "$(db_image)" --mysqlx=OFF >/dev/null
    # The entrypoint's first server skips networking, so TCP answers only the real one.
    for (( attempt = 0; attempt < 300; attempt++ )); do
        database --execute='SELECT 1' >/dev/null 2>&1 && return 0
        [[ "$(docker inspect --format '{{.State.Running}}' "$DB" 2>/dev/null)" == true ]] \
            || die "the database container stopped. docker logs $DB shows why."
        sleep 1
    done
    die "the database was not ready within 300 s."
}

# Sets APP_ARGS: the production restrictions, the data volumes, the mitigation
# ini, the shopware service's environment and the mirror's overrides. Docker
# keeps the last of two -e for one name, so the overrides win.
app_args() {
    local entry line secret
    secret="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    APP_ARGS=(--network "$NETWORK" --cap-drop ALL --security-opt no-new-privileges:true)
    for entry in "${DATA_VOLUMES[@]}"; do
        APP_ARGS+=(--mount "type=volume,src=$PREFIX-${entry%%:*},dst=${entry#*:},volume-nocopy=true")
    done
    APP_ARGS+=(--mount "type=bind,src=$REPO_ROOT/hardening/php/99-php-security-mitigation.ini,dst=/usr/local/etc/php/conf.d/99-php-security-mitigation.ini,readonly")
    while IFS= read -r line; do
        APP_ARGS+=(-e "$line")
    done < <(compose_environment)
    APP_ARGS+=(-e "APP_URL=$LOCAL_URL" -e MAILER_DSN=null://null -e "APP_SECRET=$secret"
        -e "DATABASE_URL=mysql://shopware:shopware@$DB:3306/$(database_name)")
}

# Dies before the application starts unless staging left the copy harmless.
assert_neutralised() {
    [[ "$(query "SELECT JSON_EXTRACT(configuration_value, '\$._value') FROM system_config WHERE configuration_key = 'core.mailerSettings.disableDelivery' AND sales_channel_id IS NULL")" == true ]] \
        || die "mail delivery is not disabled in the copy."
    [[ "$(query "SELECT COUNT(*) FROM sales_channel_domain WHERE url REGEXP '^https?://' AND url NOT LIKE '$LOCAL_URL%'")" == 0 ]] \
        || die "a sales channel domain still points outside $LOCAL_URL."
    # Catches an unresolved %env(APP_URL)%, which would leave no http domain at all.
    [[ "$(query "SELECT COUNT(*) FROM sales_channel_domain WHERE url LIKE '$LOCAL_URL%'")" -ge 1 ]] \
        || die "no sales channel domain points at $LOCAL_URL."
    [[ "$(query "SELECT COUNT(*) FROM plugin WHERE name = 'FroshShopmon' AND active = 1")" == 0 ]] \
        || die "FroshShopmon is still active in the copy."
    # Production holds no app since SEC-29, so any app stops the mirror.
    [[ "$(query 'SELECT COUNT(*) FROM app')" == 0 ]] || die "the copy holds an app."
}

start_application() {
    docker run --detach --name "$APP" --hostname "$APP" "${APP_ARGS[@]}" "$(app_image)" >/dev/null
}

# A port cannot be published from an --internal network, so a proxy on its own
# network publishes it and joins the internal one afterwards. Shopware itself
# never gets a route out.
start_proxy() {
    docker run --detach --name "$PROXY" --network "$WEB_NETWORK" --cap-drop ALL \
        --publish "127.0.0.1:$DEV_PORT:8080" \
        "$PROXY_IMAGE" TCP-LISTEN:8080,fork,reuseaddr "TCP:$APP:8000" >/dev/null
    docker network connect "$NETWORK" "$PROXY"
}

# Asked by the local URL, because a host that matches no sales channel domain
# such as 127.0.0.1 gets a 400. Prints the storefront's status code as soon as
# there is one, and fails only when nothing answers at all.
storefront_code() {
    local attempt code
    for (( attempt = 0; attempt < 120; attempt++ )); do
        code="$(curl --silent --output /dev/null --max-time 5 --write-out '%{http_code}' \
            "$LOCAL_URL/" || true)"
        [[ "$code" =~ ^[1-5][0-9][0-9]$ ]] && { printf '%s' "$code"; return 0; }
        sleep 1
    done
    die "the storefront did not answer on port $DEV_PORT within 120 s."
}

# restore demands a working storefront.
wait_for_application() {
    local code
    code="$(storefront_code)"
    [[ "$code" =~ ^(200|301|302)$ ]] || die "the storefront answered $code. docker exec $APP ls var/log shows the logs."
}

# up only reports it, because during an update the storefront answers 503 in
# maintenance mode and 500 until the helper has migrated the database.
report_application() {
    local code
    code="$(storefront_code)"
    [[ "$code" =~ ^(200|301|302)$ ]] || printf 'The storefront answers %s.\n' "$code"
}

cmd_fetch() {
    mkdir -p "$DEV_DIR"
    local listing path
    # The dockware era's copy held production .env and auth.json, and the
    # integration keys lived in a database that the next restore replaces.
    rm -f -- "$DEV_DIR/html.tar.gz" "$DEV_DIR/integration.env"
    printf 'Copying %s:%s (%s)\n' "$DEV_SSH" "$DEV_DATA_REMOTE" "$DEV_DATA_PATHS"
    # The paths are meant to expand here and are quoted for the remote shell.
    # shellcheck disable=SC2029,SC2086
    ssh "$DEV_SSH" "tar -C $(printf '%q' "$DEV_DATA_REMOTE") --transform 's,^public/,,' -czf - $(printf '%q ' $DEV_DATA_PATHS)" \
        > "$DEV_DIR/data.tar.gz.part"
    gzip -t "$DEV_DIR/data.tar.gz.part" || die "the copied shop data is not a valid gzip file."
    # The listing is captured first, because grep -q stops reading early and
    # pipefail would report tar's SIGPIPE as a missing file.
    listing="$(tar -tzf "$DEV_DIR/data.tar.gz.part")"
    for path in $DEV_DATA_PATHS; do
        grep -qx "${path##*/}/" <<< "$listing" || die "the shop data holds no ${path##*/}/."
    done
    mv "$DEV_DIR/data.tar.gz.part" "$DEV_DIR/data.tar.gz"
    printf 'Copying %s:%s\n' "$DEV_SSH" "$DEV_ARCHIVE_REMOTE"
    # shellcheck disable=SC2029
    ssh "$DEV_SSH" "cat $(printf '%q' "$DEV_ARCHIVE_REMOTE")" > "$DEV_DIR/archive.tar.gz.part"
    gzip -t "$DEV_DIR/archive.tar.gz.part" || die "the copied archive is not a valid gzip file."
    listing="$(tar -tzf "$DEV_DIR/archive.tar.gz.part")"
    grep -qx 'dump.sql' <<< "$listing" || die "the archive holds no dump.sql."
    mv "$DEV_DIR/archive.tar.gz.part" "$DEV_DIR/archive.tar.gz"
    printf 'Stored %s and %s bytes in %s\n' "$(stat -c %s "$DEV_DIR/data.tar.gz")" \
        "$(stat -c %s "$DEV_DIR/archive.tar.gz")" "$DEV_DIR"
}

cmd_restore() {
    local entry
    local -a mounts=()
    [[ -r "$DEV_DIR/data.tar.gz" && -r "$DEV_DIR/archive.tar.gz" ]] || die "no copy in $DEV_DIR. Run fetch first."
    [[ "$(tar -xzOf "$DEV_DIR/archive.tar.gz" manifest.tsv | awk -F '\t' '$1 == "coverage" { print $2 }')" == full ]] \
        || die "the archive is not a full dump."
    [[ "$(database_name)" =~ ^[A-Za-z0-9_]+$ ]] || die "the archive manifest names no database."
    remove_containers
    # shellcheck disable=SC2046
    docker volume rm --force $(volume_names) >/dev/null
    printf 'Unpacking the shop data.\n'
    for entry in "${DATA_VOLUMES[@]}"; do
        mounts+=(--mount "type=volume,src=$PREFIX-${entry%%:*},dst=/data/${entry%%:*},volume-nocopy=true")
    done
    # As root, because the volumes are new and www-data (82) must own them.
    docker run --rm --network none --user 0 --entrypoint sh "${mounts[@]}" \
        --mount "type=bind,src=$DEV_DIR/data.tar.gz,dst=/import/data.tar.gz,readonly" \
        "$(app_image)" -c 'tar -xzf /import/data.tar.gz -C /data && chown -R 82:82 /data'
    printf 'Starting the database without a network route out.\n'
    start_database
    printf 'Importing the archive.\n'
    tar -xzOf "$DEV_DIR/archive.tar.gz" dump.sql | database
    app_args
    printf 'Running the deployment helper in staging mode.\n'
    SECONDS=0
    deployment_helper docker run --rm "${APP_ARGS[@]}" -e SHOPWARE_DEPLOYMENT_STAGING=1 "$(app_image)" \
        || die "the deployment helper failed."
    printf 'Deployment helper took %ss.\n' "$SECONDS"
    assert_neutralised
    start_application
    # Renders the copy's storefront in-process on its rewritten domain.
    console system:check --context=pre_rollout || die "system:check failed in the copy."
    start_proxy
    wait_for_application
    cmd_status
}

cmd_up() {
    # shellcheck disable=SC2046
    docker volume inspect $(volume_names) >/dev/null 2>&1 \
        || die "no mirror. Run fetch and restore first."
    [[ -r "$DEV_DIR/archive.tar.gz" ]] || die "no archive in $DEV_DIR. Run fetch and restore."
    remove_containers
    start_database
    assert_neutralised
    app_args
    start_application
    start_proxy
    report_application
    cmd_status
}

cmd_down() {
    remove_containers
    docker network rm "$NETWORK" "$WEB_NETWORK" >/dev/null 2>&1 || true
    printf 'Stopped. The data stays in the %s-* volumes.\n' "$PREFIX"
}

cmd_purge() {
    cmd_down >/dev/null
    # shellcheck disable=SC2046
    docker volume rm --force $(volume_names) >/dev/null
    rm -rf -- "$DEV_DIR"
    printf 'Removed the mirror and %s.\n' "$DEV_DIR"
}

cmd_console() {
    local -a tty=()
    [[ "$(docker inspect --format '{{.State.Running}}' "$APP" 2>/dev/null)" == true ]] \
        || die "the mirror is not running. Run up first."
    [[ -t 0 && -t 1 ]] && tty=(-t)
    docker exec -i "${tty[@]}" "$APP" php bin/console "$@"
}

# docker inspect prints an empty line for a missing object before it fails,
# so its output is dropped on failure rather than followed by the fallback.
inspect_or_absent() {
    local out
    out="$(docker "$@" 2>/dev/null)" || out=''
    printf '%s' "${out:-absent}"
}

cmd_status() {
    local app_state db_state
    app_state="$(inspect_or_absent inspect --format '{{.State.Status}}' "$APP")"
    db_state="$(inspect_or_absent inspect --format '{{.State.Status}}' "$DB")"
    printf 'application\t%s\t%s\t%s\n' "$app_state" "$(app_image)" "$(inspect_or_absent inspect --format '{{.Image}}' "$APP")"
    printf 'database\t%s\t%s\t%s\n' "$db_state" "$(db_image)" "$(inspect_or_absent inspect --format '{{.Image}}' "$DB")"
    printf 'proxy\t%s\t127.0.0.1:%s\n' "$(inspect_or_absent inspect --format '{{.State.Status}}' "$PROXY")" "$DEV_PORT"
    printf 'egress\t%s\n' "$(inspect_or_absent network inspect --format '{{if .Internal}}none{{else}}OPEN{{end}}' "$NETWORK")"
    if [[ "$db_state" == running && -r "$DEV_DIR/archive.tar.gz" ]]; then
        printf 'mails\t%s\n' "$([[ "$(query "SELECT JSON_EXTRACT(configuration_value, '\$._value') FROM system_config WHERE configuration_key = 'core.mailerSettings.disableDelivery' AND sales_channel_id IS NULL" 2>/dev/null)" == true ]] \
            && printf 'disabled' || printf 'ENABLED')"
        printf 'staging\t%s\n' "$([[ "$(query "SELECT JSON_EXTRACT(configuration_value, '\$._value') FROM system_config WHERE configuration_key = 'core.staging'" 2>/dev/null)" == true ]] \
            && printf 'on' || printf 'OFF')"
    fi
    [[ "$app_state" != running ]] || printf 'url\t%s/\n' "$LOCAL_URL"
}

main() {
    case "${1:-}" in
        fetch) cmd_fetch ;;
        restore) cmd_restore ;;
        up) cmd_up ;;
        down) cmd_down ;;
        status) cmd_status ;;
        purge) cmd_purge ;;
        console) shift; cmd_console "$@" ;;
        -h|--help) usage ;;
        "") usage; exit 2 ;;
        *) die "unknown command: $1. Try --help." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
