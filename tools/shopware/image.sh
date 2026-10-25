#!/usr/bin/env bash
#
# Build, ship and maintain the sdwa5.org shop image (docs/shopware/image.md).
#
# The image is built on the workstation and loaded onto the host over ssh, so
# no registry and no build load on production are involved. The tag comes from
# the shopware service of docker-compose.yml, the only place that names it.
#
# build     exports the tracked files of shopware/ and shopware-html-data/ from
#           the working tree, uncommitted edits included, and builds them with
#           the store token as a build secret. A new file needs `git add` first.
#           The revision label gets -dirty while either directory has edits.
# ship      loads the image onto the host. A dirty build is refused, an image
#           the host already holds is skipped, and a tag the host holds as
#           another image is refused, because a shipped tag never changes.
# composer  runs Composer on shopware-html-data/ in the build stage's CLI image,
#           for example `require|update PACKAGE --no-install --no-scripts
#           --no-plugins`. The project's scripts need vendor/ and a database,
#           and Flex would write recipes, hence those flags.
#
# Usage:
#   tools/shopware/image.sh build
#   tools/shopware/image.sh ship [HOST]
#   tools/shopware/image.sh composer ARGS...
#   tools/shopware/image.sh --help
#
# Environment:
#   SDWA5_SHOPWARE_IMAGE   image, default the shopware service's; it must start
#                          with localhost/sdwa5-shopware:
#   SDWA5_SHOPWARE_AUTH    Composer auth.json with the store token,
#                          default ~/.config/sdwa5/shopware-auth.json
#   SDWA5_SHOPWARE_SSH     host for ship, default root@sdwa5.org

set -euo pipefail

REPO_ROOT="${SDWA5_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

AUTH="${SDWA5_SHOPWARE_AUTH:-$HOME/.config/sdwa5/shopware-auth.json}"
HOST="${SDWA5_SHOPWARE_SSH:-root@sdwa5.org}"
DOCKERFILE="$REPO_ROOT/shopware/Dockerfile"

image() {
    local image="${SDWA5_SHOPWARE_IMAGE:-$(compose_image shopware)}"
    [[ "$image" == localhost/sdwa5-shopware:?* ]] \
        || die "\"$image\" is not a localhost/sdwa5-shopware: image."
    printf '%s' "$image"
}

# The image of the Dockerfile's FROM line whose stage name is $1, or of the last
# FROM line without one.
from_image() {
    if [[ -n "$1" ]]; then
        awk -v stage="$1" 'toupper($1) == "FROM" && tolower($3) == "as" && $4 == stage { print $2; exit }' "$DOCKERFILE"
    else
        awk 'toupper($1) == "FROM" { last = $2 } END { print last }' "$DOCKERFILE"
    fi
}

revision() {
    local rev
    rev="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    git -C "$REPO_ROOT" diff --quiet HEAD -- shopware shopware-html-data || rev="$rev-dirty"
    printf '%s' "$rev"
}

build() {
    local image base rev
    image="$(image)"
    [[ -r "$AUTH" ]] || die "no store token at $AUTH, see docs/shopware/image.md."
    base="$(from_image '')"
    [[ "$base" == *@sha256:* ]] || die "the final FROM line of $DOCKERFILE is not pinned by digest."
    rev="$(revision)"
    # Global, because the EXIT trap runs after this function has returned.
    BUILD_DIR="$(mktemp -d)"
    trap 'rm -rf "$BUILD_DIR"' EXIT
    git -C "$REPO_ROOT" ls-files -z shopware shopware-html-data \
        | tar -C "$REPO_ROOT" --null -T - -cf - | tar -xf - -C "$BUILD_DIR"
    docker buildx build --load \
        --secret id=composer_auth,src="$AUTH" \
        --build-context project="$BUILD_DIR/shopware-html-data" \
        --label org.opencontainers.image.title=sdwa5-shopware \
        --label org.opencontainers.image.source=https://github.com/SdWa5/vps \
        --label org.opencontainers.image.revision="$rev" \
        --label org.opencontainers.image.version="${image#*:}" \
        --label org.opencontainers.image.base.name="${base%@*}" \
        --label org.opencontainers.image.base.digest="${base#*@}" \
        -t "$image" "$BUILD_DIR/shopware"
    docker image inspect -f '{{.Id}}' "$image"
}

ship() {
    local image local_id remote_id rev rc
    image="$(image)"
    local_id="$(docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)" || die "$image is not built here."
    rev="$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")"
    [[ "$rev" != *-dirty ]] || die "$image was built from uncommitted files ($rev); commit and build again."
    # docker exits 1 for an unknown image, ssh 255 when the host is out of reach.
    rc=0
    remote_id="$(ssh -o BatchMode=yes "$HOST" docker image inspect -f '{{.Id}}' "$image" 2>/dev/null)" || rc=$?
    (( rc != 255 )) || die "cannot reach $HOST."
    if [[ "$remote_id" == "$local_id" ]]; then
        printf '%s is already on the host.\n' "$image"
        return 0
    fi
    [[ -z "$remote_id" ]] \
        || die "the host holds $image as another image; raise the build number in docker-compose.yml."
    docker save "$image" | gzip -1 | ssh -o BatchMode=yes "$HOST" 'gunzip | docker load'
    remote_id="$(ssh -o BatchMode=yes "$HOST" docker image inspect -f '{{.Id}}' "$image")"
    [[ "$remote_id" == "$local_id" ]] || die "the host loaded $image as $remote_id, not $local_id."
    printf 'Shipped %s (%s).\n' "$image" "$local_id"
}

run_composer() {
    local cli
    image >/dev/null
    [[ -r "$AUTH" ]] || die "no store token at $AUTH, see docs/shopware/image.md."
    cli="$(from_image build)"
    [[ -n "$cli" ]] || die "$DOCKERFILE has no FROM ... AS build line."
    # Composer's path repository throws without this ignored directory
    # (docs/shopware/plugins.md).
    mkdir -p "$REPO_ROOT/shopware-html-data/custom/plugins"
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e COMPOSER_HOME=/tmp/composer -e COMPOSER_CACHE_DIR=/tmp/cache \
        -v "$AUTH:/tmp/composer/auth.json:ro" \
        -v "$REPO_ROOT/shopware-html-data:/src" -w /src \
        --entrypoint composer "$cli" "$@"
}

main() {
    case "${1:-}" in
        build) shift; [[ $# -eq 0 ]] || { sw_usage >&2; exit 2; }; build ;;
        ship) shift; [[ $# -le 1 ]] || { sw_usage >&2; exit 2; }; HOST="${1:-$HOST}"; ship ;;
        composer) shift; run_composer "$@" ;;
        --help|-h) sw_usage ;;
        *) sw_usage >&2; exit 2 ;;
    esac
}

main "$@"
