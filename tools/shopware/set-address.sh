#!/usr/bin/env bash
#
# Roll the organisation's postal address through the live Shopware shop.
#
# Four places hold it and none of them is in this repository: the Impressum and
# Datenschutz CMS pages, the AGB page, and `core.basicInformation.address`.
# The document templates hold the sender block that invoices carry.
#
# The script is idempotent. Every target is read first and skipped when it
# already carries the new value, so a second run is a no-op and a half-finished
# run can simply be repeated.
#
# It writes to production, so it is **dry-run by default** and a human starts
# it. Claude Code's auto-mode classifier blocks production mutations, which is
# the same reason the Dolibarr client next door reads only.
#
# What it deliberately does NOT touch: the place of jurisdiction in the AGB and
# in the document templates. That follows the **Sitz**, not the postal address,
# and the Sitz is still Ostermiething until the Statutenaenderung is registered.
# See the parent repo's docs/organization.md.
#
# Usage:
#   tools/shopware/set-address.sh              show what would change
#   tools/shopware/set-address.sh --apply      write it
#   tools/shopware/set-address.sh --help
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

set -euo pipefail

OLD_STREET="Mühlenstraße 24"
OLD_CITY="5121 Ostermiething"
NEW_STREET="Egitlweg 6"
NEW_CITY="5322 Hof bei Salzburg"
NEW_COMPANY="Musikverein Schmeiß die Wand an 5"

APPLY=0

# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${1:-}" in
    --apply) APPLY=1 ;;
    -h|--help) sw_usage; exit 0 ;;
    "") ;;
    *) die "unknown option: ${1}. Try --help." ;;
esac

sw_auth

CHANGED=0
SKIPPED=0

# --- 1. CMS text slots -----------------------------------------------------
#
# A slot's config is a single JSON column, so a partial write would drop every
# other key in it. The whole config is read, the content string replaced, and
# the whole config written back under the slot's own language.

update_slot() {
    local slot_id="$1" language_id="$2" label="$3"
    local current new_content config

    config="$(sw_api POST "/search/cms-slot-translation" \
        "{\"limit\":1,\"filter\":[{\"type\":\"equals\",\"field\":\"cmsSlotId\",\"value\":\"$slot_id\"},{\"type\":\"equals\",\"field\":\"languageId\",\"value\":\"$language_id\"}]}" \
        | jq -c '.data[0].config // empty')"
    [[ -n "$config" ]] || die "no translation for slot $slot_id in language $language_id"

    current="$(printf '%s' "$config" | jq -r '.content.value // ""')"

    if [[ "$current" != *"$OLD_STREET"* && "$current" != *"$OLD_CITY"* ]]; then
        sw_skip "$label, already current"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    new_content="${current//$OLD_STREET/$NEW_STREET}"
    new_content="${new_content//$OLD_CITY/$NEW_CITY}"

    sw_report "update" "$label"
    CHANGED=$((CHANGED + 1))
    (( APPLY )) || return 0

    local payload
    payload="$(jq -c -n --argjson cfg "$config" --arg v "$new_content" \
        '{config: ($cfg | .content.value = $v)}')"
    sw_write_ok "$(sw_api PATCH "/cms-slot/$slot_id" "$payload" "sw-language-id: $language_id")" "slot $slot_id"
}

# --- 2. the shop's own address ---------------------------------------------
#
# Written as the entity rather than through /_action/system-config, which
# answered 204 and changed nothing. The value stays a bare string; a row
# wrapped as {"_value": ...} is corruption and renders as "Array".

update_basic_address() {
    local want="$NEW_STREET<br>$NEW_CITY<br>Österreich"
    local row id current

    row="$(sw_api POST "/search/system-config" \
        '{"limit":1,"filter":[{"type":"equals","field":"configurationKey","value":"core.basicInformation.address"}]}' \
        | jq -c '.data[0] // empty')"
    [[ -n "$row" ]] || die "core.basicInformation.address does not exist"

    id="$(printf '%s' "$row" | jq -r '.id')"
    current="$(printf '%s' "$row" | jq -r '.configurationValue | if type == "object" then (._value // tostring) else tostring end')"

    if [[ "$current" == "$want" ]]; then
        sw_skip "core.basicInformation.address, already current"
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    sw_report "update" "core.basicInformation.address"
    CHANGED=$((CHANGED + 1))
    (( APPLY )) || return 0

    sw_write_ok "$(sw_api PATCH "/system-config/$id" "$(jq -c -n --arg v "$want" '{configurationValue: $v}')")" \
        "core.basicInformation.address"
}

# --- 3. document sender block ----------------------------------------------
#
# All four templates ship Shopware's stock `companyName: "Example Company"` and
# an empty address. No order and no document exists yet, so nothing wrong has
# been printed, but the first invoice would carry it.

update_documents() {
    local rows
    rows="$(sw_api POST "/search/document-base-config" '{"limit":50}' | jq -c '.data[]')"
    [[ -n "$rows" ]] || die "no document base configs found"

    local row id name config want_addr
    want_addr="$NEW_STREET, $NEW_CITY, Österreich"

    while IFS= read -r row; do
        id="$(printf '%s' "$row" | jq -r '.id')"
        name="$(printf '%s' "$row" | jq -r '.name')"
        config="$(printf '%s' "$row" | jq -c '.config')"

        if [[ "$(printf '%s' "$config" | jq -r '.companyName // ""')" == "$NEW_COMPANY" \
           && "$(printf '%s' "$config" | jq -r '.companyAddress // ""')" == "$want_addr" ]]; then
            sw_skip "document $name, already current"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        sw_report "update" "document $name, company name and address"
        CHANGED=$((CHANGED + 1))
        (( APPLY )) || continue

        local payload
        payload="$(jq -c -n --argjson cfg "$config" --arg n "$NEW_COMPANY" --arg a "$want_addr" \
            '{config: ($cfg | .companyName = $n | .companyAddress = $a)}')"
        sw_write_ok "$(sw_api PATCH "/document-base-config/$id" "$payload")" "document base config $name"
    done <<< "$rows"
}

# --- targets ---------------------------------------------------------------
#
# Slot and language ids are pinned rather than searched, because a substring
# sweep over every CMS slot in the shop is not something to point at production.
# Read on 2026-09-14; if a page is rebuilt these have to be re-read.

EN_LANG="2fbb5fe2e29a4d70aa5854ce7ce3e20b"
DE_LANG="019c36d736207216a1f1d943de40f765"

printf 'Shopware at %s\n' "$SW_API_URL"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

update_slot "c75f2dbf219844f78ee363fd43d56ef3" "$EN_LANG" "Impressum page"
update_slot "02bbb49aaa0145e8b1276b2c90404d30" "$EN_LANG" "Datenschutz page"
update_slot "9115152f846b4593a95b8fb6da7c2003" "$DE_LANG" "AGB page, German"
update_basic_address
update_documents

printf '\n%d to change, %d already current.\n' "$CHANGED" "$SKIPPED"
if (( APPLY && CHANGED > 0 )); then
    printf 'Clear the HTTP cache so the storefront shows it:\n'
    printf '  docker exec shopware bin/console cache:pool:clear cache.http\n'
fi
