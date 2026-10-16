#!/usr/bin/env bash
#
# A local Dolibarr dev mirror of erp.sdwa5.org, for module and API work.
#
# It runs the production images against a
# copy of the newest production database archive, bound to 127.0.0.1 only. It
# never writes to production: `fetch` reads one archive over ssh, and every
# other command acts on local containers and on the data directory below.
#
# The copy holds real member data, so it lives outside the repository in a
# private directory, and it is made harmless before Apache starts:
#   - MAIN_DISABLE_ALL_MAILS=1, so nothing is ever sent
#   - every scheduled job disabled, and no cron container at all, so the
#     BankSync PayPal job cannot run
#   - its own instance key, so secrets that production stored encrypted with
#     its key cannot be decrypted here, and production API keys do not work
#   - no /run/secrets mount, so module credentials such as paypal.json are absent
#
# Usage:
#   tools/dolibarr/dev-instance.sh fetch      copy the newest production archive
#   tools/dolibarr/dev-instance.sh restore    rebuild the mirror from that archive
#   tools/dolibarr/dev-instance.sh up         start the mirror again
#   tools/dolibarr/dev-instance.sh down       stop and remove its containers
#   tools/dolibarr/dev-instance.sh status     containers, version and URL
#   tools/dolibarr/dev-instance.sh api-key [LOGIN]
#                                             give LOGIN (default admin) a local API key,
#                                             kept in <data directory>/api-key
#   tools/dolibarr/dev-instance.sh --help
#
# Environment:
#   SDWA5_DOLIBARR_DEV_DIR       data directory, default ~/.local/share/sdwa5-dolibarr-dev
#   SDWA5_DOLIBARR_DEV_PORT      local port, default 8089
#   SDWA5_DOLIBARR_DEV_IMAGE     application image, default the one docker-compose.yml pins
#   SDWA5_DOLIBARR_DEV_MODULES   space-separated name=path pairs mounted into custom/,
#                                default banksync=<this repo>/../sdwa5-banksync
#                                pmtools=<this repo>/../sdwa5-pmtools
#   SDWA5_DOLIBARR_SSH           production host, default root@sdwa5.org
#   SDWA5_DOLIBARR_ARCHIVE       archive path on the host,
#                                default /opt/docker/database-backup/dolibarr_db.tar.gz

set -euo pipefail
umask 077

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_DIR="${SDWA5_DOLIBARR_DEV_DIR:-$HOME/.local/share/sdwa5-dolibarr-dev}"
DEV_PORT="${SDWA5_DOLIBARR_DEV_PORT:-8089}"
DEV_SSH="${SDWA5_DOLIBARR_SSH:-root@sdwa5.org}"
DEV_ARCHIVE_REMOTE="${SDWA5_DOLIBARR_ARCHIVE:-/opt/docker/database-backup/dolibarr_db.tar.gz}"
DEV_MODULES="${SDWA5_DOLIBARR_DEV_MODULES:-banksync=$REPO_ROOT/../sdwa5-banksync pmtools=$REPO_ROOT/../sdwa5-pmtools}"
PREFIX="sdwa5-dolibarr-dev"
APP="$PREFIX"
DB="$PREFIX-db"
NETWORK="$PREFIX"
WEB_NETWORK="$PREFIX-web"

usage() { sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'dev-instance.sh: %s\n' "$*" >&2; exit 1; }

# The image a service of docker-compose.yml pins, so the mirror follows every
# production bump without a second place to edit.
compose_image() {
    awk -v service="  $1:" '
        $0 == service { found = 1; next }
        found && /^  [a-z_]+:$/ { exit }
        found && /^ +image:/ { print $2; exit }' "$REPO_ROOT/docker-compose.yml"
}

app_image() { printf '%s' "${SDWA5_DOLIBARR_DEV_IMAGE:-$(compose_image dolibarr)}"; }
db_image() { compose_image dolibarr_db; }

# Credentials of the local copy. Generated once, readable by the owner only,
# and handed to the containers as env files, so they never reach the
# terminal or the process list.
ensure_secrets() {
    mkdir -p "$DEV_DIR"
    [[ -s "$DEV_DIR/db.env" ]] && return 0
    local password instance
    password="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    instance="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf 'MARIADB_ROOT_PASSWORD=%s\n' "$password" > "$DEV_DIR/db.env"
    printf 'DOLI_DB_PASSWORD=%s\nDOLI_INSTANCE_UNIQUE_ID=%s\n' "$password" "$instance" > "$DEV_DIR/app.env"
}

# Every statement runs inside the database container, which reads the root
# password from its own environment.
database() {
    docker exec -i "$DB" sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb --no-defaults --user=root "$@"' sh "$@"
}

database_name() {
    awk -F '\t' '$1 == "database" { print $2 }' "$DEV_DIR/archive/manifest.tsv"
}

remove_containers() {
    docker rm -f "$APP" "$DB" >/dev/null 2>&1 || true
}

start_database() {
    docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --internal "$NETWORK" >/dev/null
    docker run --detach --name "$DB" --network "$NETWORK" \
        --env-file "$DEV_DIR/db.env" \
        --mount "type=bind,src=$DEV_DIR/db,dst=/var/lib/mysql" \
        "$(db_image)" >/dev/null
    local attempt
    for (( attempt = 0; attempt < 120; attempt++ )); do
        database --execute='SELECT 1' >/dev/null 2>&1 && return 0
        sleep 1
    done
    die "the database container did not come up. docker logs $DB shows why."
}

# Module checkouts are bind-mounted one by one, so the mirror runs the working
# tree that is being developed rather than a released tag.
module_mounts() {
    local pair name path
    for pair in $DEV_MODULES; do
        name="${pair%%=*}"
        path="${pair#*=}"
        [[ "$name" =~ ^[a-z0-9_]+$ ]] || die "module name \"$name\" is not lowercase alphanumeric."
        [[ -d "$path" ]] || die "module $name: no directory at $path."
        printf -- '--mount\0type=bind,src=%s,dst=/var/www/html/custom/%s\0' "$(cd "$path" && pwd)" "$name"
    done
}

start_application() {
    local -a mounts=()
    local item
    while IFS= read -r -d '' item; do mounts+=("$item"); done < <(module_mounts)
    # Without install.lock the image compares the database version with its own
    # and migrates only when the database is older, so another image upgrades
    # the copy and the same image just locks again.
    rm -f -- "$DEV_DIR/documents/install.lock"
    docker network inspect "$WEB_NETWORK" >/dev/null 2>&1 || docker network create "$WEB_NETWORK" >/dev/null
    docker run --detach --name "$APP" --network "$WEB_NETWORK" \
        --publish "127.0.0.1:$DEV_PORT:80" \
        --env-file "$DEV_DIR/app.env" \
        --env DOLI_DB_HOST="$DB" --env "DOLI_DB_NAME=$(database_name)" --env DOLI_DB_USER=root \
        --env DOLI_INIT_DEMO=0 --env DOLI_INSTALL_AUTO=1 --env DOLI_CRON=0 \
        --env "DOLI_URL_ROOT=http://localhost:$DEV_PORT" \
        --env WWW_USER_ID="$(id -u)" --env WWW_GROUP_ID="$(id -g)" \
        --mount "type=bind,src=$DEV_DIR/documents,dst=/var/www/documents" \
        "${mounts[@]}" \
        "$(app_image)" apache2-foreground >/dev/null
    # A port cannot be published from an --internal network, so the application
    # starts on its own network and joins the database's afterwards. The
    # database stays reachable from the application only.
    docker network connect "$NETWORK" "$APP"
}

wait_for_application() {
    local attempt code
    for (( attempt = 0; attempt < 300; attempt++ )); do
        code="$(curl --silent --output /dev/null --max-time 2 --write-out '%{http_code}' \
            "http://127.0.0.1:$DEV_PORT/" || true)"
        [[ "$code" == 200 || "$code" == 302 ]] && return 0
        [[ "$(docker inspect --format '{{.State.Running}}' "$APP" 2>/dev/null)" == true ]] \
            || die "the application container stopped. docker logs $APP shows why."
        sleep 1
    done
    die "the application did not answer on port $DEV_PORT within 300 s."
}

# Applied to the restored copy before Apache ever starts, so not a single
# request runs against an unneutralised production configuration.
neutralise() {
    database --database="$(database_name)" <<'SQL'
DELETE FROM llx_const WHERE name = 'MAIN_DISABLE_ALL_MAILS';
INSERT INTO llx_const (name, entity, value, type, visible, note)
    VALUES ('MAIN_DISABLE_ALL_MAILS', 0, '1', 'chaine', 0, 'sdwa5 dev mirror: never send mail');
UPDATE llx_cronjob SET status = 0;
SQL
}

cmd_fetch() {
    mkdir -p "$DEV_DIR"
    printf 'Copying %s:%s\n' "$DEV_SSH" "$DEV_ARCHIVE_REMOTE"
    # The path is meant to expand here and is quoted for the remote shell.
    # shellcheck disable=SC2029
    ssh "$DEV_SSH" "cat $(printf '%q' "$DEV_ARCHIVE_REMOTE")" > "$DEV_DIR/archive.tar.gz.part"
    gzip -t "$DEV_DIR/archive.tar.gz.part" || die "the copied archive is not a valid gzip file."
    # The listing is captured first, because grep -q stops reading early and
    # pipefail would report tar's SIGPIPE as a missing file.
    local listing
    listing="$(tar -tzf "$DEV_DIR/archive.tar.gz.part")"
    grep -qx 'dump.sql' <<< "$listing" || die "the archive holds no dump.sql."
    mv "$DEV_DIR/archive.tar.gz.part" "$DEV_DIR/archive.tar.gz"
    printf 'Archive of %s bytes stored in %s\n' "$(stat -c %s "$DEV_DIR/archive.tar.gz")" "$DEV_DIR"
}

cmd_restore() {
    [[ -r "$DEV_DIR/archive.tar.gz" ]] || die "no archive in $DEV_DIR. Run fetch first."
    ensure_secrets
    remove_containers
    rm -rf -- "$DEV_DIR/archive" "$DEV_DIR/db" "$DEV_DIR/documents"
    mkdir -p "$DEV_DIR/archive" "$DEV_DIR/db" "$DEV_DIR/documents"
    tar -xzf "$DEV_DIR/archive.tar.gz" -C "$DEV_DIR/archive" -- dump.sql manifest.tsv
    [[ "$(awk -F '\t' '$1 == "coverage" { print $2 }' "$DEV_DIR/archive/manifest.tsv")" == full ]] \
        || die "the archive is not a full dump."
    [[ -n "$(database_name)" ]] || die "the archive manifest names no database."
    start_database
    printf 'Importing the archive.\n'
    database < "$DEV_DIR/archive/dump.sql"
    rm -f -- "$DEV_DIR/archive/dump.sql"
    neutralise
    start_application
    wait_for_application
    cmd_status
}

cmd_up() {
    [[ -d "$DEV_DIR/db" && -s "$DEV_DIR/db.env" ]] || die "no mirror in $DEV_DIR. Run fetch and restore first."
    remove_containers
    start_database
    neutralise
    start_application
    wait_for_application
    cmd_status
}

cmd_down() {
    remove_containers
    docker network rm "$NETWORK" "$WEB_NETWORK" >/dev/null 2>&1 || true
    printf 'Stopped. The data stays in %s\n' "$DEV_DIR"
}

cmd_status() {
    local state version
    state="$(docker inspect --format '{{.State.Status}}' "$APP" 2>/dev/null || printf 'absent')"
    printf 'application\t%s\t%s\n' "$state" "$(app_image)"
    printf 'database\t%s\t%s\n' "$(docker inspect --format '{{.State.Status}}' "$DB" 2>/dev/null || printf 'absent')" "$(db_image)"
    if [[ "$state" == running ]]; then
        version="$(database --batch --skip-column-names --database="$(database_name)" \
            --execute="SELECT value FROM llx_const WHERE name = 'MAIN_VERSION_LAST_UPGRADE' AND entity = 0" 2>/dev/null || true)"
        printf 'version\t%s\n' "${version:-unknown}"
        printf 'mails\t%s\n' "$(database --batch --skip-column-names --database="$(database_name)" \
            --execute="SELECT IF(value = '1', 'disabled', 'ENABLED') FROM llx_const WHERE name = 'MAIN_DISABLE_ALL_MAILS'" 2>/dev/null || printf 'unknown')"
        printf 'url\thttp://localhost:%s/\n' "$DEV_PORT"
    fi
}

# Production API keys cannot be decrypted here, because the mirror has its own
# instance key. This gives one user a key of the mirror's own, generated once
# into a private file and handed to the container on stdin, so it never shows
# up in the terminal or the process list. dolEncrypt() stores it the way the
# user card does. Running PHP in the container is acceptable here because it
# only ever touches the local copy.
cmd_api_key() {
    local login="${1:-admin}" key_file="$DEV_DIR/api-key"
    [[ "$login" =~ ^[A-Za-z0-9._@-]+$ ]] || die "not a login: $login"
    [[ "$(docker inspect --format '{{.State.Status}}' "$APP" 2>/dev/null)" == running ]] \
        || die "the mirror is not running. Start it with up first."
    [[ -s "$key_file" ]] || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$key_file"
    docker exec -i -u www-data -e "DEV_LOGIN=$login" "$APP" php -r '
        define("NOSESSION", 1); define("NOREQUIREMENU", 1); define("NOREQUIREHTML", 1); define("NOREQUIREAJAX", 1);
        require "/var/www/html/master.inc.php";
        $key = trim(stream_get_contents(STDIN));
        $login = getenv("DEV_LOGIN");
        $where = " WHERE login = \x27".$db->escape($login)."\x27";
        if (!$db->num_rows($db->query("SELECT rowid FROM ".MAIN_DB_PREFIX."user".$where))) {
            exit(3);
        }
        $value = $db->escape(dolEncrypt($key, "", "", "dolibarr"));
        exit($db->query("UPDATE ".MAIN_DB_PREFIX."user SET api_key = \x27".$value."\x27".$where) ? 0 : 4);
    ' < "$key_file" || die "no user $login on the mirror, or the update failed."
    printf 'API key for %s stored in %s\n' "$login" "$key_file"
}

main() {
    case "${1:-}" in
        fetch) cmd_fetch ;;
        restore) cmd_restore ;;
        up) cmd_up ;;
        down) cmd_down ;;
        status) cmd_status ;;
        api-key) cmd_api_key "${2:-}" ;;
        -h|--help) usage ;;
        "") usage; exit 2 ;;
        *) die "unknown command: $1. Try --help." ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
