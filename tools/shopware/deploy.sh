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
#   4. a fresh backup of shopware_db, because migrations cannot be undone;
#   5. the helper in a one-off container of the new image, while the old
#      container keeps serving;
#   6. system:check --context=pre_rollout, because the health route that
#      `up --wait` waits for renders no storefront page;
#   7. the switch to the new container, which returns once its healthcheck
#      passes. Caddy holds requests meanwhile.
# A failure before step 7 leaves the old container serving.
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

deploy() {
    local image lock archive start

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

    # A concurrent backup run exits 0 without a dump, hence the mtime check.
    start="$(date +%s)"
    DATABASE_BACKUP_CONTAINERS=shopware_db monitoring/database-backup.sh \
        || die "the backup of shopware_db failed."
    archive="${DATABASE_BACKUP_DIR:-$REPO_ROOT/database-backup}/shopware_db.tar.gz"
    [[ -f "$archive" && "$(stat -c %Y "$archive")" -ge "$start" ]] \
        || die "no fresh backup at $archive; another backup run may hold its lock."

    deployment_helper one_off \
        || die "the deployment helper failed. The old container still serves; see docs/shopware/image.md#rollback."

    if [[ "$(db_query 'SELECT COUNT(*) FROM sales_channel WHERE maintenance = 1')" == 0 ]]; then
        one_off php bin/console system:check --context=pre_rollout --no-interaction \
            || die "system:check failed. The old container still serves; see docs/shopware/image.md#rollback."
    else
        printf 'Skipping system:check: a sales channel is in maintenance mode.\n'
    fi

    docker compose up -d --no-deps --wait --wait-timeout 360 shopware
    printf 'Deployed %s.\n' "$image"
}

case "${1:-}" in
    '') deploy ;;
    --help|-h) sw_usage ;;
    *) sw_usage >&2; exit 2 ;;
esac
