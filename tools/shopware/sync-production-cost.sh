#!/usr/bin/env bash
#
# Copy every product's purchase price into the custom field the storefront
# shows as the production cost, in the live Shopware shop.
#
# The storefront cannot read purchase prices, because the Store API leaves them
# out, so the SdWa5Theme reads the custom field sdwa5_production_cost instead,
# see docs/shopware/theme.md. The purchase price in the admin stays the only
# source. This script creates the custom field set sdwa5_merch with that field
# if it is missing, then writes the purchase price into every translation the
# product has. A purchase price of 0 counts as unknown and is not copied, so the
# storefront leaves the cost line out.
#
# The script is idempotent. A product whose field already holds its purchase
# price in every translation is skipped.
#
# It writes to production, so it is **dry-run by default**. Claude Code's
# auto-mode classifier blocks production mutations unless the owner allows them.
#
# Usage:
#   tools/shopware/sync-production-cost.sh              show what would change
#   tools/shopware/sync-production-cost.sh --apply      write it
#   tools/shopware/sync-production-cost.sh --help
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

set -euo pipefail

# shellcheck source=tools/shopware/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Fixed ids, so a second shop or a rerun creates the same entities.
SET_ID="bc61d4d4ae214bf198162684c0bceaf7"
RELATION_ID="89563b810bdf4066abbae1310f4e7f9f"
FIELD_ID="4f450586c6bd491191e479c7a603e13c"
FIELD="sdwa5_production_cost"

APPLY=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        -h|--help) sw_usage; exit 0 ;;
        *) die "unknown argument: ${arg}. Try --help." ;;
    esac
done

sw_auth
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'

CHANGED=0

# The field, and its set when that is missing too.
if [[ "$(sw_api POST /search/custom-field "$(jq -cn --arg n "$FIELD" \
        '{limit:1,filter:[{type:"equals",field:"name",value:$n}]}')" | jq -r '.total // 0')" == 0 ]]; then
    field="$(jq -cn --arg i "$FIELD_ID" --arg n "$FIELD" '{id:$i, name:$n, type:"float", config:{
        label:{"en-GB":"Production cost (estimate)","de-DE":"Herstellungskosten (geschätzt)"},
        helpText:{"en-GB":"Copied from the purchase price by tools/shopware/sync-production-cost.sh",
                  "de-DE":"Wird von tools/shopware/sync-production-cost.sh aus dem Einkaufspreis kopiert"},
        customFieldType:"number", numberType:"float", customFieldPosition:1}}')"
    set_id="$(sw_api POST /search/custom-field-set "$(jq -cn \
        '{limit:1,filter:[{type:"equals",field:"name",value:"sdwa5_merch"}]}')" | jq -r '.data[0].id // empty')"
    if [[ -z "$set_id" ]]; then
        sw_report create "custom field set sdwa5_merch with $FIELD"
        if (( APPLY )); then
            sw_write_ok "$(sw_api POST /custom-field-set "$(jq -cn --arg s "$SET_ID" --arg r "$RELATION_ID" --argjson f "$field" \
                '{id:$s, name:"sdwa5_merch", active:true,
                  config:{label:{"en-GB":"SdWa5 merch","de-DE":"SdWa5 Merch"}},
                  relations:[{id:$r, entityName:"product"}], customFields:[$f]}')")" "custom field set"
        fi
    else
        sw_report create "custom field $FIELD"
        if (( APPLY )); then
            sw_write_ok "$(sw_api POST /custom-field "$(jq -c --arg s "$set_id" '. + {customFieldSetId:$s}' <<<"$field")")" \
                "custom field"
        fi
    fi
    CHANGED=$((CHANGED + 1))
fi

PRODUCTS="$(sw_api POST /search/product '{"limit":500,"associations":{"translations":{}},
    "includes":{"product":["id","productNumber","purchasePrices","translations"],
                "product_translation":["languageId","customFields"]}}')"
jq -e '.data | type == "array"' <<<"$PRODUCTS" >/dev/null 2>&1 || die "product search failed: $PRODUCTS"

while IFS= read -r p; do
    number="$(jq -r .productNumber <<<"$p")"
    cost="$(jq -r '.purchasePrices[0].gross // 0' <<<"$p")"
    if jq -en --argjson c "$cost" '$c == 0' >/dev/null; then
        sw_skip "$number has no purchase price"; continue
    fi
    if jq -e --arg f "$FIELD" --argjson c "$cost" \
            'all(.translations[]; (.customFields // {})[$f] == $c)' <<<"$p" >/dev/null; then
        sw_skip "$number already current ($cost)"; continue
    fi
    sw_report update "$number production cost $cost"
    CHANGED=$((CHANGED + 1))
    if (( APPLY )); then
        # customFields is a JSON column that Shopware merges, so other keys stay.
        sw_write_ok "$(sw_api PATCH "/product/$(jq -r .id <<<"$p")" "$(jq -c --arg f "$FIELD" --argjson c "$cost" \
            '{translations: (reduce .translations[] as $t ({}; .[$t.languageId] = {customFields: {($f): $c}}))}' <<<"$p")")" \
            "product $number"
    fi
done < <(jq -c '.data[]' <<<"$PRODUCTS")

if (( APPLY && CHANGED > 0 )); then
    sw_write_ok "$(sw_api DELETE /_action/cache)" "cache clear"
fi
printf '%d %s.\n' "$CHANGED" "$( (( APPLY )) && echo changed || echo to change)"
