#!/usr/bin/env bash
#
# Turn product photos into shop images: a transparent cutout and 2000 x 2000
# white, light and dark studio variants of each, through shopimg.py in Docker.
#
# A jobs file names the photos and how to treat each. It is a POSIX shell
# fragment that calls `shot PHOTO NAME [shopimg.py options]` once per output,
# where PHOTO is relative to IN_DIR. print-models.jobs is the worked example
# and documents the options. Read the corners for --patch and --quad off the
# grid zooms that the corners subcommand prints.
#
# Nothing is written outside OUT_DIR and the model cache. The first run builds
# the image and downloads the BiRefNet model (ca. 930 MB) into the cache.
#
# Usage:
#   tools/shopware/images/shop-images.sh run JOBS IN_DIR OUT_DIR
#   tools/shopware/images/shop-images.sh corners PHOTO OUT.jpg "x,y x,y ..." [RADIUS [FACTOR]]
#   tools/shopware/images/shop-images.sh --help
#
# Environment:
#   SHOP_IMAGES_CACHE   model cache, default ${XDG_CACHE_HOME:-~/.cache}/sdwa5-rembg

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="sdwa5-shop-images:2.0.84"
CACHE="${SHOP_IMAGES_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/sdwa5-rembg}"

die() { printf 'shop-images.sh: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,/^[^#]/{/^#/p}' "$0" | sed 's/^# \{0,1\}//'; }

ensure_image() {
    docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -q -t "$IMAGE" "$HERE" >/dev/null
}

# Directories are created here as the user, because a path Docker creates for a
# bind mount belongs to root.
in_docker() {
    mkdir -p "$CACHE"
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$CACHE:/models" -v "$HERE:/tool:ro" "$@"
}

case "${1:-}" in
    -h|--help|"") usage; exit 0 ;;
    run)
        [[ $# -eq 4 ]] || die "run needs JOBS IN_DIR OUT_DIR"
        jobs="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
        [[ -r "$jobs" ]] || die "cannot read $2"
        [[ -d "$3" ]] || die "no directory $3"
        mkdir -p "$4"
        ensure_image
        # shellcheck disable=SC2016 # expanded by the container shell, not here
        in_docker -v "$jobs:/jobs.sh:ro" -v "$(cd "$3" && pwd):/in:ro" -v "$(cd "$4" && pwd):/out" \
            "$IMAGE" sh -ec 'shot() { f="$1"; shift; python -I /tool/shopimg.py "/in/$f" /out "$@"; }; . /jobs.sh'
        ;;
    corners)
        [[ $# -ge 4 ]] || die "corners needs PHOTO OUT.jpg POINTS"
        [[ -r "$2" ]] || die "cannot read $2"
        out_dir="$(dirname "$3")"; mkdir -p "$out_dir"
        ensure_image
        in_docker -v "$(cd "$(dirname "$2")" && pwd):/in:ro" -v "$(cd "$out_dir" && pwd):/out" \
            "$IMAGE" python -I /tool/corners.py "/in/$(basename "$2")" "/out/$(basename "$3")" "${@:4}"
        ;;
    *) die "unknown command: $1. Try --help." ;;
esac
