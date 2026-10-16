#!/usr/bin/env bats

setup() {
    export TOOLS="$BATS_TEST_DIRNAME/../tools/paperless"
    export SDWA5_PAPERLESS_DEV_DIR="$BATS_TEST_TMPDIR/dev"
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export SPEC="$BATS_TEST_TMPDIR/spec.json"
    jq --arg d "$BATS_TEST_TMPDIR/passwords" '.password_dir = $d' "$TOOLS/paperless-spec.example.json" > "$SPEC"
}

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
    chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

@test "dev-instance: without a command it prints the usage and does nothing" {
    stub docker 'exit 97'
    run bash "$TOOLS/dev-instance.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *'dev mirror of paper.sdwa5.org'* ]]
}

@test "dev-instance: an unknown instance is refused before docker runs" {
    stub docker 'exit 97'
    run bash "$TOOLS/dev-instance.sh" up shared
    [ "$status" -ne 0 ]
    [[ "$output" == *'Use sdwa5 or home'* ]]
}

@test "dev-instance: the images follow the production compose file, anchors skipped" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; compose_image paperless_sdwa5; printf " "; compose_image paperless_sdwa5_broker; printf " "; compose_image paperless_sdwa5_db'
    [ "$status" -eq 0 ]
    [[ "$output" == "ghcr.io/paperless-ngx/paperless-ngx:"*"@sha256:"*" valkey/valkey:"*" mariadb:"* ]]
}

@test "dev-instance: the shared settings come from x-paperless-env" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; compose_paperless_env'
    [ "$status" -eq 0 ]
    [[ "$output" == *'PAPERLESS_CONSUMER_DISABLE=true'* ]]
    [[ "$output" == *'PAPERLESS_TASK_WORKERS=1'* ]]
    [[ "$output" != *'PAPERLESS_URL'* ]]
}

@test "dev-instance: the generated secrets are private and never printed" {
    run bash -c 'source "$TOOLS/dev-instance.sh"; select_instance home; ensure_secrets'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(stat -c %a "$SDWA5_PAPERLESS_DEV_DIR/home/app.env")" = 600 ]
    [ "$(stat -c %a "$SDWA5_PAPERLESS_DEV_DIR/home/passwords/admin")" = 600 ]
    grep -q '^PAPERLESS_ADMIN_PASSWORD=[0-9a-f]\{32\}$' "$SDWA5_PAPERLESS_DEV_DIR/home/app.env"
}

@test "setup: without a spec it prints the usage" {
    run bash "$TOOLS/setup.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *'dry-run by default'* ]]
}

@test "setup: a spec without password_dir is refused" {
    jq 'del(.password_dir)' "$SPEC" > "$BATS_TEST_TMPDIR/bad.json"
    stub curl 'exit 97'
    run bash "$TOOLS/setup.sh" "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'no password_dir'* ]]
}

@test "setup: a workflow read back from the API matches the wanted one" {
    run bash -c 'source "$TOOLS/setup.sh"
        wanted="$(share_workflow "Share tag Shared with group members" 3 2 | normalise_workflow)"
        api="{\"id\":7,\"name\":\"Share tag Shared with group members\",\"order\":0,\"enabled\":true,
            \"triggers\":[{\"id\":2,\"type\":3,\"sources\":[\"4\",\"3\",\"2\",\"1\"],\"matching_algorithm\":0,\"filter_has_tags\":[3],\"filter_path\":null},
                          {\"id\":1,\"type\":2,\"sources\":[1,2,3,4],\"matching_algorithm\":0,\"filter_has_tags\":[3]}],
            \"actions\":[{\"id\":1,\"type\":1,\"assign_view_groups\":[2],\"assign_change_groups\":[2],\"assign_tags\":[]}]}"
        [ "$(normalise_workflow <<< "$api")" = "$wanted" ]'
    [ "$status" -eq 0 ]
}

@test "setup: a workflow that lost Web UI uploads differs" {
    run bash -c 'source "$TOOLS/setup.sh"
        wanted="$(share_workflow "w" 3 2 | normalise_workflow)"
        changed="$(share_workflow "w" 3 2 | jq -c ".triggers[0].sources = [1, 2, 3]" | normalise_workflow)"
        [ "$changed" != "$wanted" ]'
    [ "$status" -eq 0 ]
}

@test "lib: a cached token is used without asking /api/token/, and only on a pipe" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'cached-token' > "$BATS_TEST_TMPDIR/passwords/alice.token"
    stub curl 'case "$*" in *api/token*) exit 97 ;; esac
for arg; do [ "$arg" = cached-token ] && exit 98; done
while [ $# -gt 0 ]; do [ "$1" = --config ] && cat "$2"; shift; done'
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; curl_as alice "$PAPERLESS_URL/api/"'
    [ "$status" -eq 0 ]
    [ "$output" = 'header = "Authorization: Token cached-token"' ]
}

@test "lib: a throttled token request waits and retries" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'pw' > "$BATS_TEST_TMPDIR/passwords/bob"
    stub sleep 'exit 0'
    stub curl "cat >/dev/null
if [ -e '$BATS_TEST_TMPDIR/once' ]; then printf '{\"token\":\"fresh\"}'; else touch '$BATS_TEST_TMPDIR/once'; printf '{\"detail\":\"Request was throttled. Expected available in 3 seconds.\"}'; fi"
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; ensure_token bob'
    [ "$status" -eq 0 ]
    [[ "$output" == *'waiting 3 s'* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/passwords/bob.token")" = fresh ]
}

@test "lib: a wrong password fails without a token file" {
    mkdir -p "$BATS_TEST_TMPDIR/passwords"
    printf 'pw' > "$BATS_TEST_TMPDIR/passwords/bob"
    stub curl 'cat >/dev/null; printf "{\"non_field_errors\":[\"Unable to log in\"]}"'
    run bash -c 'source "$TOOLS/lib.sh"; load_spec; ensure_token bob'
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/passwords/bob.token" ]
}

@test "visibility-check: the generated PDF has a valid cross-reference offset" {
    run bash -c 'source "$TOOLS/visibility-check.sh"; make_pdf "visibility-check abc alice private" "$BATS_TEST_TMPDIR/t.pdf"'
    [ "$status" -eq 0 ]
    offset="$(tail -n 2 "$BATS_TEST_TMPDIR/t.pdf" | head -n 1)"
    [ "$(tail -c +"$((offset + 1))" "$BATS_TEST_TMPDIR/t.pdf" | head -n 1)" = xref ]
    head -c 8 "$BATS_TEST_TMPDIR/t.pdf" | grep -q '^%PDF-1.4'
}

@test "visibility-check: group membership is read from the spec" {
    run bash -c 'source "$TOOLS/visibility-check.sh"; in_group alice members && ! in_group alice board'
    [ "$status" -eq 0 ]
}
