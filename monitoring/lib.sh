#!/usr/bin/env bash
# Shared helpers for the SdWa5 VPS monitoring scripts.
#
# Sourced by vps-health.sh and vaultwarden-autoupdate.sh. Provides configuration
# loading and mail delivery. Not executable on its own.

# Directory this library lives in, so callers can be invoked from anywhere.
MONITORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compose project root. The live deployment is /opt/docker, which is also a git
# checkout of this repository, so monitoring/ sits directly inside it.
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$MONITORING_DIR")}"

# DOCKER_COMPOSE: `docker compose` where the v2 plugin exists, else `docker-compose`.
# shellcheck source=tools/compose.sh
. "$MONITORING_DIR/../tools/compose.sh"

# State shared between the two scripts. vps-health.sh touches last-run on every
# run; vaultwarden-autoupdate.sh reads it to detect that health checks stopped.
STATE_DIR="${STATE_DIR:-/var/lib/vps-health}"
# Read by both sourcing scripts, not by this library.
# shellcheck disable=SC2034
LAST_RUN_FILE="$STATE_DIR/last-run"

# Current time as a unix timestamp. Overridable so tests can drive the backoff
# schedule without waiting days.
now() {
    echo "${FAKE_NOW:-$(date +%s)}"
}

# Seconds to wait before reminder number N+1, given N reminders already sent.
# 1, 2, 4, 8, 16 days, then capped at 30. Shared by vps-health.sh and
# chimodiazz-deploy.sh, so both back off on the same schedule.
backoff_seconds() {
    local sent="$1" days=1 i
    for (( i = 1; i < sent; i++ )); do
        days=$(( days * 2 ))
        (( days >= 30 )) && { days=30; break; }
    done
    echo $(( days * 86400 ))
}

# Log to stderr with a timestamp. stdout stays reserved for check results.
log() {
    printf '[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# Read KEY=VALUE pairs from the compose .env without executing it. Only keys
# that are not already set in the environment are taken, so tests and manual
# runs can override anything.
#
# Secret-shaped keys (see env_key_is_secret) are skipped, because every key
# taken here is exported into the script and each child it starts, and none of
# the monitoring scripts needs the stack's passwords. MONITOR_* keys are this
# suite's own configuration and always load, MONITOR_SMTP_PASSWORD included. A
# caller that needs another secret names it in LOAD_ENV_SECRETS, separated by
# spaces.
load_env() {
    local env_file="${ENV_FILE:-$COMPOSE_DIR/.env}"
    [[ -r "$env_file" ]] || return 0

    local line key value
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" != *=* ]] && continue

        key="${line%%=*}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        [[ -n "${!key:-}" ]] && continue
        if [[ "$key" != MONITOR_* && " ${LOAD_ENV_SECRETS:-} " != *" $key "* ]] \
            && env_key_is_secret "$key"; then
            continue
        fi

        value="${line#*=}"
        # Strip one layer of matching quotes, as docker-compose does.
        if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
            value="${value:1:${#value}-2}"
        fi
        printf -v "$key" '%s' "$value"
        export "${key?}"
    done < "$env_file"
}

# True for a variable name that by convention holds a credential. The same
# rule names the keys security-recheck.sh looks for in container environments.
env_key_is_secret() {
    [[ "$1" == *PASS* || "$1" == *TOKEN* || "$1" == *SECRET* || "$1" == *_KEY ]]
}

# Mail configuration. The default is the Workspace SMTP relay, which accepts
# mail from this host's addresses without a login and requires TLS.
mail_defaults() {
    MONITOR_SMTP_HOST="${MONITOR_SMTP_HOST:-smtp-relay.gmail.com}"
    MONITOR_SMTP_PORT="${MONITOR_SMTP_PORT:-587}"
    MONITOR_SMTP_USER="${MONITOR_SMTP_USER:-ripper@sdwa5.org}"
    MONITOR_SMTP_FROM="${MONITOR_SMTP_FROM:-$MONITOR_SMTP_USER}"
    MONITOR_MAIL_TO="${MONITOR_MAIL_TO:-ripper@sdwa5.org}"
    MONITOR_SMTP_PASSWORD="${MONITOR_SMTP_PASSWORD:-}"
}

# send_mail SUBJECT BODY
#
# Delivers one mail to every address in MONITOR_MAIL_TO. Returns non-zero if
# curl fails, so callers can fall back to logging.
#
# Port 465 uses implicit TLS, every other port STARTTLS, and both refuse to send
# unencrypted. A login is sent only when MONITOR_SMTP_PASSWORD is set. The
# password then travels to curl through a config file on stdin rather than as an
# argument, so it never appears in the process list.
send_mail() {
    local subject="$1" body="$2"

    mail_defaults

    local msg rcpt_args=()
    msg="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$msg'" RETURN

    local addr
    for addr in $MONITOR_MAIL_TO; do
        rcpt_args+=(--mail-rcpt "$addr")
    done

    {
        printf 'From: SdWa5 VPS Monitor <%s>\n' "$MONITOR_SMTP_FROM"
        printf 'To: %s\n' "${MONITOR_MAIL_TO// /, }"
        printf 'Subject: %s\n' "$subject"
        printf 'Date: %s\n' "$(date -R)"
        printf 'MIME-Version: 1.0\n'
        printf 'Content-Type: text/plain; charset=UTF-8\n'
        printf '\n%s\n' "$body"
    } > "$msg"

    local scheme=smtp
    [[ "$MONITOR_SMTP_PORT" == 465 ]] && scheme=smtps

    if [[ -n "$MONITOR_SMTP_PASSWORD" ]]; then
        printf 'user = "%s:%s"\n' "$MONITOR_SMTP_USER" "$MONITOR_SMTP_PASSWORD"
    fi | curl --silent --show-error --config - \
        --ssl-reqd \
        --max-time 60 \
        --url "${scheme}://${MONITOR_SMTP_HOST}:${MONITOR_SMTP_PORT}" \
        --mail-from "$MONITOR_SMTP_FROM" \
        "${rcpt_args[@]}" \
        --upload-file "$msg"
}
