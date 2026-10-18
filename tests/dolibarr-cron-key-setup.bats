#!/usr/bin/env bats

setup() {
    export KEY_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/cron-key-setup.sh"
    export BATS_TEST_TMPDIR
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export DOLIBARR_ADMIN_PASSWORD_FILE="$BATS_TEST_TMPDIR/password"
    printf 'secret' > "$DOLIBARR_ADMIN_PASSWORD_FILE"
    export DOLIBARR_CRON_KEY_FILE="$BATS_TEST_TMPDIR/cron-key"
    printf 'new-Key_0123456789abcdef' > "$DOLIBARR_CRON_KEY_FILE"
    export STORED="$BATS_TEST_TMPDIR/stored"
    printf 'old-Key_0123456789abcdef' > "$STORED"
    refusing_curl
}

# A curl that fails and records that it was called.
refusing_curl() {
    printf '#!/bin/sh\necho called >> "%s/curl.log"\nexit 97\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/curl"
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

# A curl that plays Dolibarr: a logged-in index page, and a setup page that shows the key in
# $STORED, saves a posted CRON_KEY there unless SAVE_IGNORED is set, and echoes the posted
# value in its answer, as Dolibarr does.
dolibarr_curl() {
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
out="" posted="" url=""
while (( $# )); do
    case "$1" in
        -o) out="$2"; shift ;;
        -w|-b|-c) shift ;;
        --data-urlencode) [[ "$2" == CRON_KEY@* ]] && posted="$(< "${2#CRON_KEY@}")"; shift ;;
        http*) url="$1" ;;
    esac
    shift
done
echo "$url ${posted:+post}" >> "$BATS_TEST_TMPDIR/curl.log"
case "$url" in
    */index.php) echo '<input name="token" value="ab12"><a href="/user/logout.php">out</a>' > "$out" ;;
    */cron/admin/cron.php)
        shown="$(< "$STORED")"
        if [[ -n "$posted" ]]; then
            [[ -n "${SAVE_IGNORED:-}" ]] || printf '%s' "$posted" > "$STORED"
            shown="$posted"
        fi
        printf '<input type="hidden" name="token" value="cd34">\n<input type="text" class="flat" id="CRON_KEY" name="CRON_KEY" value="%s">\n' "$shown" > "$out" ;;
esac
printf 200
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
}

@test "--help prints the usage and touches nothing" {
    run bash "$KEY_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'cron security key'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "an unknown command prints the usage and fails before any request" {
    run bash "$KEY_SCRIPT" rotate
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "an unset key file variable stops before any request" {
    unset DOLIBARR_CRON_KEY_FILE
    run bash "$KEY_SCRIPT" check
    [ "$status" -eq 2 ]
    [[ "$output" == *'DOLIBARR_CRON_KEY_FILE is not set'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "a missing admin password file stops before any request" {
    rm "$DOLIBARR_ADMIN_PASSWORD_FILE"
    run bash "$KEY_SCRIPT" check
    [ "$status" -eq 1 ]
    [[ "$output" == *'Cannot read'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "a key file with other characters is refused before any request and not printed" {
    printf 'short key; rm -rf' > "$DOLIBARR_CRON_KEY_FILE"
    run bash "$KEY_SCRIPT" set
    [ "$status" -eq 1 ]
    [[ "$output" == *'no key of 16 to 128 URL-safe characters'* ]]
    [[ "$output" != *'rm -rf'* ]]
    [ ! -e "$BATS_TEST_TMPDIR/curl.log" ]
}

@test "the stored key is read from the text field and from the hidden one" {
    printf '<input type="text" class="flat" id="CRON_KEY" name="CRON_KEY" value="a&amp;b">\n' > "$BATS_TEST_TMPDIR/text.html"
    printf 'abc<input type="hidden" id="CRON_KEY" name="CRON_KEY" value="xyz">\n' > "$BATS_TEST_TMPDIR/hidden.html"
    run bash -c 'source "$KEY_SCRIPT"; stored_key "$BATS_TEST_TMPDIR/text.html"; stored_key "$BATS_TEST_TMPDIR/hidden.html"'
    [ "${lines[0]}" = 'a&b' ]
    [ "${lines[1]}" = 'xyz' ]
}

@test "check reports a differing key without printing either key" {
    dolibarr_curl
    run bash "$KEY_SCRIPT" check
    [ "$status" -eq 1 ]
    [[ "$output" == *'differs'* ]]
    [[ "$output" != *'Key_'* ]]
    ! grep -q post "$BATS_TEST_TMPDIR/curl.log"
}

@test "set saves the key, a trailing newline in the file dropped, and confirms with a fresh read" {
    printf 'new-Key_0123456789abcdef\n' > "$DOLIBARR_CRON_KEY_FILE"
    dolibarr_curl
    run bash "$KEY_SCRIPT" set
    [ "$status" -eq 0 ]
    [[ "$output" == *'now matches'* ]]
    [[ "$output" != *'Key_'* ]]
    [ "$(cat "$STORED")" = 'new-Key_0123456789abcdef' ]
    [ "$(grep -c 'cron.php post' "$BATS_TEST_TMPDIR/curl.log")" -eq 1 ]
    [ "$(tail -n 1 "$BATS_TEST_TMPDIR/curl.log")" = 'http://localhost:8089/cron/admin/cron.php ' ]
}

@test "set fails when the fresh read still shows the old key, although the answer echoed the new one" {
    export SAVE_IGNORED=1
    dolibarr_curl
    run bash "$KEY_SCRIPT" set
    [ "$status" -eq 1 ]
    [[ "$output" == *'still differs after saving'* ]]
}

@test "set changes nothing when the stored key already matches" {
    printf 'new-Key_0123456789abcdef' > "$STORED"
    dolibarr_curl
    run bash "$KEY_SCRIPT" set
    [ "$status" -eq 0 ]
    [[ "$output" == *'matches'* ]]
    ! grep -q post "$BATS_TEST_TMPDIR/curl.log"
}
