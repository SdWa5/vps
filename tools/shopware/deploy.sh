#!/usr/bin/env bash
#
# Deploy the sdwa5.org shop image on the host (docs/shopware/image.md#deploy).
#
# Runs on the host from /opt/docker after `tools/shopware/image.sh ship` and
# `git pull`. It deploys the image that docker-compose.yml names with Shopware's
# deployment helper and never installs a shop. The order:
#   1. the image must be on the host;
#   2. the worker cron's lock, so no scheduled task or queue consumer runs
#      against a half-migrated database;
#   3. shopware_db must answer and hold an installed shop;
#   4. for a new Shopware core version, maintenance mode for every sales
#      channel in the serving container, so no order lands between the backup
#      and the migrations;
#   5. a fresh backup of shopware_db, because migrations cannot be undone;
#   6. the helper in a one-off container of the new image, while the old
#      container keeps serving;
#   7. system:check --context=pre_rollout, because the health route that
#      `up --wait` waits for renders no storefront page. Under maintenance it
#      runs after the switch instead, since it cannot pass before;
#   8. the switch to the new container, which returns once its healthcheck
#      passes. Caddy holds requests meanwhile. Maintenance then goes off.
# A failure before step 8 leaves the old container serving and switches
# maintenance off again.
#
# It needs Compose v2 for `up --wait`, so it calls `docker compose` rather than
# tools/compose.sh, whose v1 fallback lacks --wait.
#
# Usage, on the host as root:
#   tools/shopware/deploy.sh
#   tools/shopware/deploy.sh --help
#
# Environment:
#   COMPOSE_DIR                 directory of docker-compose.yml, default the repository
#   SHOPWARE_DEPLOY_LOCK        the worker's lock, default /run/lock/shopware-worker.lock
#   SHOPWARE_DEPLOY_LOCK_WAIT   seconds to wait for it, default 120
#   DATABASE_BACKUP_DIR         where database-backup.sh writes, default COMPOSE_DIR/database-backup

set -euo pipefail

# Its callers are heredocs, whose remaining lines docker compose run would read.
exec </dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${COMPOSE_DIR:-$SCRIPT_DIR/../..}"
# shellcheck source=tools/shopware/lib.sh
source "$SCRIPT_DIR/lib.sh"

one_off() {
    docker compose run --rm --no-deps -T --name shopware-deploy shopware "$@"
}

db_query() {
    # shellcheck disable=SC2016 # expanded inside the container
    docker exec shopware_db sh -c 'MYSQL_PWD="$(cat "$MYSQL_PASSWORD_FILE")" exec mysql --no-defaults -h 127.0.0.1 -u"$MYSQL_USER" -N -B "$MYSQL_DATABASE" -e "$1"' sh "$1"
}

# The tag without its build number, e.g. 6.7.16.0 for …:6.7.16.0-1.
core_version() {
    local tag="${1##*:}"
    printf '%s\n' "${tag%-*}"
}

# Each container caches the maintenance flag, so it is set and cleared through
# the serving container and followed by a cache clear there.
serving_console() {
    docker exec shopware php bin/console "$@" --no-interaction
}

maintenance_off() {
    serving_console sales-channel:maintenance:disable --all
    serving_console cache:clear
    printf 'Maintenance off at %s.\n' "$(date +%T)"
}

deploy() {
    local image lock archive start running maintenance=0

    cd "$REPO_ROOT"
    image="$(compose_image shopware)"
    docker image inspect "$image" >/dev/null 2>&1 \
        || die "$image is not on this host. Run tools/shopware/image.sh ship first."

    # The cron's flock -n skips every run until this script exits.
    lock="${SHOPWARE_DEPLOY_LOCK:-/run/lock/shopware-worker.lock}"
    exec 9>"$lock"
    flock -w "${SHOPWARE_DEPLOY_LOCK_WAIT:-120}" 9 || die "the worker still holds $lock."

    docker compose up -d --no-deps shopware_db
    docker exec shopware_db mysqladmin --no-defaults -h 127.0.0.1 --wait=24 --connect-timeout=5 ping >/dev/null \
        || die "shopware_db does not answer."
    one_off vendor/bin/shopware-deployment-helper is-installed >/dev/null \
        || die "shopware_db holds no installed shop or does not answer. deploy.sh never installs one."

    # The helper's own maintenance option would set the flag from the one-off
    # container only (docs/shopware/image.md#deploy).
    # A sales channel already in maintenance leaves the switch to the operator.
    running="$(docker inspect -f '{{.Config.Image}}' shopware 2>/dev/null || true)"
    if [[ -n "$running" && "$(core_version "$running")" != "$(core_version "$image")" ]] \
        && [[ "$(db_query 'SELECT COUNT(*) FROM sales_channel WHERE maintenance = 1')" == 0 ]]; then
        serving_console sales-channel:maintenance:enable --all
        maintenance=1
        trap maintenance_off EXIT
        serving_console cache:clear
        printf 'Maintenance on at %s for %s -> %s.\n' "$(date +%T)" "$(core_version "$running")" "$(core_version "$image")"
    fi

    # A concurrent backup run exits 0 without a dump, hence the mtime check.
    start="$(date +%s)"
    DATABASE_BACKUP_CONTAINERS=shopware_db monitoring/database-backup.sh \
        || die "the backup of shopware_db failed."
    archive="${DATABASE_BACKUP_DIR:-$REPO_ROOT/database-backup}/shopware_db.tar.gz"
    [[ -f "$archive" && "$(stat -c %Y "$archive")" -ge "$start" ]] \
        || die "no fresh backup at $archive; another backup run may hold its lock."

    deployment_helper one_off \
        || die "the deployment helper failed. The old container still serves; see docs/shopware/image.md#rollback."

    if ((maintenance == 0)) && [[ "$(db_query 'SELECT COUNT(*) FROM sales_channel WHERE maintenance = 1')" == 0 ]]; then
        one_off php bin/console system:check --context=pre_rollout --no-interaction \
            || die "system:check failed. The old container still serves; see docs/shopware/image.md#rollback."
    else
        printf 'Skipping system:check: a sales channel is in maintenance mode.\n'
    fi

    # From here on the new code runs the migrated database, so a failure keeps
    # maintenance on rather than reopening the shop.
    trap - EXIT
    docker compose up -d --no-deps --wait --wait-timeout 360 shopware \
        || die "the new container did not become healthy.$( ((maintenance)) && printf ' Maintenance stays on.') See docs/shopware/image.md#rollback."
    if ((maintenance)); then
        maintenance_off
        serving_console system:check --context=pre_rollout \
            || die "system:check failed on the new container. See docs/shopware/image.md#rollback."
    fi
    printf 'Deployed %s.\n' "$image"
}

case "${1:-}" in
    '') deploy ;;
    --help|-h) sw_usage ;;
    *) sw_usage >&2; exit 2 ;;
esac
