#!/usr/bin/env bash
#
# Replace text in CMS text slots of the live Shopware shop, from a JSON file.
#
# Each edit names a slot id, a language, the exact old text and the new text.
# The old text has to occur exactly once in that slot's content, so an edit
# never lands in the wrong table row. An edit whose old text is gone and whose
# new text is present counts as already done, so a second run is a no-op.
#
# Every edit is checked before anything is written. A typo in the last edit
# therefore leaves the shop untouched rather than half-edited. Several edits
# to one slot are applied in file order and written in one request, and the
# HTTP cache is cleared after a run that changed something.
#
# It writes to production, so it is **dry-run by default**. Claude Code's
# auto-mode classifier blocks production mutations unless the owner allows them.
#
# Usage:
#   tools/shopware/edit-slots.sh EDITS.json              show what would change
#   tools/shopware/edit-slots.sh EDITS.json --apply      write it
#   tools/shopware/edit-slots.sh --help
#
# EDITS.json holds an optional `languages` map from a short name to a language
# id, and an `edits` array of {label, slot, lang, old, new}. `lang` is a short
# name from the map or a language id. Slot ids are read from the admin or with
# a search on cms-slot-translation. tools/shopware/slot-edits/ holds the edits
# that were run, as worked examples.
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

set -euo pipefail

# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Shopware's live version of every versioned entity. Drafts of a CMS page live
# in other versions and are not touched.
LIVE_VERSION="0fa91ce3e96a4bc2be4bd9ce752c3425"

APPLY=0
EDITS=""
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help) sw_usage; exit 0 ;;
        -*) die "unknown option: ${arg}. Try --help." ;;
        *) [[ -z "$EDITS" ]] || die "only one edits file, got $EDITS and $arg"; EDITS="$arg" ;;
    esac
done
[[ -n "$EDITS" ]] || die "no edits file. Try --help."
[[ -r "$EDITS" ]] || die "cannot read $EDITS"
jq -e '.edits | type == "array" and length > 0' "$EDITS" >/dev/null 2>&1 || die "$EDITS has no edits"
jq -e '.edits | all(has("slot") and has("lang") and (.old | type == "string" and length > 0) and (.new | type == "string"))' \
    "$EDITS" >/dev/null || die "every edit needs slot, lang, a non-empty old and a new text"

# The edits with `lang` resolved to an id and the label defaulted.
RESOLVED="$(jq -c '(.languages // {}) as $l
    | [.edits[] | .lang = ($l[.lang] // .lang) | .label = (.label // "\(.slot) \(.lang)")]' "$EDITS")"

sw_auth
printf 'Shopware at %s\n' "$SW_API_URL"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

# One search fetches every slot translation the file touches.
ROWS="$(sw_api POST /search/cms-slot-translation "$(jq -c --arg v "$LIVE_VERSION" '{
    limit: 500,
    filter: [{type: "equalsAny", field: "cmsSlotId", value: (map(.slot) | unique)},
             {type: "equals", field: "cmsSlotVersionId", value: $v}],
    includes: {cms_slot_translation: ["cmsSlotId", "languageId", "config"]}}' <<<"$RESOLVED")")"
jq -e '.data | type == "array"' <<<"$ROWS" >/dev/null 2>&1 || die "slot search failed: $ROWS"

# Pass 1 builds one write per slot and language, and dies on the first edit
# that does not fit. Nothing has been written at that point.
WRITES="[]"
CHANGED=0
SKIPPED=0
while IFS= read -r key; do
    slot="${key% *}"; lang="${key#* }"
    config="$(jq -c --arg s "$slot" --arg l "$lang" \
        'first(.data[] | select(.cmsSlotId == $s and .languageId == $l) | .config) // empty' <<<"$ROWS")"
    [[ -n "$config" ]] || die "slot $slot has no translation in language $lang"
    jq -e '.content.value | type == "string"' <<<"$config" >/dev/null 2>&1 || die "slot $slot is not a text slot"

    value="$(jq -c '.content.value' <<<"$config")"
    touched=0
    while IFS= read -r edit; do
        label="$(jq -r .label <<<"$edit")"
        hits="$(jq -n --argjson v "$value" --argjson e "$edit" '$v | split($e.old) | length - 1')"
        if [[ "$hits" == 0 ]] && jq -en --argjson v "$value" --argjson e "$edit" '$v | contains($e.new)' >/dev/null; then
            sw_skip "$label, already current"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        [[ "$hits" == 1 ]] || die "$label: old text found $hits times in slot $slot, expected once"
        value="$(jq -cn --argjson v "$value" --argjson e "$edit" '$v | split($e.old) | join($e.new)')"
        sw_report update "$label"
        CHANGED=$((CHANGED + 1))
        touched=1
    done < <(jq -c --arg s "$slot" --arg l "$lang" '.[] | select(.slot == $s and .lang == $l)' <<<"$RESOLVED")

    if (( touched )); then
        WRITES="$(jq -c --arg s "$slot" --arg l "$lang" --argjson c "$config" --argjson v "$value" \
            '. + [{slot: $s, lang: $l, body: {config: ($c | .content.value = $v)}}]' <<<"$WRITES")"
    fi
done < <(jq -r '[.[] | "\(.slot) \(.lang)"] | reduce .[] as $k ([]; if index([$k]) then . else . + [$k] end) | .[]' <<<"$RESOLVED")

# Pass 2 writes, under each translation's own language, so a partial write
# cannot drop the other keys of the config column.
if (( APPLY && CHANGED > 0 )); then
    while IFS= read -r write; do
        slot="$(jq -r .slot <<<"$write")"
        lang="$(jq -r .lang <<<"$write")"
        sw_write_ok "$(sw_api PATCH "/cms-slot/$slot" "$(jq -c .body <<<"$write")" "sw-language-id: $lang")" \
            "slot $slot in language $lang"
    done < <(jq -c '.[]' <<<"$WRITES")
    sw_write_ok "$(sw_api DELETE /_action/cache)" "cache clear"
fi

printf '\n%d %s, %d already current.\n' "$CHANGED" "$( (( APPLY )) && echo changed || echo to change)" "$SKIPPED"
