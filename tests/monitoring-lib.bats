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
