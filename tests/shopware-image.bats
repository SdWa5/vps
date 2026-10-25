#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# The script runs against a throwaway git repository (SDWA5_REPO_ROOT), because
# the bats container sees /code as owned by another user. docker and ssh are
# stubs that log every call.

setup() {
    export IMAGE_SCRIPT="$BATS_TEST_DIRNAME/../tools/shopware/image.sh"
    export DOCKERFILE_SRC="$BATS_TEST_DIRNAME/../shopware/Dockerfile"
    export SDWA5_REPO_ROOT="$BATS_TEST_TMPDIR/repo"
    export SDWA5_SHOPWARE_AUTH="$BATS_TEST_TMPDIR/auth.json"
    export SDWA5_SHOPWARE_SSH='root@host.test'
    export DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
    unset SDWA5_SHOPWARE_IMAGE
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    printf '{"bearer":{}}\n' > "$SDWA5_SHOPWARE_AUTH"
    repo
    fake_docker
    fake_ssh
}

repo() {
    mkdir -p "$SDWA5_REPO_ROOT"/{shopware,shopware-html-data,docs}
    cp "$DOCKERFILE_SRC" "$SDWA5_REPO_ROOT/shopware/Dockerfile"
    printf 'APP_ENV=prod\n' > "$SDWA5_REPO_ROOT/shopware/.env"
    printf '{}\n' > "$SDWA5_REPO_ROOT/shopware-html-data/composer.json"
    printf 'x\n' > "$SDWA5_REPO_ROOT/docs/readme.md"
    cat > "$SDWA5_REPO_ROOT/docker-compose.yml" <<'YAML'
services:
  caddy:
    image: caddy:2
  shopware:
    image: localhost/sdwa5-shopware:6.7.15.1-3
    restart: unless-stopped
  shopware_db:
    image: mysql:8.4
YAML
    git -C "$SDWA5_REPO_ROOT" init -q
    git -C "$SDWA5_REPO_ROOT" add -A
    git -C "$SDWA5_REPO_ROOT" -c user.name=t -c user.email=t@t commit -qm init
}

# LOCAL_ID is the workstation's image ID, REV_LABEL its revision label.
fake_docker() {
    cat > "$BATS_TEST_TMPDIR/bin/docker" <<'STUB'
#!/bin/bash
printf 'CALL %s\n' "$*" >> "$DOCKER_LOG"
case "$*" in
    'buildx build '*)
        context="${*: -1}"
        find "$context" "$context/../shopware-html-data" -type f | sed "s#^$context/../#EXPORT #;s#^$context/#EXPORT shopware/#" >> "$DOCKER_LOG" ;;
    *'.Config.Labels'*) printf '%s\n' "${REV_LABEL:-abc123}" ;;
    'image inspect -f {{.Id}} '*)
        [[ -n "${LOCAL_ID-sha256:local}" ]] || exit 1
        printf '%s\n' "${LOCAL_ID-sha256:local}" ;;
    save*) printf 'IMAGE-TAR' ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/docker"
}

# REMOTE_ID is the host's ID before the load (empty: unknown image), LOADED_ID
# after it. SSH_DOWN=1 makes ssh fail like an unreachable host.
fake_ssh() {
    cat > "$BATS_TEST_TMPDIR/bin/ssh" <<'STUB'
#!/bin/bash
[[ "${SSH_DOWN:-0}" == 1 ]] && exit 255
shift 3
printf 'SSH %s\n' "$*" >> "$SSH_LOG"
case "$*" in
    'gunzip | docker load')
        cat > /dev/null
        touch "$BATS_TEST_TMPDIR/loaded" ;;
    'docker image inspect'*)
        if [[ -e "$BATS_TEST_TMPDIR/loaded" ]]; then id="${LOADED_ID:-sha256:local}"; else id="${REMOTE_ID:-}"; fi
        [[ -n "$id" ]] || exit 1
        printf '%s\n' "$id" ;;
esac
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
}

final_stage() { awk 'toupper($1) == "FROM" { stage = "" } { stage = stage $0 "\n" } END { printf "%s", stage }' "$DOCKERFILE_SRC"; }

@test "--help exits 0 and an unknown command exits 2" {
    run bash "$IMAGE_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *'Build, ship and maintain'* ]]
    [[ "$output" != *'set -euo pipefail'* ]]
    run bash "$IMAGE_SCRIPT" push
    [ "$status" -eq 2 ]
}

@test "build passes the secret, the context, the six labels and the compose tag" {
    run bash "$IMAGE_SCRIPT" build
    [ "$status" -eq 0 ]
    [[ "$output" == *'sha256:local'* ]]
    call="$(grep '^CALL buildx build' "$DOCKER_LOG")"
    rev="$(git -C "$SDWA5_REPO_ROOT" rev-parse HEAD)"
    [[ "$call" == *"--load "* ]]
    [[ "$call" == *"--secret id=composer_auth,src=$SDWA5_SHOPWARE_AUTH "* ]]
    [[ "$call" == *'--build-context project='*'/shopware-html-data '* ]]
    [[ "$call" == *'--label org.opencontainers.image.title=sdwa5-shopware '* ]]
    [[ "$call" == *'--label org.opencontainers.image.source=https://github.com/SdWa5/vps '* ]]
    [[ "$call" == *"--label org.opencontainers.image.revision=$rev "* ]]
    [[ "$call" == *'--label org.opencontainers.image.version=6.7.15.1-3 '* ]]
    [[ "$call" == *'--label org.opencontainers.image.base.name=ghcr.io/shopware/docker-base:'*' '* ]]
    [[ "$call" == *'--label org.opencontainers.image.base.digest=sha256:'* ]]
    [[ "$call" == *'-t localhost/sdwa5-shopware:6.7.15.1-3 '* ]]
}

@test "build exports only tracked files, uncommitted edits included" {
    printf 'APP_ENV=prod\n# edited\n' > "$SDWA5_REPO_ROOT/shopware/.env"
    printf 'untracked\n' > "$SDWA5_REPO_ROOT/shopware/untracked.txt"
    run bash "$IMAGE_SCRIPT" build
    [ "$status" -eq 0 ]
    grep -qx 'EXPORT shopware/.env' "$DOCKER_LOG"
    grep -qx 'EXPORT shopware-html-data/composer.json' "$DOCKER_LOG"
    run ! grep -q 'untracked.txt' "$DOCKER_LOG"
    run ! grep -q 'EXPORT docs/' "$DOCKER_LOG"
}

@test "the revision gets -dirty for an edit under shopware/ but not under docs/" {
    printf 'y\n' > "$SDWA5_REPO_ROOT/docs/readme.md"
    run bash "$IMAGE_SCRIPT" build
    grep -q 'image.revision=[0-9a-f]* ' "$DOCKER_LOG"
    run ! grep -q 'image.revision=[0-9a-f]*-dirty' "$DOCKER_LOG"
    printf 'y\n' >> "$SDWA5_REPO_ROOT/shopware/.env"
    run bash "$IMAGE_SCRIPT" build
    grep -q 'image.revision=[0-9a-f]*-dirty ' "$DOCKER_LOG"
}

@test "build fails without the auth file" {
    rm "$SDWA5_SHOPWARE_AUTH"
    run bash "$IMAGE_SCRIPT" build
    [ "$status" -eq 1 ]
    [[ "$output" == *'no store token'* ]]
    run ! grep -q 'buildx' "$DOCKER_LOG"
}

@test "every command refuses an image outside localhost/sdwa5-shopware:" {
    for cmd in build ship 'composer show'; do
        # shellcheck disable=SC2086
        run env SDWA5_SHOPWARE_IMAGE=dockware/shopware:6.7.15.1 bash "$IMAGE_SCRIPT" $cmd
        [ "$status" -eq 1 ]
        [[ "$output" == *'is not a localhost/sdwa5-shopware: image'* ]]
    done
    [ ! -e "$DOCKER_LOG" ]
    [ ! -e "$SSH_LOG" ]
}

@test "ship loads the image and compares the IDs" {
    run bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 0 ]
    [[ "$output" == *'Shipped localhost/sdwa5-shopware:6.7.15.1-3'* ]]
    grep -qx 'CALL save localhost/sdwa5-shopware:6.7.15.1-3' "$DOCKER_LOG"
    grep -qx 'SSH gunzip | docker load' "$SSH_LOG"
}

@test "ship refuses a dirty build" {
    run env REV_LABEL=abc123-dirty bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 1 ]
    [[ "$output" == *'uncommitted files'* ]]
    [ ! -e "$SSH_LOG" ]
}

@test "ship skips an image the host already holds" {
    run env REMOTE_ID=sha256:local bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 0 ]
    [[ "$output" == *'already on the host'* ]]
    run ! grep -q '^CALL save' "$DOCKER_LOG"
}

@test "ship refuses a tag the host holds as another image" {
    run env REMOTE_ID=sha256:other bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 1 ]
    [[ "$output" == *'raise the build number'* ]]
    run ! grep -q '^CALL save' "$DOCKER_LOG"
}

@test "ship fails when the IDs differ after the load" {
    run env LOADED_ID=sha256:broken bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 1 ]
    [[ "$output" == *'loaded localhost/sdwa5-shopware:6.7.15.1-3 as sha256:broken'* ]]
}

@test "ship fails when the host is out of reach" {
    run env SSH_DOWN=1 bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 1 ]
    [[ "$output" == *'cannot reach root@host.test'* ]]
    run ! grep -q '^CALL save' "$DOCKER_LOG"
}

@test "ship fails for an image that is not built" {
    run env LOCAL_ID= bash "$IMAGE_SCRIPT" ship
    [ "$status" -eq 1 ]
    [[ "$output" == *'is not built here'* ]]
}

@test "composer mounts the auth file read-only in the build stage's CLI image" {
    run bash "$IMAGE_SCRIPT" composer show --all shopware/deployment-helper
    [ "$status" -eq 0 ]
    cli="$(awk 'toupper($1) == "FROM" && tolower($3) == "as" && $4 == "build" { print $2 }' "$DOCKERFILE_SRC")"
    call="$(grep '^CALL run' "$DOCKER_LOG")"
    [[ "$call" == *"-v $SDWA5_SHOPWARE_AUTH:/tmp/composer/auth.json:ro "* ]]
    [[ "$call" == *"-v $SDWA5_REPO_ROOT/shopware-html-data:/src "* ]]
    [[ "$call" == *"--entrypoint composer $cli show --all shopware/deployment-helper" ]]
    [ -d "$SDWA5_REPO_ROOT/shopware-html-data/custom/plugins" ]
}

@test "the Dockerfile pins every FROM by digest" {
    froms="$(grep -ciE '^FROM ' "$DOCKERFILE_SRC")"
    [ "$froms" -eq 2 ]
    [ "$(grep -iE '^FROM ' "$DOCKERFILE_SRC" | grep -c '@sha256:[0-9a-f]\{64\}')" -eq "$froms" ]
}

@test "the final stage hardens the base image" {
    stage="$(final_stage)"
    [[ "$stage" == *'FROM ghcr.io/shopware/docker-base:'*'-frankenphp@sha256:'* ]]
    # The capability and the access log go in one RUN.
    run grep -A2 '^RUN setcap -r /usr/local/bin/frankenphp' <<<"$stage"
    [[ "$output" == *"sed -i -E '/^\s*log\s*\$/d' /etc/caddy/Caddyfile"* ]]
    [[ "$stage" == *'CADDY_GLOBAL_OPTIONS="admin off"'* ]]
    grep -qE '^\s+INSTALL_ADMIN_PASSWORD= \\$' <<<"$stage"
    [[ "$stage" == *'DO_NOT_TRACK=1'* ]]
    [[ "$stage" == *'SHOPWARE_DISABLE_UPDATE_CHECK=1'* ]]
    [[ "$stage" == *'HEALTHCHECK '*'http://127.0.0.1:8000/api/_info/health-check'* ]]
    [[ "$stage" == *'USER www-data'* ]]
}
