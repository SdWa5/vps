#!/usr/bin/env bats

load test_helper

# A docker that knows one container, `db`, whose environment is STUB_ENV. Its
# printenv answers from the same table unless STUB_PROCESS_VALUE overrides it.
setup() {
    common_setup
    local bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == *' db'* || "$*" == *' db '* ]] || exit 1
case "$1" in
    inspect) printf '%s\n' "$STUB_ENV" ;;
    exec)
        if [[ -n "${STUB_PROCESS_VALUE:-}" ]]; then printf '%s\n' "$STUB_PROCESS_VALUE"; exit 0; fi
        printf '%s\n' "$STUB_ENV" | awk -v k="$4" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); f = 1 } END { exit !f }'
        ;;
esac
STUB
    chmod +x "$bin/docker"
    export PATH="$bin:$PATH"
    export STUB_ENV='PATH=/usr/bin
DB_PW=a$b "c" =d
EMPTY='
    unset STUB_PROCESS_VALUE
    SECRETS="$BATS_TEST_TMPDIR/secrets"
}

write() {
    run bash "$REPO_ROOT/tools/secrets/write-secret-files.sh" --dir "$SECRETS" "$@"
}

@test "a value is copied from the container byte for byte, without a newline, and never printed" {
    write db_password=db:DB_PW
    [ "$status" -eq 0 ]
    [ "$output" = 'db_password: written, matches db DB_PW' ]
    [ "$(cat "$SECRETS/db_password")" = 'a$b "c" =d' ]
    [ "$(wc -c < "$SECRETS/db_password")" -eq 10 ]
    [ "$(stat -c %a "$SECRETS/db_password")" = 400 ]
    [ "$(stat -c %a "$SECRETS")" = 700 ]
}

@test "a random value has 43 URL-safe characters and a second run keeps it" {
    write init=random
    [ "$status" -eq 0 ]
    [[ "$(cat "$SECRETS/init")" =~ ^[A-Za-z0-9_-]{43}$ ]]
    cp "$SECRETS/init" "$BATS_TEST_TMPDIR/first"
    write init=random
    [ "$status" -eq 0 ]
    [[ "$output" == *'left unchanged'* ]]
    cmp "$SECRETS/init" "$BATS_TEST_TMPDIR/first"
}

@test "an existing file is kept when it holds the value and refused when it differs" {
    write db_password=db:DB_PW
    write db_password=db:DB_PW
    [ "$status" -eq 0 ]
    [[ "$output" == *'already holds the value'* ]]
    export STUB_ENV='DB_PW=other'
    write db_password=db:DB_PW
    [ "$status" -eq 1 ]
    [[ "$output" == *'different value, not overwritten'* ]]
    [ "$(cat "$SECRETS/db_password")" = 'a$b "c" =d' ]
}

@test "a missing, empty or inconsistently read variable writes nothing and leaves no temp file" {
    write a=db:ABSENT b=db:EMPTY
    [ "$status" -eq 1 ]
    [[ "$output" == *'db has no ABSENT'* ]]
    [[ "$output" == *'b: the value is empty'* ]]
    export STUB_PROCESS_VALUE=different
    write c=db:DB_PW
    [ "$status" -eq 1 ]
    [[ "$output" == *'differ, nothing written'* ]]
    [[ "$output" != *different* ]]
    [ -z "$(ls -A "$SECRETS")" ]
}

@test "one failing spec does not stop the others, and the run still fails" {
    write a=db:ABSENT db_password=db:DB_PW
    [ "$status" -eq 1 ]
    [ -f "$SECRETS/db_password" ]
}

@test "invalid specs and a missing argument are usage errors" {
    write 'Bad=db:DB_PW'
    [ "$status" -eq 2 ]
    write 'x=db:1bad'
    [ "$status" -eq 2 ]
    write 'x='
    [ "$status" -eq 2 ]
    run bash "$REPO_ROOT/tools/secrets/write-secret-files.sh"
    [ "$status" -eq 2 ]
    run bash "$REPO_ROOT/tools/secrets/write-secret-files.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'NAME=CONTAINER:VARIABLE'* ]]
}
