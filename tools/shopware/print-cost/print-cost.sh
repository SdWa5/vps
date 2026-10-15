#!/usr/bin/env bash
#
# Estimate the production cost of 3D-printed merch by slicing it.
#
# Each STL is sliced with OrcaSlicer's own profiles for the Anycubic Kobra 3
# Max (0.4 mm nozzle, 0.20 mm Standard, Anycubic PLA, so 15 % infill and two
# walls), and the G-code's filament weight and print time become a cost per
# piece: filament + electricity + printer wear, plus a failure allowance.
# Labour is not included. The STLs must already be at print scale and in mm;
# sdwa5-3d builds the models, and the scaling is its job.
#
# The defaults are the inputs behind the purchase prices in
# docs/shopware/merch.md, sourced on 2026-10-15: PLA at the top of the
# geizhals.at range for Anycubic PLA Basic, the Kobra 3 Max's 300 W power
# supply as an upper bound for its draw, the top of the Austrian 2026
# household tariffs, and the printer's list price over 3000 hours.
#
# The first run builds the image, which downloads the OrcaSlicer AppImage
# (pinned by sha256).
#
# Usage:
#   tools/shopware/print-cost/print-cost.sh MODEL.stl...
#   tools/shopware/print-cost/print-cost.sh --help
#
# Environment (defaults in brackets):
#   FILAMENT_EUR_KG [26.90]   PRINTER_EUR [999]     PRINTER_HOURS [3000]
#   POWER_W [300]             EUR_KWH [0.34]        FAILURE [0.10]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="sdwa5-print-cost:2.4.2"

die() { printf 'print-cost.sh: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,/^[^#]/{/^#/p}' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
    -h|--help|"") usage; exit 0 ;;
    -*) die "unknown option: $1. Try --help." ;;
esac

# cost GRAMS SECONDS prints the cost per piece in euro, rounded to the cent.
cost() {
    awk -v g="$1" -v s="$2" -v f="${FILAMENT_EUR_KG:-26.90}" -v w="${POWER_W:-300}" \
        -v k="${EUR_KWH:-0.34}" -v p="${PRINTER_EUR:-999}" -v l="${PRINTER_HOURS:-3000}" \
        -v x="${FAILURE:-0.10}" \
        'BEGIN { h = s / 3600; printf "%.2f", (g / 1000 * f + w / 1000 * h * k + p / l * h) * (1 + x) }'
}

# Only the cost formula, for the test suite.
if [[ "${PRINT_COST_ONLY:-}" == 1 ]]; then cost "$1" "$2"; echo; exit 0; fi

DIR=""
NAMES=()
for stl in "$@"; do
    [[ -r "$stl" ]] || die "cannot read $stl"
    d="$(cd "$(dirname "$stl")" && pwd)"
    [[ -z "$DIR" || "$DIR" == "$d" ]] || die "all STLs must sit in one directory"
    DIR="$d"; NAMES+=("$(basename "$stl")")
done

docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -q -t "$IMAGE" "$HERE" >/dev/null
printf '%-24s %9s %9s %9s\n' model grams time euro
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$DIR:/models:ro" "$IMAGE" "${NAMES[@]}" \
    | while read -r name grams seconds; do
        printf '%-24s %9s %6dh%02dm %9s\n' "$name" "$grams" $((seconds / 3600)) $((seconds % 3600 / 60)) \
            "$(cost "$grams" "$seconds")"
    done
