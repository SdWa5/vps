#!/usr/bin/env bats
# Tests for tools/sandbox/sandbox.sh
#
# Everything that changes the host runs under --dry-run, so the tests assert the
# commands the tool would run. Reads go to stubs: getent and setpriv from
# tests/stubs, dpkg-query and dockerd-rootless-setuptool.sh from a per-test bin.

load test_helper

setup() {
    common_setup
    TEST_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$TEST_BIN"
    printf '#!/bin/sh\nprintf "5:29.9.3-1~debian.13~trixie"\n' > "$TEST_BIN/dpkg-query"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_BIN/dockerd-rootless-setuptool.sh"
    chmod 755 "$TEST_BIN/dpkg-query" "$TEST_BIN/dockerd-rootless-setuptool.sh"
    # Real git ahead of the git stub, so the private path listing is git's own.
    local real_path="${PATH#"$BATS_TEST_DIRNAME/stubs:"}"
    ln -s "$(PATH="$real_path" command -v git)" "$TEST_BIN/git"
    export PATH="$TEST_BIN:$PATH"
    export COMPOSE_DIR="$BATS_TEST_TMPDIR/compose"
    mkdir -p "$COMPOSE_DIR"
    export STUB_GETENT_GROUP='sandbox:x:998:chimodiazz'
    export STUB_GETENT_PASSWD='chimodiazz:x:1001:1001::/opt/docker/sandbox/chimodiazz:/usr/sbin/nologin
www-data:x:33:33:www-data:/var/www:/usr/sbin/nologin'
    export SUBUID_FILE="$BATS_TEST_TMPDIR/subuid"
    export SUBGID_FILE="$BATS_TEST_TMPDIR/subgid"
    printf 'chimodiazz:165536:65536\n' > "$SUBUID_FILE"
    printf 'chimodiazz:165536:65536\n' > "$SUBGID_FILE"
    export STUB_SETPRIV_LOG="$BATS_TEST_TMPDIR/setpriv.log"
    : > "$STUB_SETPRIV_LOG"
}

sandbox() {
    run "$REPO_ROOT/tools/sandbox/sandbox.sh" "$@"
}

@test "a changing command is refused without root unless it is a dry run" {
    SANDBOX_EUID=1000 sandbox create newproject
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run as root"* ]]
    SANDBOX_EUID=1000 sandbox create newproject --dry-run
    [ "$status" -eq 0 ]
}

@test "a sandbox name must be a short lowercase word" {
    sandbox create 'Bad_Name' --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid sandbox name"* ]]
    sandbox create '../x' --dry-run
    [ "$status" -eq 1 ]
}

@test "an existing account outside the sandbox group is refused" {
    sandbox create www-data --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a sandbox account"* ]]
}

@test "create needs prepare-host first" {
    unset STUB_GETENT_GROUP
    sandbox create newproject --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"run prepare-host first"* ]]
}

@test "create adds a normal account with its home below the sandbox directory" {
    sandbox create newproject --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would run: useradd --home-dir $COMPOSE_DIR/sandbox/newproject --no-create-home --shell /usr/sbin/nologin --user-group --groups sandbox newproject"* ]]
    [[ "$output" == *"would run: install -d -m 0700 -o newproject -g newproject $COMPOSE_DIR/sandbox/newproject"* ]]
    [[ "$output" != *"--system"* ]]
}

@test "create limits the slice, enables linger, installs the daemon and reloads the firewall" {
    sandbox create chimodiazz --memory 2G --cpus 3 --tasks 512 --dry-run
    [ "$status" -eq 0 ]
    # An existing sandbox account keeps its account and home.
    [[ "$output" != *useradd* ]]
    [[ "$output" == *"/etc/systemd/system/user-1001.slice.d/50-sandbox.conf"* ]]
    [[ "$output" == *"MemoryMax=2G"* ]]
    [[ "$output" == *"TasksMax=512"* ]]
    [[ "$output" == *"CPUQuota=300%"* ]]
    [[ "$output" == *"would run: loginctl enable-linger chimodiazz"* ]]
    [[ "$output" == *"would run: as_sandbox chimodiazz env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus dockerd-rootless-setuptool.sh install"* ]]
    [[ "$output" == *"would run: systemctl restart sdwa5-firewall"* ]]
}

@test "create refuses an account without a subordinate id range" {
    : > "$SUBGID_FILE"
    sandbox create chimodiazz --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no range"* ]]
}

@test "prepare-host pins the rootless package to docker-ce and closes the private paths" {
    mkdir -p "$COMPOSE_DIR/open-data" "$COMPOSE_DIR/closed-data" "$COMPOSE_DIR/sandbox"
    git -C "$COMPOSE_DIR" init -q
    printf '/open-data/\n/closed-data/\n/sandbox/\n' > "$COMPOSE_DIR/.gitignore"
    chmod 755 "$COMPOSE_DIR/.git" "$COMPOSE_DIR/open-data" "$COMPOSE_DIR/sandbox"
    chmod 700 "$COMPOSE_DIR/closed-data"
    sandbox prepare-host --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"docker-ce-rootless-extras=5:29.9.3-1~debian.13~trixie"* ]]
    [[ "$output" == *"would run: install -d -m 0711 -o root -g root $COMPOSE_DIR/sandbox"* ]]
    [[ "$output" == *"would run: chmod o-rwx -- $COMPOSE_DIR/open-data"* ]]
    [[ "$output" == *"would run: chmod o-rwx -- $COMPOSE_DIR/.git"* ]]
    [[ "$output" != *"o-rwx -- $COMPOSE_DIR/closed-data"* ]]
    [[ "$output" != *"o-rwx -- $COMPOSE_DIR/sandbox"* ]]
    # The group exists in these fixtures, so it is not created again.
    [[ "$output" != *groupadd* ]]
}

@test "run and compose act as the account, compose with the home as project directory" {
    sandbox compose chimodiazz config --quiet
    grep -qF -- "--reuid=chimodiazz" "$STUB_SETPRIV_LOG"
    grep -qF -- "docker compose --project-name chimodiazz --project-directory $COMPOSE_DIR/sandbox/chimodiazz -f $COMPOSE_DIR/projects/chimodiazz/docker-compose.yml config --quiet" "$STUB_SETPRIV_LOG"
}

@test "run refuses an account outside the sandbox group" {
    sandbox run www-data id
    [ "$status" -eq 1 ]
    [ ! -s "$STUB_SETPRIV_LOG" ]
}
