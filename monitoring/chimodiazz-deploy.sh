#!/usr/bin/env bash
#
# Deploys chimodiazz/website to the Chimo Diazz Shopware instance.
#
# The site's theme lives in a repository this host does not own and cannot push
# to. It is checked out at chimodiazz-src/ with a read-only deploy key and
# mounted into the container, so a deployment is a fetch, a reset and a theme
# rebuild. Nothing is built here and nothing is uploaded here.
#
# **Pull rather than push, and that is a deliberate departure from TODO.md.**
# That file settled on a push-based GitHub Action for *this* repository on
# 2026-09-03 and asked not to re-open the comparison. This is a different
# repository with a different owner: a push deployment would put an SSH key into
# chimodiazz/website's GitHub secrets, where its collaborators and permissions
# are administered by someone else. Pulling keeps the credential on this host,
# keeps it read-only and opens nothing inbound. The decision for SdWa5/vps
# stands untouched.
#
# Silent when there is nothing to do, which is most runs. One mail when a deploy
# fails, because an all-green mail every five minutes trains the recipient to
# ignore the mail.
#
# Runs from /etc/cron.d/chimodiazz-deploy every five minutes under `flock -n`.
#
# Usage:
#   chimodiazz-deploy.sh              fetch, deploy if changed, verify
#   chimodiazz-deploy.sh --force      deploy even when the commit is unchanged
#   chimodiazz-deploy.sh --dry-run    report what would happen, change nothing
#   chimodiazz-deploy.sh --help

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

SERVICE="${SERVICE:-chimodiazz_shopware}"
SRC_DIR="${SRC_DIR:-$COMPOSE_DIR/chimodiazz-src}"
PLUGIN="${PLUGIN:-ChimodiazzTheme}"
HEALTH_URL="${HEALTH_URL:-https://chimodiazz.sdwa5.org/}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-90}"
CONSOLE="${CONSOLE:-php bin/console}"

# Whatever branch the checkout sits on. Switching what gets deployed is then a
# `git switch` in chimodiazz-src/ rather than an edit here, and the deployed
# branch is visible to anyone who looks at the directory. There is deliberately
# no attempt to follow the remote's default branch: that ref is written once at
# clone time and would quietly stop matching.
BRANCH="${BRANCH:-}"

DRY_RUN=0
FORCE=0

git_src() {
    git -C "$SRC_DIR" "$@"
}

current_branch() {
    git_src rev-parse --abbrev-ref HEAD 2>/dev/null
}

local_commit() {
    git_src rev-parse HEAD 2>/dev/null
}

remote_commit() {
    git_src rev-parse "origin/$BRANCH" 2>/dev/null
}

# Every console call goes through here so a failure carries the command and the
# output into the alert mail rather than into a log nobody reads.
console() {
    local out rc
    # CONSOLE is "php bin/console" and has to split into two arguments, so the
    # word splitting here is the point rather than an oversight.
    # shellcheck disable=SC2086
    out="$(docker exec "$SERVICE" $CONSOLE "$@" 2>&1)"
    rc=$?
    if (( rc != 0 )); then
        FAILURE_DETAIL="$CONSOLE $* exited $rc:

$out"
        return 1
    fi
    return 0
}

# plugin:refresh makes Shopware notice a changed plugin version, plugin:update
# runs its migrations, theme:compile rebuilds the storefront and cache:clear
# makes the result visible. plugin:update is allowed to fail: it exits non-zero
# when there is nothing to update, which is the ordinary case for a content
# change that did not touch the plugin's version.
rebuild_theme() {
    console plugin:refresh || return 1
    # shellcheck disable=SC2086
    docker exec "$SERVICE" $CONSOLE plugin:update "$PLUGIN" >/dev/null 2>&1
    console theme:compile || return 1
    console cache:clear || return 1
    return 0
}

wait_for_health() {
    local waited=0 code
    while (( waited < HEALTH_TIMEOUT )); do
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTH_URL" 2>/dev/null)"
        [[ "$code" == "200" ]] && return 0
        sleep 5
        waited=$(( waited + 5 ))
    done
    return 1
}

# Back to the commit that was serving before. The checkout is never edited by
# hand, so a hard reset loses nothing, and the theme has to be rebuilt from the
# old source or the storefront keeps serving the broken compile.
rollback() {
    local previous="$1"
    log "Rolling back chimodiazz-src to $previous"
    git_src reset --hard "$previous" >/dev/null 2>&1
    rebuild_theme
}

usage() {
    cat <<'USAGE'
chimodiazz-deploy.sh - deploy chimodiazz/website to the Chimo Diazz instance

Fetches the checkout's current branch. If the commit is unchanged, exits
silently. Otherwise resets to it, refreshes and updates the theme plugin,
recompiles the storefront and verifies that the public site answers 200. On
failure it resets to the previous commit, rebuilds from it and mails an alert.

Deploys whatever branch chimodiazz-src/ is checked out on. Change that with a
git switch in that directory.

  chimodiazz-deploy.sh              fetch, deploy if changed, verify
  chimodiazz-deploy.sh --force      deploy even when the commit is unchanged
  chimodiazz-deploy.sh --dry-run    report what would happen, change nothing
  chimodiazz-deploy.sh --help       this text
USAGE
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --force)   FORCE=1 ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    FAILURE_DETAIL=""

    if [[ ! -d "$SRC_DIR/.git" ]]; then
        send_mail "[sdwa5] Chimo Diazz deploy: no checkout" \
"$SRC_DIR is not a git checkout on $(hostname), so nothing can be deployed. See docs/chimodiazz.md." \
            || log "no checkout at $SRC_DIR"
        exit 1
    fi

    [[ -n "$BRANCH" ]] || BRANCH="$(current_branch)"
    if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
        send_mail "[sdwa5] Chimo Diazz deploy: detached checkout" \
"$SRC_DIR is not on a branch on $(hostname), so there is nothing to follow. Check it out on the branch that should be deployed." \
            || log "detached checkout at $SRC_DIR"
        exit 1
    fi

    local before after
    before="$(local_commit)"

    if (( DRY_RUN )); then
        echo "Service:        $SERVICE"
        echo "Checkout:       $SRC_DIR"
        echo "Branch:         $BRANCH"
        echo "Local commit:   ${before:-unknown}"
        echo "Health URL:     $HEALTH_URL"
        echo "Would run:      git fetch, then compare against origin/$BRANCH"
        exit 0
    fi

    if ! git_src fetch --quiet --prune origin "$BRANCH" 2>/dev/null; then
        send_mail "[sdwa5] Chimo Diazz deploy: fetch failed" \
"git fetch origin $BRANCH failed in $SRC_DIR on $(hostname). The site is untouched and still serving $before.

This is usually the read-only deploy key: it is registered on chimodiazz/website, which this host does not own, so it can be revoked without anything here noticing. Check with: ssh -T github-chimodiazz" \
            || log "fetch failed"
        exit 1
    fi

    after="$(remote_commit)"
    if [[ -z "$after" ]]; then
        send_mail "[sdwa5] Chimo Diazz deploy: branch gone" \
"origin/$BRANCH does not exist in $SRC_DIR on $(hostname) after a successful fetch. The branch was probably renamed or deleted in chimodiazz/website. The site is untouched and still serving $before." \
            || log "origin/$BRANCH missing"
        exit 1
    fi

    if [[ "$before" == "$after" ]] && (( ! FORCE )); then
        exit 0
    fi

    log "Deploying $before -> $after"

    if ! git_src reset --hard "$after" >/dev/null 2>&1; then
        send_mail "[sdwa5] Chimo Diazz deploy: reset failed" \
"git reset --hard $after failed in $SRC_DIR on $(hostname). The site is untouched and still serving $before." \
            || log "reset failed"
        exit 1
    fi

    if ! rebuild_theme; then
        rollback "$before"
        send_mail "[sdwa5] Chimo Diazz deploy: rebuild failed, rolled back" \
"Deploying $after to https://chimodiazz.sdwa5.org failed while rebuilding the theme on $(hostname). The checkout was reset to $before and rebuilt from it.

$FAILURE_DETAIL" \
            || log "rebuild failed, rolled back"
        exit 1
    fi

    if ! wait_for_health; then
        rollback "$before"
        send_mail "[sdwa5] Chimo Diazz deploy: site did not come back, rolled back" \
"Deploying $after to https://chimodiazz.sdwa5.org rebuilt cleanly but the site did not answer 200 within ${HEALTH_TIMEOUT}s on $(hostname). The checkout was reset to $before and rebuilt from it.

Verify by hand before deploying that commit again, because the rollback rebuild was not itself health-checked." \
            || log "health check failed, rolled back"
        exit 1
    fi

    log "Deployed $after"
    exit 0
}

main "$@"
