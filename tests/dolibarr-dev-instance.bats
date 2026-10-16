#!/usr/bin/env bats

setup() {
    export DEV_SCRIPT="$BATS_TEST_DIRNAME/../tools/dolibarr/dev-instance.sh"
    export SDWA5_DOLIBARR_DEV_DIR="$BATS_TEST_TMPDIR/dev"
    mkdir "$BATS_TEST_TMPDIR/bin"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

stub() {
    printf '#!/bin/sh\n%s\n' "$2" > "$BATS_TEST_TMPDIR/bin/$1"
    chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

archive_with() {
    mkdir "$BATS_TEST_TMPDIR/archive"
    for file in "$@"; do printf 'x\n' > "$BATS_TEST_TMPDIR/archive/$file"; done
    tar -czf "$BATS_TEST_TMPDIR/archive.tar.gz" -C "$BATS_TEST_TMPDIR/archive" "$@"
}

@test "without a command it prints the usage and does nothing" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *'dev mirror of erp.sdwa5.org'* ]]
}

@test "the images follow the production compose file" {
    run bash -c 'source "$DEV_SCRIPT"; app_image; printf " "; db_image'
    [ "$status" -eq 0 ]
    [[ "$output" == "dolibarr/dolibarr:"*" mariadb:"* ]]
    [[ "$output" == "$(awk '/^  dolibarr:$/{f=1} f&&/image:/{print $2; exit}' "$BATS_TEST_DIRNAME/../docker-compose.yml") "* ]]
}

@test "an explicit image overrides the compose pin" {
    run env SDWA5_DOLIBARR_DEV_IMAGE=dolibarr/dolibarr:24.0.2 bash -c 'source "$DEV_SCRIPT"; app_image'
    [ "$output" = 'dolibarr/dolibarr:24.0.2' ]
}

@test "fetch keeps a valid archive" {
    archive_with dump.sql manifest.tsv
    stub ssh "cat '$BATS_TEST_TMPDIR/archive.tar.gz'"
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -eq 0 ]
    [ -s "$SDWA5_DOLIBARR_DEV_DIR/archive.tar.gz" ]
    [ ! -e "$SDWA5_DOLIBARR_DEV_DIR/archive.tar.gz.part" ]
}

@test "fetch rejects an archive without a dump" {
    archive_with manifest.tsv
    stub ssh "cat '$BATS_TEST_TMPDIR/archive.tar.gz'"
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [[ "$output" == *'no dump.sql'* ]]
    [ ! -e "$SDWA5_DOLIBARR_DEV_DIR/archive.tar.gz" ]
}

@test "fetch rejects a truncated download" {
    stub ssh "printf 'not gzip'"
    run bash "$DEV_SCRIPT" fetch
    [ "$status" -ne 0 ]
    [ ! -e "$SDWA5_DOLIBARR_DEV_DIR/archive.tar.gz" ]
}

@test "restore refuses to run without an archive" {
    stub docker 'exit 97'
    run bash "$DEV_SCRIPT" restore
    [ "$status" -ne 0 ]
    [[ "$output" == *'Run fetch first'* ]]
}

@test "the generated secrets are private and never printed" {
    run bash -c 'source "$DEV_SCRIPT"; ensure_secrets'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(stat -c %a "$SDWA5_DOLIBARR_DEV_DIR/db.env")" = 600 ]
    [ "$(stat -c %a "$SDWA5_DOLIBARR_DEV_DIR/app.env")" = 600 ]
    grep -q '^DOLI_INSTANCE_UNIQUE_ID=[0-9a-f]\{32\}$' "$SDWA5_DOLIBARR_DEV_DIR/app.env"
}

@test "the secrets are generated once and then kept" {
    bash -c 'source "$DEV_SCRIPT"; ensure_secrets'
    first="$(cat "$SDWA5_DOLIBARR_DEV_DIR/db.env")"
    bash -c 'source "$DEV_SCRIPT"; ensure_secrets'
    [ "$(cat "$SDWA5_DOLIBARR_DEV_DIR/db.env")" = "$first" ]
}

@test "the neutralising SQL disables mail and every scheduled job" {
    mkdir -p "$SDWA5_DOLIBARR_DEV_DIR/archive"
    printf 'database\tdolidb\n' > "$SDWA5_DOLIBARR_DEV_DIR/archive/manifest.tsv"
    stub docker "cat > '$BATS_TEST_TMPDIR/sql'"
    run bash -c 'source "$DEV_SCRIPT"; neutralise'
    [ "$status" -eq 0 ]
    grep -q "'MAIN_DISABLE_ALL_MAILS', 0, '1'" "$BATS_TEST_TMPDIR/sql"
    grep -q 'UPDATE llx_cronjob SET status = 0;' "$BATS_TEST_TMPDIR/sql"
}

@test "module mounts are built from name=path pairs" {
    mkdir "$BATS_TEST_TMPDIR/mod"
    run env SDWA5_DOLIBARR_DEV_MODULES="pmtools=$BATS_TEST_TMPDIR/mod" \
        bash -c 'source "$DEV_SCRIPT"; module_mounts | tr "\0" "\n"'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = '--mount' ]
    [ "${lines[1]}" = "type=bind,src=$BATS_TEST_TMPDIR/mod,dst=/var/www/html/custom/pmtools" ]
}

@test "a module name that could escape custom/ is refused" {
    mkdir "$BATS_TEST_TMPDIR/mod"
    run env SDWA5_DOLIBARR_DEV_MODULES="../x=$BATS_TEST_TMPDIR/mod" \
        bash -c 'source "$DEV_SCRIPT"; module_mounts'
    [ "$status" -ne 0 ]
}

@test "a missing module checkout is refused" {
    run env SDWA5_DOLIBARR_DEV_MODULES="pmtools=$BATS_TEST_TMPDIR/nowhere" \
        bash -c 'source "$DEV_SCRIPT"; module_mounts'
    [ "$status" -ne 0 ]
    [[ "$output" == *'no directory'* ]]
}

start_with_image() {
    mkdir -p "$SDWA5_DOLIBARR_DEV_DIR/documents" "$SDWA5_DOLIBARR_DEV_DIR/archive" "$BATS_TEST_TMPDIR/mod"
    printf 'database\tdolidb\n' > "$SDWA5_DOLIBARR_DEV_DIR/archive/manifest.tsv"
    touch "$SDWA5_DOLIBARR_DEV_DIR/documents/install.lock"
    stub docker "printf '%s\n' \"\$@\" >> '$BATS_TEST_TMPDIR/docker-args'"
    run env SDWA5_DOLIBARR_DEV_MODULES="m=$BATS_TEST_TMPDIR/mod" SDWA5_DOLIBARR_DEV_IMAGE="$1" \
        bash -c 'source "$DEV_SCRIPT"; start_application'
}

@test "the application starts with the image's own entrypoint" {
    start_with_image dolibarr/dolibarr:99.0.0
    [ "$status" -eq 0 ]
    ! grep -q 'sdwa5-dolibarr-entrypoint' "$BATS_TEST_TMPDIR/docker-args"
    grep -qx 'dolibarr/dolibarr:99.0.0' "$BATS_TEST_TMPDIR/docker-args"
}

@test "every start removes install.lock so the image can migrate" {
    start_with_image dolibarr/dolibarr:99.0.0
    [ ! -e "$SDWA5_DOLIBARR_DEV_DIR/documents/install.lock" ]
}
