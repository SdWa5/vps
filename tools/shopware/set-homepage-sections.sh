#!/usr/bin/env bash
#
# Mark the homepage sections that the SdWa5Theme styles.
#
# The theme gives the hero image its full-width crop and turns the link tiles
# into a card grid, but it can only find them by a CSS class, and the class and
# the sizing mode live on the CMS sections in the shop's database rather than
# in this repository. This script sets them:
#
#   hero section (position 0)    sizingMode full_width, class sdwa5-hero
#   tiles section (position 2)   class sdwa5-tiles
#
# The section in position 1 already carries sdwa5-hero-text and is left alone.
# Other classes a section carries are kept, so the script adds or removes only
# its own class.
#
# The script is idempotent. Every section is read first and skipped when it is
# already in the wanted state. It writes to production, so it is **dry-run by
# default** and a human starts it.
#
# --revert restores the state before the theme, a boxed hero and neither class.
# Run it before switching back to the Storefront theme, which would otherwise
# show the uncropped 4:3 hero across the full width of the screen. See
# docs/shopware/theme.md for the whole rollback.
#
# Usage:
#   tools/shopware/set-homepage-sections.sh                    show what would change
#   tools/shopware/set-homepage-sections.sh --apply            write it
#   tools/shopware/set-homepage-sections.sh --revert           show what a revert would change
#   tools/shopware/set-homepage-sections.sh --revert --apply   revert it
#   tools/shopware/set-homepage-sections.sh --help
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

set -euo pipefail

APPLY=0
REVERT=0

# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --revert) REVERT=1 ;;
        -h|--help) sw_usage; exit 0 ;;
        *) die "unknown option: ${arg}. Try --help." ;;
    esac
done

# --- targets ---------------------------------------------------------------
#
# Section ids are pinned rather than looked up by position, because a section
# that moved would otherwise receive the other one's class. Read on 2026-10-06
# from the cms page "Homepage", which is the Storefront channel's home page. If
# the page is rebuilt these have to be re-read.

HOME_PAGE="695477e02ef643e5a016b83ed4cdf63a"
HERO_SECTION="935477e02ef643e5a016b83ed4cdf63a"
TILES_SECTION="fe11e555fd554ac69a914c34b0b2093f"

sw_auth

CHANGED=0
SKIPPED=0

# with_class CLASSES NAME prints CLASSES with NAME added once.
# without_class CLASSES NAME prints CLASSES with every NAME removed, or nothing.
with_class() {
    jq -r -n --arg c "$1" --arg n "$2" '($c | split(" ") | map(select(. != ""))) as $l
        | (if ($l | index($n)) then $l else $l + [$n] end) | join(" ")'
}
without_class() {
    jq -r -n --arg c "$1" --arg n "$2" '$c | split(" ") | map(select(. != "" and . != $n)) | join(" ")'
}

# update_section ID LABEL CLASS [SIZING_MODE]
#
# Adds CLASS, or removes it with --revert, and sets SIZING_MODE when one is
# given. A revert sets the sizing mode back to boxed.
update_section() {
    local id="$1" label="$2" class="$3" sizing="${4:-}"
    local row page current_class current_sizing want_class want_sizing payload

    row="$(sw_api GET "/cms-section/$id" | jq -c '.data | objects')"
    [[ -n "$row" ]] || die "section $id ($label) does not exist, re-read the ids"

    page="$(printf '%s' "$row" | jq -r '.pageId // ""')"
    [[ "$page" == "$HOME_PAGE" ]] || die "section $id ($label) belongs to page $page, not to the homepage"

    current_class="$(printf '%s' "$row" | jq -r '.cssClass // ""')"
    current_sizing="$(printf '%s' "$row" | jq -r '.sizingMode // ""')"

    if (( REVERT )); then
        want_class="$(without_class "$current_class" "$class")"
        [[ -n "$sizing" ]] && sizing="boxed"
    else
        want_class="$(with_class "$current_class" "$class")"
    fi
    want_sizing="${sizing:-$current_sizing}"

    if [[ "$want_class" == "$current_class" && "$want_sizing" == "$current_sizing" ]]; then
        sw_skip "$label, already current"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    sw_report "update" "$label: class \"$current_class\" -> \"$want_class\", sizing $current_sizing -> $want_sizing"
    CHANGED=$((CHANGED + 1))
    (( APPLY )) || return 0

    # An empty class is written as null, which is what the administration
    # stores for a section that never had one.
    payload="$(jq -c -n --arg c "$want_class" --arg s "$want_sizing" \
        '{cssClass: (if $c == "" then null else $c end), sizingMode: $s}')"
    sw_write_ok "$(sw_api PATCH "/cms-section/$id" "$payload")" "section $id ($label)"
}

printf 'Shopware at %s\n' "$SW_API_URL"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
(( REVERT )) && printf 'Reverting to the state before the SdWa5Theme.\n'
printf '\n'

update_section "$HERO_SECTION" "hero section" "sdwa5-hero" "full_width"
update_section "$TILES_SECTION" "tiles section" "sdwa5-tiles"

printf '\n%d to change, %d already current.\n' "$CHANGED" "$SKIPPED"

# The storefront caches the rendered homepage, so a changed section shows only
# after the HTTP cache is cleared.
if (( APPLY && CHANGED > 0 )); then
    sw_write_ok "$(sw_api DELETE "/_action/cache")" "cache clear"
    printf 'Cache cleared.\n'
fi
