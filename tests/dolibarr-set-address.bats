#!/usr/bin/env bats
# Tests for tools/dolibarr/set-address.sh

load test_helper

setup() {
    common_setup
    doli_address_setup
}

@test "help works without a key file" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    doli_set_address --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
}

@test "an unknown option is rejected" {
    doli_set_address --frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a missing key file explains itself" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    doli_set_address
    [ "$status" -eq 1 ]
    [[ "$output" == *"no API key at"* ]]
}

@test "a dry run writes nothing" {
    doli_set_address
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [ "$(doli_put_count)" -eq 0 ]
}

@test "a dry run names all three records and the manual company step" {
    doli_set_address
    [ "$status" -eq 0 ]
    [[ "$output" == *"member Ada Example"* ]]
    [[ "$output" == *"user Ada Example"* ]]
    [[ "$output" == *"thirdparty Example Supplies"* ]]
    [[ "$output" == *"3 to change, 0 already current"* ]]
    [[ "$output" == *"Home, Setup, Company/Organization"* ]]
}

@test "apply writes all three records" {
    doli_set_address --apply
    [ "$status" -eq 0 ]
    [ "$(doli_put_count)" -eq 3 ]
    run doli_requests
    [[ "$output" == *"PUT members/2"* ]]
    [[ "$output" == *"PUT users/2"* ]]
    [[ "$output" == *"PUT thirdparties/10"* ]]
}

@test "the new address is what gets written" {
    doli_set_address --apply
    run doli_requests
    [[ "$output" == *"Egitlweg 6"* ]]
    [[ "$output" == *"Hof bei Salzburg"* ]]
    [[ "$output" != *"Ostermiething"* ]]
}

# The thirdparty's street and postcode were already right. Rewriting them would
# be noise, and a wrong street in the payload would be a real defect.
@test "the thirdparty gets only its town corrected" {
    doli_set_address --apply
    run doli_requests
    line="$(printf '%s\n' "$output" | grep '^PUT thirdparties/10')"
    [[ "$line" == *"Hof bei Salzburg"* ]]
    [[ "$line" != *"Egitlweg"* ]]
    [[ "$line" != *"5322"* ]]
}

@test "a person record gets street, postcode and town together" {
    doli_set_address --apply
    run doli_requests
    line="$(printf '%s\n' "$output" | grep '^PUT members/2')"
    [[ "$line" == *"Egitlweg 6"* ]]
    [[ "$line" == *"5322"* ]]
    [[ "$line" == *"Hof bei Salzburg"* ]]
}

@test "records that already carry the new address are skipped" {
    doli_fixture members_2 "$(jq -n '{id:"2",lastname:"Example",address:"Egitlweg 6",zip:"5322",town:"Hof bei Salzburg"}')"
    doli_fixture users_2   "$(jq -n '{id:"2",lastname:"Example",address:"Egitlweg 6",zip:"5322",town:"Hof bei Salzburg"}')"
    doli_fixture thirdparties_10 "$(jq -n '{id:"10",name:"Example Supplies",address:"Egitlweg 6",zip:"5322",town:"Hof bei Salzburg"}')"
    doli_set_address --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to change, 3 already current"* ]]
    [ "$(doli_put_count)" -eq 0 ]
}

# A pinned id alone would rewrite whoever sits at that id after a merge or a
# re-import. This is the guard that stops it.
@test "an id holding a different person is refused instead of rewritten" {
    doli_fixture members_2 "$(jq -n '{id:"2",lastname:"Somebody",address:"Irgendwo 1",zip:"1010",town:"Wien"}')"
    doli_set_address --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *"Refusing to write"* ]]
    [[ "$output" == *"Somebody"* ]]
    [ "$(doli_put_count)" -eq 0 ]
}

@test "a missing record list explains itself" {
    export DOLIBARR_ADDRESS_RECORDS="$BATS_TEST_TMPDIR/does-not-exist.json"
    doli_set_address
    [ "$status" -eq 1 ]
    [[ "$output" == *"no record list at"* ]]
    [[ "$output" == *"address-records.example.json"* ]]
}

@test "a missing record fails loudly" {
    doli_fixture members_2 '{"error":{"code":404,"message":"Not Found"}}'
    doli_set_address
    [ "$status" -eq 1 ]
    [[ "$output" == *"did not return a record"* ]]
}

# The organisation record is GET-only in Dolibarr, measured on 2026-09-14.
@test "the organisation record is never written" {
    doli_set_address --apply
    run doli_requests
    [[ "$output" != *"setup/company"* ]]
}
