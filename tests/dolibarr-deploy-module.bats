#!/usr/bin/env bats
# Tests for tools/dolibarr/deploy-module.sh
#
# These run real git against a throwaway source repository instead of the git stub, because what
# matters here is git's own behaviour: that a tag resolves, that a detached checkout lands on it,
# and that root can still operate on a tree it handed to uid 1000.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/tools/dolibarr/deploy-module.sh"

    export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
    : > "$GIT_CONFIG_GLOBAL"

    SRC="$BATS_TEST_TMPDIR/src"
    git init --quiet -b main "$SRC"
    echo one > "$SRC/version.txt"
    git -C "$SRC" add version.txt
    git -C "$SRC" commit --quiet -m one
    git -C "$SRC" tag v1.0.0
    echo two > "$SRC/version.txt"
    git -C "$SRC" commit --quiet -am two
    git -C "$SRC" tag -a v1.1.0 -m "annotated"

    export CUSTOM_DIR="$BATS_TEST_TMPDIR/custom"
    mkdir -p "$CUSTOM_DIR"
    export MODULE_OWNER=""
}

deploy() {
    run "$SCRIPT" "$@"
}

@test "--help prints the usage" {
    deploy --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "a missing argument is refused" {
    deploy banksync "$SRC"
    [ "$status" -eq 1 ]
    [[ "$output" == *"expected NAME REPO TAG"* ]]
}

@test "a name with a path in it is refused" {
    deploy ../evil "$SRC" v1.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"NAME must match"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/evil" ]
}

@test "a first deploy clones and checks out the tag" {
    deploy banksync "$SRC" v1.0.0
    [ "$status" -eq 0 ]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = one ]
    [[ "$output" == *"banksync: none -> v1.0.0"* ]]
}

@test "an update moves to the newer tag, an annotated one included" {
    deploy banksync "$SRC" v1.0.0
    deploy banksync "$SRC" v1.1.0
    [ "$status" -eq 0 ]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = two ]
    [[ "$output" == *"-> v1.1.0"* ]]
}

@test "a tag pushed after the first deploy is fetched" {
    deploy banksync "$SRC" v1.1.0
    echo three > "$SRC/version.txt"
    git -C "$SRC" commit --quiet -am three
    git -C "$SRC" tag v1.2.0
    deploy banksync "$SRC" v1.2.0
    [ "$status" -eq 0 ]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = three ]
}

@test "a rollback is the same command with the older tag" {
    deploy banksync "$SRC" v1.1.0
    deploy banksync "$SRC" v1.0.0
    [ "$status" -eq 0 ]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = one ]
}

@test "an unknown tag fails and leaves the checkout where it was" {
    deploy banksync "$SRC" v1.0.0
    deploy banksync "$SRC" v9.9.9
    [ "$status" -eq 1 ]
    [[ "$output" == *"tag v9.9.9 not found"* ]]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = one ]
}

@test "a branch name is not accepted as a tag" {
    deploy banksync "$SRC" main
    [ "$status" -eq 1 ]
    [[ "$output" == *"tag main not found"* ]]
}

@test "a directory that is not a git checkout is left alone" {
    mkdir -p "$CUSTOM_DIR/banksync"
    echo keep > "$CUSTOM_DIR/banksync/file"
    deploy banksync "$SRC" v1.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a git checkout"* ]]
    [ "$(cat "$CUSTOM_DIR/banksync/file")" = keep ]
}

@test "a checkout of another repository is refused" {
    deploy banksync "$SRC" v1.0.0
    deploy banksync "$BATS_TEST_TMPDIR/other" v1.0.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"tracks $SRC"* ]]
}

@test "local edits in the checkout are not overwritten" {
    deploy banksync "$SRC" v1.0.0
    echo hacked > "$CUSTOM_DIR/banksync/version.txt"
    deploy banksync "$SRC" v1.1.0
    [ "$status" -eq 1 ]
    [[ "$output" == *"local changes"* ]]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = hacked ]
}

@test "the checkout is handed to the web user and root can still update it" {
    [ "$(id -u)" -eq 0 ] || skip "needs root to chown"
    MODULE_OWNER=1000:1000 deploy banksync "$SRC" v1.0.0
    [ "$status" -eq 0 ]
    [ "$(stat -c %u:%g "$CUSTOM_DIR/banksync/version.txt")" = 1000:1000 ]
    MODULE_OWNER=1000:1000 deploy banksync "$SRC" v1.1.0
    [ "$status" -eq 0 ]
    [ "$(cat "$CUSTOM_DIR/banksync/version.txt")" = two ]
}
