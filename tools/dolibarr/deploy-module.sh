#!/usr/bin/env bash
#
# Install or update a Dolibarr custom module from a git repository, pinned to a tag.
#
# Runs on the VPS as root. The module lands in the directory that docker-compose bind-mounts to
# /var/www/html/custom in both Dolibarr containers, so the web container and the one running
# scheduled jobs see the same code. A tag rather than a branch is checked out, so what runs in
# production is always a named release and a rollback is the same command with the older tag.
#
# The checkout is handed to the container's web user afterwards. Dolibarr reads it as www-data
# (uid 1000), and git, run as root on a tree root does not own, needs safe.directory for every call,
# which is why each git call below carries it.
#
# Nothing in Dolibarr is switched on by this script. Activating the module, or deactivating and
# activating it again so that new scheduled jobs, boxes and menus get registered, stays a step in
# Setup -> Modules, done by a person.
#
# Usage:
#   deploy-module.sh NAME REPO TAG    e.g. deploy-module.sh banksync https://github.com/SdWa5/banksync.git v1.0.0
#   deploy-module.sh --help
#
# Environment:
#   CUSTOM_DIR     module root, default /opt/docker/dolibarr-custom-data
#   MODULE_OWNER   owner:group handed the checkout, default 1000:1000, empty skips the chown

set -euo pipefail

CUSTOM_DIR="${CUSTOM_DIR:-/opt/docker/dolibarr-custom-data}"
MODULE_OWNER="${MODULE_OWNER-1000:1000}"

usage() {
    sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf 'deploy-module.sh: %s\n' "$*" >&2
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

[[ $# -eq 3 ]] || die "expected NAME REPO TAG, see --help"

NAME="$1"
REPO="$2"
TAG="$3"

# The name becomes a directory under custom/ and Dolibarr's module name, so it stays a plain word.
[[ "$NAME" =~ ^[a-z0-9_]+$ ]] || die "NAME must match [a-z0-9_]+, got '$NAME'"
[[ -n "$REPO" ]] || die "REPO is empty"
[[ -n "$TAG" && "$TAG" != -* ]] || die "TAG is empty or looks like an option"
[[ -d "$CUSTOM_DIR" ]] || die "$CUSTOM_DIR does not exist"

TARGET="$CUSTOM_DIR/$NAME"

g() {
    git -c safe.directory="$TARGET" -C "$TARGET" "$@"
}

if [[ -e "$TARGET" && ! -d "$TARGET/.git" ]]; then
    die "$TARGET exists but is not a git checkout, refusing to touch it"
fi

if [[ ! -d "$TARGET" ]]; then
    git clone --quiet --no-checkout "$REPO" "$TARGET" || die "clone of $REPO failed"
    previous="none"
else
    origin="$(g remote get-url origin)"
    [[ "$origin" == "$REPO" ]] || die "$TARGET tracks $origin, not $REPO"
    previous="$(g rev-parse --short HEAD 2>/dev/null || echo none)"
    g fetch --quiet --tags --force origin || die "fetch from $REPO failed"
fi

commit="$(g rev-parse --verify --quiet "refs/tags/$TAG^{commit}")" || die "tag $TAG not found in $REPO"

if [[ -n "$(g status --porcelain --untracked-files=no 2>/dev/null)" ]] && [[ "$previous" != "none" ]]; then
    die "$TARGET has local changes, refusing to overwrite them"
fi

g -c advice.detachedHead=false checkout --quiet --detach "$commit"

if [[ -n "$MODULE_OWNER" ]]; then
    chown -R "$MODULE_OWNER" "$TARGET"
fi

printf '%s: %s -> %s (%s)\n' "$NAME" "$previous" "$TAG" "${commit:0:7}"
