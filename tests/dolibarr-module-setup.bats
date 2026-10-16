#!/usr/bin/env bats

setup() {
    export MODULE_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/module-setup.sh"
    export LIB="$BATS_TEST_DIRNAME/../tools/dolibarr/lib.sh"
    mkdir "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho called >> "%s/curl.log"\nexit 97\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/curl"
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DOLIBARR_ADMIN_PASSWORD_FILE="$BATS_TEST_TMPDIR/password"
    printf 'secret' > "$DOLIBARR_ADMIN_PASSWORD_FILE"
}

# The two link forms Dolibarr 24 renders: the enable link with bare "&", the disable link escaped.
modules_page() {
    cat > "$BATS_TEST_TMPDIR/modules.html" <<'HTML'
<a class="reposition" href="/admin/modules.php?id=1&action=set&token=ab12&value=modPmTools&mode=commonkanban">on</a>
<a class="reposition" href="/admin/modules.php?id=2&amp;action=reset&amp;token=ab12&amp;value=modBankSync&amp;mode=commonkanban">off</a>
<a class="reposition" href="/admin/modules.php?id=3&action=set&token=ab12&value=modPmToolsExtra&mode=commonkanban">on</a>
HTML
}

@test "--help prints the usage and touches nothing" {
    run bash "$MODULE_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Setup -> Modules'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "an unknown command prints the usage and fails before any request" {
    run bash "$MODULE_SCRIPT" toggle PmTools
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "a module name that is not a class name is refused before any request" {
    run bash "$MODULE_SCRIPT" enable '../x'
    [ "$status" -eq 2 ]
    [[ "$output" == *'Not a module class'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "a missing admin password file stops before any request" {
    rm "$DOLIBARR_ADMIN_PASSWORD_FILE"
    run bash "$MODULE_SCRIPT" status PmTools
    [ "$status" -eq 1 ]
    [[ "$output" == *'Cannot read'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "the enable link with bare ampersands is found and made relative" {
    modules_page
    run bash -c 'source "$MODULE_SCRIPT"; switch_link "$BATS_TEST_TMPDIR/modules.html" set modPmTools'
    [ "$output" = 'admin/modules.php?id=1&action=set&token=ab12&value=modPmTools&mode=commonkanban' ]
}

@test "the escaped disable link is found and decoded" {
    modules_page
    run bash -c 'source "$MODULE_SCRIPT"; switch_link "$BATS_TEST_TMPDIR/modules.html" reset modBankSync'
    [ "$output" = 'admin/modules.php?id=2&action=reset&token=ab12&value=modBankSync&mode=commonkanban' ]
}

@test "the state is read off the switch link of exactly that class" {
    modules_page
    run bash -c 'source "$MODULE_SCRIPT"
        f="$BATS_TEST_TMPDIR/modules.html"
        printf "%s %s %s\n" "$(module_state "$f" modPmTools)" "$(module_state "$f" modBankSync)" "$(module_state "$f" modPmTool)"'
    [ "$output" = 'disabled enabled unknown' ]
}

@test "the library takes the dev mirror as default target" {
    run bash -c 'unset DOLIBARR_URL; source "$LIB"; printf "%s %s" "$DOLIBARR_URL" "$DOLIBARR_ADMIN_LOGIN"'
    [ "$output" = 'http://localhost:8089 admin' ]
}

@test "a failed request names the path and the status" {
    run bash -c 'source "$LIB"; WORK="$BATS_TEST_TMPDIR"; curl() { printf 500; }; page admin/modules.php'
    [ "$status" -ne 0 ]
    [[ "$output" == *'HTTP 500 from admin/modules.php'* ]]
}
