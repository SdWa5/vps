#!/usr/bin/env bash
#
# A local Shopware mirror of sdwa5.org, for rehearsing updates and plugin work.
#
# It runs the production image against a copy of the shop's files and of the
# newest production database archive. It never writes to production: `fetch`
# reads the files and one archive over ssh, and every other command acts on
# local containers and volumes.
#
# The copy holds real customer data and the shop's credentials, so the fetched
# archives live in a private directory outside the repository, and the copy is
# made harmless before anything can reach it:
#   - Shopware sits on an internal Docker network without egress, so no mail,
#     webhook, service app or Shopmon report can leave it. A socat container
#     publishes it on 127.0.0.1 only, and it starts last.
#   - MAILER_DSN=null://null and core.mailerSettings.disableDelivery, so mail
#     delivery stays off even with a network.
#   - APP_URL and every sales channel domain point at the local URL.
#   - FroshShopmon and every Shopware service app are deactivated, and no
#     scheduled-task runner or queue consumer runs (the admin worker is off in
#     the tracked config).
#   - A new APP_SECRET, so a token minted here is not valid in production.
#
# Usage:
#   tools/shopware/dev-instance.sh fetch      copy the shop files and the newest archive
#   tools/shopware/dev-instance.sh restore    rebuild the mirror from that copy
#   tools/shopware/dev-instance.sh up         start the mirror again
#   tools/shopware/dev-instance.sh down       stop and remove its containers, keep the data
#   tools/shopware/dev-instance.sh status     containers, version, mail state and URL
#   tools/shopware/dev-instance.sh purge      remove containers, volumes and fetched copies
#   tools/shopware/dev-instance.sh composer ARGS   run Composer on the mirror's files, with network
#   tools/shopware/dev-instance.sh console ARGS    run bin/console inside the mirror
#   tools/shopware/dev-instance.sh --help
#
# Environment:
#   SDWA5_SHOPWARE_DEV_SERVICE   compose service whose image is mirrored, default shopware
#   SDWA5_SHOPWARE_DEV_IMAGE     application image, default the one that service pins,
#                                set it to rehearse an update
#   SDWA5_SHOPWARE_DEV_DIR       data directory, default ~/.local/share/sdwa5-<service>-dev
#   SDWA5_SHOPWARE_DEV_PORT      local port, default 8090
#   SDWA5_SHOPWARE_SSH           production host, default root@sdwa5.org
#   SDWA5_SHOPWARE_HTML          shop files on the host, default /opt/docker/shopware-html-data
#   SDWA5_SHOPWARE_ARCHIVE       archive path on the host,
#                                default /opt/docker/database-backup/shopware.tar.gz

set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE="${SDWA5_SHOPWARE_DEV_SERVICE:-shopware}"
[[ "$SERVICE" =~ ^[a-z0-9_]+$ ]] || { printf 'dev-instance.sh: service "%s" is not lowercase alphanumeric.\n' "$SERVICE" >&2; exit 2; }
PREFIX="sdwa5-${SERVICE//_/-}-dev"
DEV_DIR="${SDWA5_SHOPWARE_DEV_DIR:-$HOME/.local/share/$PREFIX}"
DEV_PORT="${SDWA5_SHOPWARE_DEV_PORT:-8090}"
DEV_SSH="${SDWA5_SHOPWARE_SSH:-root@sdwa5.org}"
DEV_HTML_REMOTE="${SDWA5_SHOPWARE_HTML:-/opt/docker/shopware-html-data}"
DEV_ARCHIVE_REMOTE="${SDWA5_SHOPWARE_ARCHIVE:-/opt/docker/database-backup/shopware.tar.gz}"
APP="$PREFIX"
PROXY="$PREFIX-proxy"
NETWORK="$PREFIX"
WEB_NETWORK="$PREFIX-web"
HTML_VOLUME="$PREFIX-html"
MYSQL_VOLUME="$PREFIX-mysql"
# Pinned like every other image, and only ever forwards inbound connections.
PROXY_IMAGE="alpine/socat:1.8.1.1"
# The dockware image ships MySQL with these credentials. The database is
# reachable from inside its own container only, so they protect nothing.
DATABASE_URL="mysql://root:root@127.0.0.1:3306"
LOCAL_URL="http://localhost:$DEV_PORT"

usage() { sed -n '3,44p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'dev-instance.sh: %s\n' "$*" >&2; exit 1; }

# The image a service of docker-compose.yml pins, so the mirror follows every
# production bump without a second place to edit.
compose_image() {
    awk -v service="  $1:" '
        $0 == service { found = 1; next }
        found && /^  [a-z_]+:$/ { exit }
        found && /^ +image:/ { print $2; exit }' "$REPO_ROOT/docker-compose.yml"
}

app_image() {
    local image="${SDWA5_SHOPWARE_DEV_IMAGE:-$(compose_image "$SERVICE")}"
    [[ -n "$image" ]] || die "docker-compose.yml has no image for service $SERVICE."
    printf '%s' "$image"
}

database() {
    docker exec -i --env MYSQL_PWD=root "$APP" mysql --no-defaults --protocol=TCP --host=127.0.0.1 --user=root "$@"
}

console() {
    docker exec --user www-data --workdir /var/www/html "$APP" php bin/console --no-interaction "$@"
}

database_name() {
    tar -xzOf "$DEV_DIR/archive.tar.gz" manifest.tsv | awk -F '\t' '$1 == "database" { print $2 }'
}

remove_containers() {
    docker rm -f "$PROXY" "$APP" >/dev/null 2>&1 || true
}

ensure_networks() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --internal "$NETWORK" >/dev/null
    docker network inspect "$WEB_NETWORK" >/dev/null 2>&1 || docker network create "$WEB_NETWORK" >/dev/null
}

# volume-nocopy keeps Docker from seeding the files volume with the demo shop
# the image ships. The MySQL volume is seeded on purpose, because that gives an
# initialised server with the image's credentials.
start_application() {
    ensure_networks
    docker run --detach --name "$APP" --hostname "$APP" --network "$NETWORK" --cap-drop NET_RAW \
        --mount "type=volume,src=$HTML_VOLUME,dst=/var/www/html,volume-nocopy=true" \
        --mount "type=volume,src=$MYSQL_VOLUME,dst=/var/lib/mysql" \
        "$(app_image)" >/dev/null
    local attempt
    for (( attempt = 0; attempt < 300; attempt++ )); do
        docker exec "$APP" test -f /var/www/container.launched 2>/dev/null \
            && database --execute='SELECT 1' >/dev/null 2>&1 && return 0
        [[ "$(docker inspect --format '{{.State.Running}}' "$APP" 2>/dev/null)" == true ]] \
            || die "the application container stopped. docker logs $APP shows why."
        sleep 1
    done
    die "the application container was not ready within 300 s."
}

# A port cannot be published from an --internal network, so a proxy on its own
# network publishes it and joins the internal one afterwards. Shopware itself
# never gets a route out.
start_proxy() {
    docker run --detach --name "$PROXY" --network "$WEB_NETWORK" --cap-drop ALL \
        --publish "127.0.0.1:$DEV_PORT:8080" \
        "$PROXY_IMAGE" TCP-LISTEN:8080,fork,reuseaddr "TCP:$APP:80" >/dev/null
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
    [[ "$code" =~ ^(200|301|302)$ ]] || die "the storefront answered $code. docker exec $APP tail var/log shows why."
}

# up only reports it, because during an update the storefront answers 503 in
# maintenance mode and 500 until system:update:finish has migrated the database.
report_application() {
    local code
    code="$(storefront_code)"
    [[ "$code" =~ ^(200|301|302)$ ]] || printf 'The storefront answers %s.\n' "$code"
}

# Rewrites .env.local inside the copy. The keys set here replace production's,
# and every other line is kept. The secret goes through stdin and is never
# printed.
write_env_local() {
    local secret
    secret="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf 'APP_URL=%s\nAPP_SECRET=%s\nDATABASE_URL=%s/%s\nMAILER_DSN=null://null\n' \
        "$LOCAL_URL" "$secret" "$DATABASE_URL" "$(database_name)" \
        | docker exec -i --user www-data "$APP" sh -c '
            set -e
            cd /var/www/html
            { grep -v -E "^(APP_URL|APP_SECRET|DATABASE_URL|MAILER_DSN)=" .env.local 2>/dev/null || true
              printf "# sdwa5 dev mirror: the lines below replace production values\n"
              cat; } > .env.local.mirror
            chmod 600 .env.local.mirror
            mv .env.local.mirror .env.local'
}

# Shopware's service apps such as ShopwarePayments cannot reach their servers
# from here. Since 6.7.15 a checkout gateway whose host does not resolve fails
# the cart with a 400 instead of being skipped, because AppSystemHttpMiddleware
# throws an AppException that the gateway's GuzzleException catch misses. They
# are deactivated through the services API, the way the admin does it, with a
# local integration whose keys stay in the private directory. Consent-bound
# services stay deactivated across system:update:finish. SwagGmvReportingService
# carries only the shopware_account requirement, which Shopware declares
# always-on, so an update reactivates it, and only its privileges follow whether
# an admin user holds a store token. Without egress it reaches nobody.
deactivate_services() {
    if [[ ! -s "$DEV_DIR/integration.env" ]]; then
        console integration:create --admin "$PREFIX" > "$DEV_DIR/integration.env"
    fi
    docker exec -i "$APP" sh -c '
        set -e
        . /dev/stdin
        api=http://127.0.0.1/api
        token="$(curl -sf -m 30 "$api/oauth/token" -H "Content-Type: application/json" \
            -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"$SHOPWARE_ACCESS_KEY_ID\",\"client_secret\":\"$SHOPWARE_SECRET_ACCESS_KEY\"}" \
            | php -r "echo json_decode(stream_get_contents(STDIN), true)[\"access_token\"] ?? \"\";")"
        [ -n "$token" ]
        curl -sf -m 30 -H "Authorization: Bearer $token" "$api/service/list" \
            | php -r "foreach (json_decode(stream_get_contents(STDIN), true) as \$s) { if (\$s[\"active\"]) { echo \$s[\"name\"], \"\n\"; } }" \
            | while read -r name; do
                curl -sf -m 60 -X POST -H "Authorization: Bearer $token" "$api/service/deactivate/$name" >/dev/null
            done' < "$DEV_DIR/integration.env" \
        || die "the service apps could not be deactivated through the admin API."
}

# Applied to the restored copy before the proxy ever starts, so not a single
# request reaches an unneutralised production configuration. Safe to repeat.
neutralise() {
    console system:config:set --json core.mailerSettings.disableDelivery true >/dev/null
    # Every domain keeps its path and language and moves to the local origin.
    # The headless channel's placeholder such as default.headless0 is no URL
    # and stays as it is.
    database --database="$(database_name)" <<SQL
UPDATE sales_channel_domain
   SET url = CONCAT('$LOCAL_URL', SUBSTRING(url, LOCATE('/', CONCAT(url, '/'), LOCATE('//', url) + 2)))
 WHERE url REGEXP '^https?://';
SQL
    if [[ "$(database --batch --skip-column-names --database="$(database_name)" \
            --execute="SELECT COUNT(*) FROM plugin WHERE name = 'FroshShopmon' AND active = 1")" != 0 ]]; then
        console plugin:deactivate FroshShopmon >/dev/null
    fi
    # The new APP_URL and domains make Shopware suspect a moved shop and refuse
    # the cart. Reinstalling the apps gives the copy a shop ID of its own, so it
    # never presents itself to an app server as production. Their registration
    # under it then fails without egress ("App system target is not allowed")
    # and exits 1, which is expected, so Shopware's own check decides.
    if ! console app:shop-id:check 2>/dev/null | grep -q 'not suggested'; then
        console app:shop-id:change reinstall-apps >/dev/null 2>&1 || true
        console app:shop-id:check 2>/dev/null | grep -q 'not suggested' \
            || die "Shopware still suggests a shop ID change. bin/console app:shop-id:check shows why."
    fi
    deactivate_services
    console cache:clear >/dev/null
}

cmd_fetch() {
    mkdir -p "$DEV_DIR"
    local listing
    printf 'Copying %s:%s\n' "$DEV_SSH" "$DEV_HTML_REMOTE"
    # Caches, logs and the dated .env backups stay behind. The paths are meant
    # to expand here and are quoted for the remote shell.
    # shellcheck disable=SC2029
    ssh "$DEV_SSH" "tar -C $(printf '%q' "$DEV_HTML_REMOTE") --anchored --exclude=./var/cache --exclude=./var/log --exclude='./.env*.before-*' -czf - ." \
        > "$DEV_DIR/html.tar.gz.part"
    gzip -t "$DEV_DIR/html.tar.gz.part" || die "the copied shop files are not a valid gzip file."
    # The listing is captured first, because grep -q stops reading early and
    # pipefail would report tar's SIGPIPE as a missing file.
    listing="$(tar -tzf "$DEV_DIR/html.tar.gz.part")"
    grep -qx './composer.lock' <<< "$listing" || die "the shop files hold no composer.lock."
    mv "$DEV_DIR/html.tar.gz.part" "$DEV_DIR/html.tar.gz"
    printf 'Copying %s:%s\n' "$DEV_SSH" "$DEV_ARCHIVE_REMOTE"
    # shellcheck disable=SC2029
    ssh "$DEV_SSH" "cat $(printf '%q' "$DEV_ARCHIVE_REMOTE")" > "$DEV_DIR/archive.tar.gz.part"
    gzip -t "$DEV_DIR/archive.tar.gz.part" || die "the copied archive is not a valid gzip file."
    listing="$(tar -tzf "$DEV_DIR/archive.tar.gz.part")"
    grep -qx 'dump.sql' <<< "$listing" || die "the archive holds no dump.sql."
    mv "$DEV_DIR/archive.tar.gz.part" "$DEV_DIR/archive.tar.gz"
    printf 'Stored %s and %s bytes in %s\n' "$(stat -c %s "$DEV_DIR/html.tar.gz")" \
        "$(stat -c %s "$DEV_DIR/archive.tar.gz")" "$DEV_DIR"
}

cmd_restore() {
    [[ -r "$DEV_DIR/html.tar.gz" && -r "$DEV_DIR/archive.tar.gz" ]] || die "no copy in $DEV_DIR. Run fetch first."
    [[ "$(tar -xzOf "$DEV_DIR/archive.tar.gz" manifest.tsv | awk -F '\t' '$1 == "coverage" { print $2 }')" == full ]] \
        || die "the archive is not a full dump."
    [[ "$(database_name)" =~ ^[A-Za-z0-9_]+$ ]] || die "the archive manifest names no database."
    remove_containers
    docker volume rm --force "$HTML_VOLUME" "$MYSQL_VOLUME" >/dev/null
    # The integration lived in the database that is replaced now.
    rm -f -- "$DEV_DIR/integration.env"
    docker volume create "$HTML_VOLUME" >/dev/null
    docker volume create "$MYSQL_VOLUME" >/dev/null
    printf 'Unpacking the shop files.\n'
    # As root, so every file keeps the www-data ownership it has in production.
    docker run --rm --network none --user root --entrypoint tar \
        --mount "type=volume,src=$HTML_VOLUME,dst=/var/www/html,volume-nocopy=true" \
        --mount "type=bind,src=$DEV_DIR/html.tar.gz,dst=/import/html.tar.gz,readonly" \
        "$(app_image)" -xzpf /import/html.tar.gz --same-owner -C /var/www/html
    printf 'Starting Shopware without a network route out.\n'
    start_application
    write_env_local
    printf 'Importing the archive.\n'
    database --execute="DROP DATABASE IF EXISTS \`$(database_name)\`"
    tar -xzOf "$DEV_DIR/archive.tar.gz" dump.sql | database
    neutralise
    start_proxy
    wait_for_application
    cmd_status
}

cmd_up() {
    docker volume inspect "$HTML_VOLUME" "$MYSQL_VOLUME" >/dev/null 2>&1 \
        || die "no mirror for $SERVICE. Run fetch and restore first."
    remove_containers
    start_application
    docker exec "$APP" grep -q '^# sdwa5 dev mirror' /var/www/html/.env.local \
        || die "the mirror's .env.local is not neutralised. Run restore."
    neutralise
    start_proxy
    report_application
    cmd_status
}

cmd_down() {
    remove_containers
    docker network rm "$NETWORK" "$WEB_NETWORK" >/dev/null 2>&1 || true
    printf 'Stopped. The data stays in the volumes %s and %s.\n' "$HTML_VOLUME" "$MYSQL_VOLUME"
}

cmd_purge() {
    cmd_down >/dev/null
    docker volume rm --force "$HTML_VOLUME" "$MYSQL_VOLUME" >/dev/null
    rm -rf -- "$DEV_DIR"
    printf 'Removed the mirror of %s and %s.\n' "$SERVICE" "$DEV_DIR"
}

# Composer needs the package servers, which the mirror cannot reach, so it
# runs in a container of its own on the proxy's network. That container runs
# Composer only and none of Shopware's services, and Composer's scripts are
# skipped for the commands that run them, because they boot Shopware. They run
# inside the mirror afterwards, for example `console assets:install`.
cmd_composer() {
    docker volume inspect "$HTML_VOLUME" >/dev/null 2>&1 \
        || die "no mirror for $SERVICE. Run fetch and restore first."
    local -a extra=()
    case "${1:-}" in install|update|require|remove) extra=(--no-scripts) ;; esac
    ensure_networks
    docker run --rm --network "$WEB_NETWORK" --user www-data --workdir /var/www/html \
        --entrypoint composer \
        --mount "type=volume,src=$HTML_VOLUME,dst=/var/www/html,volume-nocopy=true" \
        "$(app_image)" --no-interaction "$@" "${extra[@]}"
}

cmd_console() {
    [[ "$(docker inspect --format '{{.State.Running}}' "$APP" 2>/dev/null)" == true ]] \
        || die "the mirror is not running. Run up first."
    console "$@"
}

# docker inspect prints an empty line for a missing object before it fails,
# so its output is dropped on failure rather than followed by the fallback.
inspect_or_absent() {
    local out
    out="$(docker "$@" 2>/dev/null)" || out=''
    printf '%s' "${out:-absent}"
}

cmd_status() {
    local state
    state="$(inspect_or_absent inspect --format '{{.State.Status}}' "$APP")"
    printf 'application\t%s\t%s\n' "$state" "$(app_image)"
    printf 'proxy\t%s\t127.0.0.1:%s\n' "$(inspect_or_absent inspect --format '{{.State.Status}}' "$PROXY")" "$DEV_PORT"
    printf 'egress\t%s\n' "$(inspect_or_absent network inspect --format '{{if .Internal}}none{{else}}OPEN{{end}}' "$NETWORK")"
    if [[ "$state" == running ]]; then
        printf 'version\t%s\n' "$(console --version 2>/dev/null || printf 'unknown')"
        printf 'mails\t%s\n' "$(console system:config:get core.mailerSettings.disableDelivery 2>/dev/null \
            | grep -q -E '=> (1|true)$' && printf 'disabled' || printf 'ENABLED')"
        printf 'services\t%s active\n' "$(database --batch --skip-column-names --database="$(database_name)" \
            --execute='SELECT COUNT(*) FROM app WHERE active = 1 AND self_managed = 1' 2>/dev/null || printf 'unknown')"
        printf 'url\t%s/\n' "$LOCAL_URL"
    fi
}

main() {
    case "${1:-}" in
        fetch) cmd_fetch ;;
        restore) cmd_restore ;;
        up) cmd_up ;;
        down) cmd_down ;;
        status) cmd_status ;;
        purge) cmd_purge ;;
        composer) shift; cmd_composer "$@" ;;
        console) shift; cmd_console "$@" ;;
        -h|--help) usage ;;
        "") usage; exit 2 ;;
        *) die "unknown command: $1. Try --help." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
