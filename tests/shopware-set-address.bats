#!/usr/bin/env bats
# Tests for tools/shopware/set-address.sh

load test_helper

setup() {
    common_setup
    sw_setup
}

@test "help needs no credentials and names the apply switch" {
    unset SW_API_URL
    export SHOPWARE_MCP_CONFIG="$BATS_TEST_TMPDIR/does-not-exist.json"
    set_address --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
}

@test "an unknown option is rejected" {
    set_address --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "missing credentials fail with an instruction rather than a stack trace" {
    unset SW_API_URL SW_API_CLIENT_ID SW_API_CLIENT_SECRET
    export SHOPWARE_MCP_CONFIG="$BATS_TEST_TMPDIR/does-not-exist.json"
    set_address
    [ "$status" -eq 1 ]
    [[ "$output" == *"no credentials"* ]]
}

# The whole reason the script defaults to a dry run.
@test "a dry run writes nothing" {
    set_address
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
}

@test "a dry run names every target it would change" {
    set_address
    [ "$status" -eq 0 ]
    [[ "$output" == *"Impressum page"* ]]
    [[ "$output" == *"Datenschutz page"* ]]
    [[ "$output" == *"AGB page, German"* ]]
    [[ "$output" == *"core.basicInformation.address"* ]]
    [[ "$output" == *"document invoice"* ]]
    [[ "$output" == *"5 to change, 0 already current"* ]]
}

@test "apply patches every target" {
    set_address --apply
    [ "$status" -eq 0 ]
    [ "$(sw_patch_count)" -eq 5 ]
    run sw_requests
    [[ "$output" == *"PATCH /api/system-config/cfg1"* ]]
    [[ "$output" == *"PATCH /api/document-base-config/doc1"* ]]
}

@test "the new address is what gets written, and the old one is gone" {
    set_address --apply
    run sw_requests
    [[ "$output" == *"Egitlweg 6"* ]]
    [[ "$output" == *"5322 Hof bei Salzburg"* ]]
    [[ "$output" != *"Mühlenstraße 24"* ]]
    [[ "$output" != *"5121 Ostermiething"* ]]
}

# A slot's config is one JSON column, so a partial write would drop the rest of
# it. This is the test that would have caught that.
@test "a slot write carries the whole config, not just the changed string" {
    set_address --apply
    run sw_requests
    [[ "$output" == *"verticalAlign"* ]]
    [[ "$output" == *'"source":"static"'* ]]
}

@test "a document write keeps the other template settings" {
    set_address --apply
    run sw_requests
    [[ "$output" == *'"pageSize":"a4"'* ]]
}

@test "the company name replaces Shopware's stock Example Company" {
    set_address --apply
    run sw_requests
    [[ "$output" == *"Musikverein Schmei"* ]]
    [[ "$output" != *"Example Company"* ]]
}

# Idempotence: a second run, or a repeat of a half-finished one, is a no-op.
@test "targets that already carry the new address are skipped" {
    sw_fixture_slot "Musikverein, Egitlweg 6, 5322 Hof bei Salzburg, Österreich"
    sw_fixture_system_config "Egitlweg 6<br>5322 Hof bei Salzburg<br>Österreich"
    sw_fixture_documents "Musikverein Schmeiß die Wand an 5" "Egitlweg 6, 5322 Hof bei Salzburg, Österreich"
    set_address
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to change, 5 already current"* ]]
}

@test "an already current shop needs no write at all" {
    sw_fixture_slot "Musikverein, Egitlweg 6, 5322 Hof bei Salzburg, Österreich"
    sw_fixture_system_config "Egitlweg 6<br>5322 Hof bei Salzburg<br>Österreich"
    sw_fixture_documents "Musikverein Schmeiß die Wand an 5" "Egitlweg 6, 5322 Hof bei Salzburg, Österreich"
    set_address --apply
    [ "$status" -eq 0 ]
    [ "$(sw_patch_count)" -eq 0 ]
}

# The place of jurisdiction follows the Sitz, which has not moved yet.
@test "Ostermiething as the place of jurisdiction is left alone" {
    sw_fixture_slot "Gerichtsstand ist Ostermiething, Österreich. Anschrift: Mühlenstraße 24, 5121 Ostermiething."
    set_address --apply
    run sw_requests
    [[ "$output" == *"Gerichtsstand ist Ostermiething"* ]]
    [[ "$output" == *"Egitlweg 6, 5322 Hof bei Salzburg"* ]]
}

@test "a missing system config row fails loudly instead of silently doing nothing" {
    printf '{"data":[],"total":0}' > "$STUB_SW_DIR/_api_search_system-config"
    set_address
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "a refused token stops the script before it touches anything" {
    export STUB_SW_NO_TOKEN=1
    set_address --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not obtain an access token"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
}
