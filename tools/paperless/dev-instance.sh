#!/usr/bin/env bash
#
# A local Paperless-ngx dev mirror of paper.sdwa5.org or paper.ripper.sdwa5.org.
#
# It runs the production images and the shared settings of docker-compose.yml
# as an empty instance, bound to 127.0.0.1 only. It holds no production data
# and never talks to production. It exists to try setup.sh and
# visibility-check.sh against a real Paperless before they touch production,
# and to measure what an instance costs in memory.
#
# Mail stays off because no EMAIL_* setting is passed. The application reaches
# its database and broker on an internal network, and only the web port is
# published.
#
# Usage:
#   tools/paperless/dev-instance.sh up [INSTANCE]      start, creating it on first use
#   tools/paperless/dev-instance.sh down [INSTANCE]    stop and remove its containers
#   tools/paperless/dev-instance.sh status [INSTANCE]  containers, memory and URL
#   tools/paperless/dev-instance.sh purge [INSTANCE]   down, then delete its data
#   tools/paperless/dev-instance.sh --help
#
# INSTANCE is sdwa5 (the Verein, default) or home (the household).
#
# The admin password is generated once into <data directory>/<INSTANCE>/passwords/admin,
# which is where setup.sh and visibility-check.sh look for it with the matching
# spec (see tools/paperless/paperless-spec.example.json).
#
# Environment:
#   SDWA5_PAPERLESS_DEV_DIR    data directory, default ~/.local/share/sdwa5-paperless-dev
#   SDWA5_PAPERLESS_DEV_PORT   local port, default 8106 for sdwa5 and 8107 for home

set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_ROOT="${SDWA5_PAPERLESS_DEV_DIR:-$HOME/.local/share/sdwa5-paperless-dev}"

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'dev-instance.sh: %s\n' "$*" >&2; exit 1; }

# The image a service of docker-compose.yml pins, so the mirror follows every
# production bump without a second place to edit. An anchor (`&name`) in front
# of the image is skipped.
compose_image() {
    awk -v service="  $1:" '
        $0 == service { found = 1; next }
        found && /^  [a-z_]+:$/ { exit }
        found && /^ +image:/ { print ($2 ~ /^&/ ? $3 : $2); exit }' "$REPO_ROOT/docker-compose.yml"
}

# The x-paperless-env block of docker-compose.yml as KEY=VALUE lines, so the
# mirror runs the same worker counts, OCR languages and switches as production.
compose_paperless_env() {
    awk '
        /^x-paperless-env:/ { found = 1; next }
        found && !/^  [A-Z_]+:/ { exit }
        found {
            key = $1; sub(/:$/, "", key)
            value = $0; sub(/^ *[A-Z_]+: */, "", value); gsub(/"/, "", value)
            print key "=" value
        }' "$REPO_ROOT/docker-compose.yml"
}

select_instance() {
    INSTANCE="${1:-sdwa5}"
    case "$INSTANCE" in
        sdwa5) DEFAULT_PORT=8106 ;;
        home) DEFAULT_PORT=8107 ;;
        *) die "unknown instance: $INSTANCE. Use sdwa5 or home." ;;
    esac
    DEV_PORT="${SDWA5_PAPERLESS_DEV_PORT:-$DEFAULT_PORT}"
    DEV_DIR="$DEV_ROOT/$INSTANCE"
    PREFIX="sdwa5-paperless-dev-$INSTANCE"
    APP="$PREFIX"
    DB="$PREFIX-db"
    BROKER="$PREFIX-broker"
    NETWORK="$PREFIX"
    WEB_NETWORK="$PREFIX-web"
}

random_hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# Credentials of the mirror. Generated once, readable by the owner only, and
# handed to the containers as env files, so they never reach the terminal or
# the process list.
ensure_secrets() {
    mkdir -p "$DEV_DIR/passwords" "$DEV_DIR/data" "$DEV_DIR/media" "$DEV_DIR/db"
    [[ -s "$DEV_DIR/db.env" ]] && return 0
    local password
    password="$(random_hex 32)"
    random_hex 16 > "$DEV_DIR/passwords/admin"
    printf 'MARIADB_ROOT_PASSWORD=%s\nMARIADB_DATABASE=paperless\nMARIADB_USER=paperless\nMARIADB_PASSWORD=%s\n' \
        "$(random_hex 32)" "$password" > "$DEV_DIR/db.env"
    printf 'PAPERLESS_SECRET_KEY=%s\nPAPERLESS_DBPASS=%s\nPAPERLESS_ADMIN_USER=admin\nPAPERLESS_ADMIN_PASSWORD=%s\n' \
        "$(random_hex 32)" "$password" "$(< "$DEV_DIR/passwords/admin")" > "$DEV_DIR/app.env"
}

remove_containers() {
    docker rm -f "$APP" "$BROKER" "$DB" >/dev/null 2>&1 || true
}

start_backends() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --internal "$NETWORK" >/dev/null
    docker run --detach --name "$DB" --network "$NETWORK" \
        --env-file "$DEV_DIR/db.env" \
        --mount "type=bind,src=$DEV_DIR/db,dst=/var/lib/mysql" \
        "$(compose_image paperless_sdwa5_db)" --innodb-buffer-pool-size=64M >/dev/null
    docker run --detach --name "$BROKER" --network "$NETWORK" \
        "$(compose_image paperless_sdwa5_broker)" >/dev/null
}

start_application() {
    docker network inspect "$WEB_NETWORK" >/dev/null 2>&1 || docker network create "$WEB_NETWORK" >/dev/null
    docker run --detach --name "$APP" --network "$WEB_NETWORK" \
        --publish "127.0.0.1:$DEV_PORT:8000" \
        --env-file <(compose_paperless_env) \
        --env-file "$DEV_DIR/app.env" \
        --env "PAPERLESS_URL=http://localhost:$DEV_PORT" \
        --env "PAPERLESS_COOKIE_PREFIX=dev$INSTANCE" \
        --env "PAPERLESS_DBHOST=$DB" \
        --env "PAPERLESS_REDIS=redis://$BROKER:6379" \
        --env USERMAP_UID="$(id -u)" --env USERMAP_GID="$(id -g)" \
        --mount "type=bind,src=$DEV_DIR/data,dst=/usr/src/paperless/data" \
        --mount "type=bind,src=$DEV_DIR/media,dst=/usr/src/paperless/media" \
        "$(compose_image paperless_sdwa5)" >/dev/null
    # A port cannot be published from an --internal network, so the application
    # starts on its own network and joins the backends' afterwards.
    docker network connect "$NETWORK" "$APP"
}

# The first start runs every migration, which takes a few minutes. Without a
# session the API redirects to the login page.
wait_for_application() {
    local attempt code
    for (( attempt = 0; attempt < 600; attempt++ )); do
        code="$(curl --silent --output /dev/null --max-time 2 --write-out '%{http_code}' \
            "http://127.0.0.1:$DEV_PORT/api/" || true)"
        [[ "$code" == 200 || "$code" == 302 ]] && return 0
        [[ "$(docker inspect --format '{{.State.Running}}' "$APP" 2>/dev/null)" == true ]] \
            || die "the application container stopped. docker logs $APP shows why."
        sleep 1
    done
    die "the application did not answer on port $DEV_PORT within 600 s."
}

cmd_up() {
    ensure_secrets
    remove_containers
    start_backends
    start_application
    wait_for_application
    cmd_status
}

cmd_down() {
    remove_containers
    docker network rm "$NETWORK" "$WEB_NETWORK" >/dev/null 2>&1 || true
    printf 'Stopped. The data stays in %s\n' "$DEV_DIR"
}

# The database writes as its own uid, so its files are removed from inside a
# container rather than with a sudo on the host.
cmd_purge() {
    cmd_down >/dev/null
    if [[ -d "$DEV_DIR" ]]; then
        docker run --rm --mount "type=bind,src=$DEV_ROOT,dst=/purge" \
            "$(compose_image paperless_sdwa5_broker)" rm -rf -- "/purge/$INSTANCE"
    fi
    printf 'Purged %s\n' "$DEV_DIR"
}

cmd_status() {
    local name role
    for role in application database broker; do
        case "$role" in
            application) name="$APP" ;;
            database) name="$DB" ;;
            broker) name="$BROKER" ;;
        esac
        printf '%s\t%s\t%s\n' "$role" \
            "$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null || printf 'absent')" \
            "$(docker stats --no-stream --format '{{.MemUsage}}' "$name" 2>/dev/null | cut -d/ -f1 || true)"
    done
    printf 'url\thttp://localhost:%s/\n' "$DEV_PORT"
    printf 'admin password\t%s\n' "$DEV_DIR/passwords/admin"
}

main() {
    local command="${1:-}"
    case "$command" in
        -h|--help) usage; return 0 ;;
        "") usage; exit 2 ;;
        up|down|status|purge) ;;
        *) die "unknown command: $command. Try --help." ;;
    esac
    select_instance "${2:-}"
    "cmd_$command"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
