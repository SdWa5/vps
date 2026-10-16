#!/usr/bin/env bats

setup() {
    export MCP_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/mcp-setup.sh"
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\nexit 97\n' > "$BATS_TEST_TMPDIR/bin/curl"
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DOLIBARR_ADMIN_PASSWORD_FILE="$BATS_TEST_TMPDIR/password"
    printf 'secret' > "$DOLIBARR_ADMIN_PASSWORD_FILE"
}

user_list() {
    cat > "$BATS_TEST_TMPDIR/list.html" <<'EOF'
<a href="/user/card.php?id=1" class="dropdown-toggle login-dropdown-a">
<tr data-rowid="4" class="oddeven"><td><a href="card.php?id=4">Florian</a></td><td class="tdoverflowmax150">flo.sch</td></tr>
<tr data-rowid="5" class="oddeven"><td><a href="card.php?id=5">MCP service</a></td><td>mcp</td></tr>
EOF
}

@test "--help prints the usage and touches nothing" {
    run bash "$MCP_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'core MCP server of Dolibarr 24'* ]]
}

@test "an unknown option prints the usage and fails" {
    run bash "$MCP_SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "a login that is not a plain user name is refused" {
    run bash "$MCP_SCRIPT" --login '../x'
    [ "$status" -eq 2 ]
}

@test "a missing admin password file stops before any request" {
    rm "$DOLIBARR_ADMIN_PASSWORD_FILE"
    run bash "$MCP_SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Cannot read'* ]]
}

@test "the form token is read from the page" {
    printf '<input type="hidden" name="token" value="0a1b2c">\n' > "$BATS_TEST_TMPDIR/page.html"
    run bash -c 'source "$MCP_SCRIPT"; form_token "$BATS_TEST_TMPDIR/page.html"'
    [ "$output" = '0a1b2c' ]
}

@test "the user id comes from the row of that login, not from the top menu" {
    user_list
    run bash -c 'source "$MCP_SCRIPT"; user_id_from_list "$BATS_TEST_TMPDIR/list.html" mcp'
    [ "$output" = '5' ]
}

@test "a login that is only part of another one does not match" {
    user_list
    run bash -c 'source "$MCP_SCRIPT"; user_id_from_list "$BATS_TEST_TMPDIR/list.html" flo'
    [ -z "$output" ]
}

@test "the key is stored privately and never printed" {
    key="$(printf 'k%.0s' {1..64})"
    printf '<input type="text" id="apikey" value="%s" readonly>\n' "$key" > "$BATS_TEST_TMPDIR/setup.html"
    run bash -c 'source "$MCP_SCRIPT"; umask 077; store_key "$BATS_TEST_TMPDIR/setup.html" "$BATS_TEST_TMPDIR/key"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"$key"* ]]
    [[ "$output" == *'64 characters'* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/key")" = "$key" ]
    [ "$(stat -c %a "$BATS_TEST_TMPDIR/key")" = 600 ]
}

@test "a setup page without a key is an error and leaves no file" {
    printf '<html>no key</html>\n' > "$BATS_TEST_TMPDIR/setup.html"
    run bash -c 'source "$MCP_SCRIPT"; store_key "$BATS_TEST_TMPDIR/setup.html" "$BATS_TEST_TMPDIR/key"'
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/key" ]
}

@test "a right id that is not a number is refused" {
    run bash -c 'source "$MCP_SCRIPT"; page() { :; }; grant_rights 5 "56001,x"'
    [ "$status" -ne 0 ]
    [[ "$output" == *'Not a right id: x'* ]]
}
