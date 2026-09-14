#!/usr/bin/env bats
# Tests for tools/dolibarr/doli.sh

load test_helper

setup() {
    common_setup
    doli_setup
}

@test "help works without a key file and names the two knobs" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    doli --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"DOLIBARR_URL"* ]]
    [[ "$output" == *"DOLIBARR_TOKEN_FILE"* ]]
}

@test "no arguments prints the usage and fails" {
    doli
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "an unknown command fails with the command named" {
    doli frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a missing key file explains how to create it" {
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/does-not-exist"
    doli status
    [ "$status" -eq 1 ]
    [[ "$output" == *"no API key at"* ]]
    [[ "$output" == *"chmod 600"* ]]
}

@test "a world readable key file is called out but still works" {
    chmod 644 "$DOLIBARR_TOKEN_FILE"
    doli status
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode 644"* ]]
}

@test "status returns the body" {
    export STUB_DOLI_BODY='{"success":{"code":200,"message":"ok"}}'
    doli status
    [ "$status" -eq 0 ]
    [[ "$output" == *'"code"'* ]]
}

# The whole point of the curl --config detour: the key must not be visible to
# anything that can read the process list.
@test "the API key travels in a header and never in the argument list" {
    doli status
    [ "$status" -eq 0 ]
    grep -q 'DOLAPIKEY: fake-api-key-0123456789' "$STUB_DOLI_CONFIG"
    run grep -c 'fake-api-key' "$STUB_DOLI_ARGS"
    [ "$status" -ne 0 ]
}

@test "the key never appears in the output either" {
    export STUB_DOLI_BODY='{"success":{"code":200}}'
    doli status
    [[ "$output" != *"fake-api-key"* ]]
}

@test "a disabled Api module is reported as such and not as a success" {
    export STUB_DOLI_BODY='Module <b>Api</b> must be enabled.<br><br>To activate modules, go on setup Area.'
    doli status
    [ "$status" -eq 1 ]
    [[ "$output" == *"Api module is disabled"* ]]
    [[ "$output" == *"Home, Setup, Modules"* ]]
}

@test "a non-200 status fails and shows the body" {
    export STUB_DOLI_CODE=401
    export STUB_DOLI_BODY='{"error":{"code":401,"message":"Invalid API key"}}'
    doli status
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTTP 401"* ]]
    [[ "$output" == *"Invalid API key"* ]]
}

@test "company reads the organisation record" {
    export STUB_DOLI_BODY='{"name":"SdWa5","address":"Egitlweg 6"}'
    doli company
    [ "$status" -eq 0 ]
    [[ "$output" == *"Egitlweg 6"* ]]
    grep -q 'setup/company' "$STUB_DOLI_ARGS"
}

@test "get without a path fails with an example" {
    doli get
    [ "$status" -eq 1 ]
    [[ "$output" == *"thirdparties"* ]]
}

@test "get passes the path through to the API root" {
    doli get 'thirdparties?limit=5'
    [ "$status" -eq 0 ]
    grep -q 'https://erp.example.org/api/index.php/thirdparties?limit=5' "$STUB_DOLI_ARGS"
}
