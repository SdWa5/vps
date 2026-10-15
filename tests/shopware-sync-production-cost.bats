#!/usr/bin/env bats
# Tests for tools/shopware/sync-production-cost.sh

load test_helper

setup() {
    common_setup
    sw_setup
    # Three products: one to copy, one already current, one without a purchase price.
    jq -n '{data: [
        {id: "p-new", productNumber: "EX-NEW", purchasePrices: [{gross: 1.75}],
         translations: [{languageId: "lang-en", customFields: null}, {languageId: "lang-de", customFields: {other: 1}}]},
        {id: "p-done", productNumber: "EX-DONE", purchasePrices: [{gross: 2.77}],
         translations: [{languageId: "lang-en", customFields: {sdwa5_production_cost: 2.77}},
                        {languageId: "lang-de", customFields: {sdwa5_production_cost: 2.77}}]},
        {id: "p-zero", productNumber: "EX-ZERO", purchasePrices: [{gross: 0}],
         translations: [{languageId: "lang-en", customFields: null}]}
      ], total: 3}' > "$STUB_SW_DIR/_api_search_product"
}

sync() {
    run "$REPO_ROOT/tools/shopware/sync-production-cost.sh" "$@"
}

count() {
    grep -c "$1" "$STUB_SW_LOG" || true
}

field_exists() {
    printf '{"data":[{"id":"f1"}],"total":1}' > "$STUB_SW_DIR/_api_search_custom-field"
}

@test "help needs no credentials and names the switch" {
    unset SW_API_URL
    export SHOPWARE_MCP_CONFIG=/nonexistent
    sync --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"sdwa5_production_cost"* ]]
}

@test "an unknown argument is rejected" {
    sync --frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a dry run names the set and the product to change and writes nothing" {
    sync
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"custom field set sdwa5_merch"* ]]
    [[ "$output" == *"EX-NEW production cost 1.75"* ]]
    [[ "$output" == *"2 to change."* ]]
    [ "$(count '^POST /api/custom-field')" -eq 0 ]
    [ "$(count '^PATCH ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}

@test "apply creates the set with the float field on products" {
    sync --apply
    [ "$status" -eq 0 ]
    body="$(grep '^POST /api/custom-field-set ' "$STUB_SW_LOG" | sed 's|^POST /api/custom-field-set ||')"
    [ "$(jq -r '.name' <<<"$body")" = "sdwa5_merch" ]
    [ "$(jq -r '.relations[0].entityName' <<<"$body")" = "product" ]
    [ "$(jq -c '.customFields[0] | [.name, .type]' <<<"$body")" = '["sdwa5_production_cost","float"]' ]
}

@test "an existing set gets only the missing field" {
    printf '{"data":[{"id":"set-live"}],"total":1}' > "$STUB_SW_DIR/_api_search_custom-field-set"
    sync --apply
    [ "$status" -eq 0 ]
    [ "$(count '^POST /api/custom-field-set ')" -eq 0 ]
    body="$(grep '^POST /api/custom-field ' "$STUB_SW_LOG" | sed 's|^POST /api/custom-field ||')"
    [ "$(jq -r '.customFieldSetId' <<<"$body")" = "set-live" ]
}

@test "the purchase price goes into every translation of the product" {
    field_exists
    sync --apply
    [ "$status" -eq 0 ]
    body="$(grep '^PATCH /api/product/p-new ' "$STUB_SW_LOG" | sed 's|^PATCH /api/product/p-new ||')"
    [ "$(jq -c '.translations | map_values(.customFields.sdwa5_production_cost)' <<<"$body")" = '{"lang-en":1.75,"lang-de":1.75}' ]
    [ "$(count '^DELETE /api/_action/cache')" -eq 1 ]
}

@test "a current product and one without a purchase price are left alone" {
    field_exists
    sync --apply
    [[ "$output" == *"EX-DONE already current (2.77)"* ]]
    [[ "$output" == *"EX-ZERO has no purchase price"* ]]
    [ "$(count '^PATCH /api/product/p-done')" -eq 0 ]
    [ "$(count '^PATCH /api/product/p-zero')" -eq 0 ]
    [[ "$output" == *"1 changed."* ]]
}

@test "nothing to do writes nothing and keeps the cache" {
    field_exists
    jq '.data |= [.[1]]' "$STUB_SW_DIR/_api_search_product" > "$STUB_SW_DIR/p" && mv "$STUB_SW_DIR/p" "$STUB_SW_DIR/_api_search_product"
    sync --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 changed."* ]]
    [ "$(count '^PATCH ')" -eq 0 ]
    [ "$(count '^DELETE ')" -eq 0 ]
}
