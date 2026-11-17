#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
    export ENV_FILE="$BATS_TEST_TMPDIR/.env"
    cat > "$ENV_FILE" <<'ENV'
# comment
RESTIC_REPOSITORY=rclone:gdrive:sdwa5
DOLIBARR_MYSQL_PASSWORD=secret-1
VAULTWARDEN_ADMIN_TOKEN='$argon2id$v=19$x'
DOLIBARR_CRON_KEY=secret-2
PAPERLESS_HOME_SECRET_KEY=secret-3
MONITOR_SMTP_PASSWORD=smtp-login
QUOTED="two words"
ENV
    unset RESTIC_REPOSITORY DOLIBARR_MYSQL_PASSWORD VAULTWARDEN_ADMIN_TOKEN DOLIBARR_CRON_KEY \
        PAPERLESS_HOME_SECRET_KEY MONITOR_SMTP_PASSWORD QUOTED LOAD_ENV_SECRETS
}

# Prints the variables a script sees after load_env, one NAME=VALUE per line.
loaded() {
    run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; load_env; env | grep -E "^(RESTIC_REPOSITORY|DOLIBARR_[A-Z_]*|VAULTWARDEN_[A-Z_]*|PAPERLESS_[A-Z_]*|MONITOR_SMTP_PASSWORD|QUOTED)=" | sort'
}

@test "load_env exports plain keys and leaves secret-shaped ones out" {
    loaded
    [ "$status" -eq 0 ]
    [[ "$output" == *'RESTIC_REPOSITORY=rclone:gdrive:sdwa5'* ]]
    [[ "$output" == *'QUOTED=two words'* ]]
    [[ "$output" != *secret-* ]]
    [[ "$output" != *argon2id* ]]
}

@test "with every secret named, load_env exports them all, so the filter above is what drops them" {
    export LOAD_ENV_SECRETS='DOLIBARR_MYSQL_PASSWORD VAULTWARDEN_ADMIN_TOKEN DOLIBARR_CRON_KEY PAPERLESS_HOME_SECRET_KEY'
    loaded
    [[ "$output" == *'DOLIBARR_MYSQL_PASSWORD=secret-1'* ]]
    [[ "$output" == *'VAULTWARDEN_ADMIN_TOKEN=$argon2id$v=19$x'* ]]
    [[ "$output" == *'DOLIBARR_CRON_KEY=secret-2'* ]]
    [[ "$output" == *'PAPERLESS_HOME_SECRET_KEY=secret-3'* ]]
}

@test "load_env keeps the monitoring's own MONITOR_ keys, the SMTP password included" {
    loaded
    [[ "$output" == *'MONITOR_SMTP_PASSWORD=smtp-login'* ]]
}

@test "load_env exports a secret the caller names in LOAD_ENV_SECRETS, and only that one" {
    export LOAD_ENV_SECRETS='DOLIBARR_CRON_KEY'
    loaded
    [[ "$output" == *'DOLIBARR_CRON_KEY=secret-2'* ]]
    [[ "$output" != *secret-1* ]]
    [[ "$output" != *secret-3* ]]
}

@test "load_env does not override a key that is already set" {
    export RESTIC_REPOSITORY=from-env
    loaded
    [[ "$output" == *'RESTIC_REPOSITORY=from-env'* ]]
}

# --- sandbox helpers -------------------------------------------------------

sandbox_account() {
    export STUB_GETENT_GROUP='sandbox:x:998:chimodiazz'
    export STUB_GETENT_PASSWD='chimodiazz:x:1001:1001::/opt/docker/sandbox/chimodiazz:/usr/sbin/nologin'
    export STUB_SETPRIV_LOG="$BATS_TEST_TMPDIR/setpriv.log"
    : > "$STUB_SETPRIV_LOG"
}

@test "sandbox_members lists the group's members and nothing without the group" {
    sandbox_account
    run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; sandbox_members'
    [ "$output" = chimodiazz ]
    unset STUB_GETENT_GROUP
    run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; sandbox_members'
    [ -z "$output" ]
}

@test "as_sandbox switches to the account with its runtime dir, socket and home" {
    sandbox_account
    run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; as_sandbox chimodiazz /usr/bin/test -r /root'
    [ "$status" -eq 1 ]
    grep -qF -- '--reuid=chimodiazz --regid=chimodiazz --init-groups --inh-caps=-all --reset-env' "$STUB_SETPRIV_LOG"
    grep -qF -- 'env -C /opt/docker/sandbox/chimodiazz XDG_RUNTIME_DIR=/run/user/1001 DOCKER_HOST=unix:///run/user/1001/docker.sock /usr/bin/test' "$STUB_SETPRIV_LOG"
}

@test "as_sandbox refuses an unknown account without calling setpriv" {
    sandbox_account
    run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; as_sandbox nobody-here true'
    [ "$status" -eq 1 ]
    [ ! -s "$STUB_SETPRIV_LOG" ]
}

@test "open_private_paths lists ignored paths and .git open to others, and nothing else" {
    # Real git, not the stub: the listing is git's own ignore logic.
    local real_path="${PATH#"$BATS_TEST_DIRNAME/stubs:"}"
    local repo="$BATS_TEST_TMPDIR/compose"
    mkdir -p "$repo/tracked" "$repo/open-data" "$repo/closed-data" "$repo/sandbox/someone"
    PATH="$real_path" git -C "$repo" init -q
    printf '/open-data/\n/closed-data/\n/tracked/local.conf\n/sandbox/\n/link\n' > "$repo/.gitignore"
    printf 'x\n' > "$repo/tracked/README"
    printf 'x\n' > "$repo/tracked/local.conf"
    ln -s /etc "$repo/link"
    PATH="$real_path" git -C "$repo" add .gitignore tracked/README
    chmod 755 "$repo/.git" "$repo/open-data" "$repo/sandbox"
    chmod 700 "$repo/closed-data"
    chmod 644 "$repo/tracked/local.conf"
    PATH="$real_path" COMPOSE_DIR="$repo" run bash -c '. "$REPO_ROOT/monitoring/lib.sh"; open_private_paths; pwd'
    [ "$status" -eq 0 ]
    [[ "$output" == *$'.git\n'* ]]
    [[ "$output" == *$'open-data\n'* ]]
    [[ "$output" == *$'tracked/local.conf\n'* ]]
    [[ "$output" != *closed-data* ]]
    [[ "$output" != *sandbox* ]]
    [[ "$output" != *link* ]]
    # The subshell keeps the caller's working directory.
    [[ "${lines[-1]}" != "$repo" ]]
}
