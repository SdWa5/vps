#!/usr/bin/env bash
#
# Replace text in CMS text slots and mail templates of the live Shopware shop,
# from a JSON file.
#
# Each edit names a slot id, a language, the exact old text and the new text.
# The old text has to occur exactly once in that slot's content, so an edit
# never lands in the wrong table row. An edit with "target": "mail-template"
# names a mail template id in `template` and the field it changes in `field`,
# contentHtml, contentPlain, subject or senderName, instead of a slot. An edit whose old text is gone and whose
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
# id, and an `edits` array of {label, slot, lang, old, new}, or of {label,
# target: "mail-template", template, field, lang, old, new}. `lang` is a short
# name from the map or a language id. Slot ids are read from the admin or with
# a search on cms-slot-translation, mail template ids with one on
# mail-template-translation. tools/shopware/slot-edits/ holds the edits that
# were run, as worked examples.
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
jq -e '.edits | all(has("lang") and (.old | type == "string" and length > 0) and (.new | type == "string"))' \
    "$EDITS" >/dev/null || die "every edit needs slot, lang, a non-empty old and a new text"
jq -e '.edits | all((.target // "cms-slot") as $t
        | if $t == "cms-slot" then has("slot")
          elif $t == "mail-template" then has("template") and (.field == "contentHtml" or .field == "contentPlain" or .field == "subject" or .field == "senderName")
          else false end)' "$EDITS" >/dev/null \
    || die "every edit needs a slot, or target mail-template with a template and field contentHtml, contentPlain, subject or senderName"

# The edits with `lang` resolved to an id, the target and label defaulted, and
# the entity id and the field named the same way for both targets.
RESOLVED="$(jq -c '(.languages // {}) as $l
    | [.edits[] | .lang = ($l[.lang] // .lang) | .target = (.target // "cms-slot")
        | .id = (.slot // .template) | .field = (if .target == "cms-slot" then "content" else .field end)
        | .label = (.label // "\(.id) \(.lang)")]' "$EDITS")"

sw_auth
printf 'Shopware at %s\n' "$SW_API_URL"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

# One search per target fetches every translation the file touches, as rows of
# {target, id, lang, values: {field: text}} plus the slot config to write back.
ROWS="[]"
if jq -e 'any(.target == "cms-slot")' <<<"$RESOLVED" >/dev/null; then
    found="$(sw_api POST /search/cms-slot-translation "$(jq -c --arg v "$LIVE_VERSION" '{
        limit: 500,
        filter: [{type: "equalsAny", field: "cmsSlotId", value: ([.[] | select(.target == "cms-slot") | .id] | unique)},
                 {type: "equals", field: "cmsSlotVersionId", value: $v}],
        includes: {cms_slot_translation: ["cmsSlotId", "languageId", "config"]}}' <<<"$RESOLVED")")"
    jq -e '.data | type == "array"' <<<"$found" >/dev/null 2>&1 || die "slot search failed: $found"
    ROWS="$(jq -c --argjson f "$found" '. + [$f.data[] | {target: "cms-slot", id: .cmsSlotId, lang: .languageId,
        config, values: {content: .config.content.value}}]' <<<"$ROWS")"
fi
if jq -e 'any(.target == "mail-template")' <<<"$RESOLVED" >/dev/null; then
    found="$(sw_api POST /search/mail-template-translation "$(jq -c '{
        limit: 500,
        filter: [{type: "equalsAny", field: "mailTemplateId", value: ([.[] | select(.target == "mail-template") | .id] | unique)}],
        includes: {mail_template_translation: ["mailTemplateId", "languageId", "contentHtml", "contentPlain", "subject", "senderName"]}}' <<<"$RESOLVED")")"
    jq -e '.data | type == "array"' <<<"$found" >/dev/null 2>&1 || die "mail template search failed: $found"
    ROWS="$(jq -c --argjson f "$found" '. + [$f.data[] | {target: "mail-template", id: .mailTemplateId, lang: .languageId,
        values: {contentHtml: (.contentHtml // ""), contentPlain: (.contentPlain // ""),
                 subject: (.subject // ""), senderName: (.senderName // "")}}]' <<<"$ROWS")"
fi

# Pass 1 builds one write per entity and language, and dies on the first edit
# that does not fit. Nothing has been written at that point.
WRITES="[]"
CHANGED=0
SKIPPED=0
while IFS= read -r key; do
    read -r target id lang <<<"$key"
    noun="$( [[ "$target" == cms-slot ]] && echo slot || echo "mail template")"
    row="$(jq -c --arg t "$target" --arg i "$id" --arg l "$lang" \
        'first(.[] | select(.target == $t and .id == $i and .lang == $l)) // empty' <<<"$ROWS")"
    [[ -n "$row" ]] || die "$noun $id has no translation in language $lang"
    if [[ "$target" == cms-slot ]]; then
        jq -e '.values.content | type == "string"' <<<"$row" >/dev/null 2>&1 || die "slot $id is not a text slot"
    fi

    values="$(jq -c .values <<<"$row")"
    touched=0
    while IFS= read -r edit; do
        label="$(jq -r .label <<<"$edit")"
        field="$(jq -r .field <<<"$edit")"
        value="$(jq -c --arg f "$field" '.[$f]' <<<"$values")"
        hits="$(jq -n --argjson v "$value" --argjson e "$edit" '$v | split($e.old) | length - 1')"
        # An edit is in place when the new text is there and the old one is gone,
        # or, for an insertion whose new text keeps the old one, simply there.
        if jq -en --argjson v "$value" --argjson e "$edit" --argjson h "$hits" \
                '($v | contains($e.new)) and ($h == 0 or ($e.new | contains($e.old)))' >/dev/null; then
            sw_skip "$label, already current"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        [[ "$hits" == 1 ]] || die "$label: old text found $hits times in $noun $id, expected once"
        values="$(jq -c --arg f "$field" --argjson e "$edit" '.[$f] |= (split($e.old) | join($e.new))' <<<"$values")"
        sw_report update "$label"
        CHANGED=$((CHANGED + 1))
        touched=1
    done < <(jq -c --arg t "$target" --arg i "$id" --arg l "$lang" \
        '.[] | select(.target == $t and .id == $i and .lang == $l)' <<<"$RESOLVED")

    if (( touched )); then
        WRITES="$(jq -c --arg t "$target" --arg i "$id" --arg l "$lang" --argjson r "$row" --argjson v "$values" \
            '. + [{target: $t, id: $i, lang: $l,
                   body: (if $t == "cms-slot" then {config: ($r.config | .content.value = $v.content)} else $v end)}]' <<<"$WRITES")"
    fi
done < <(jq -r '[.[] | "\(.target) \(.id) \(.lang)"] | reduce .[] as $k ([]; if index([$k]) then . else . + [$k] end) | .[]' <<<"$RESOLVED")

# Pass 2 writes, under each translation's own language, so a partial write
# cannot drop the other keys of the config column.
if (( APPLY && CHANGED > 0 )); then
    while IFS= read -r write; do
        target="$(jq -r .target <<<"$write")"
        id="$(jq -r .id <<<"$write")"
        lang="$(jq -r .lang <<<"$write")"
        sw_write_ok "$(sw_api PATCH "/$target/$id" "$(jq -c .body <<<"$write")" "sw-language-id: $lang")" \
            "$target $id in language $lang"
    done < <(jq -c '.[]' <<<"$WRITES")
    sw_write_ok "$(sw_api DELETE /_action/cache)" "cache clear"
fi

printf '\n%d %s, %d already current.\n' "$CHANGED" "$( (( APPLY )) && echo changed || echo to change)" "$SKIPPED"
