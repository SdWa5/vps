#!/usr/bin/env bash
#
# SdWa5 VPS health check.
#
# Runs hourly from /etc/cron.d/vps-health. Sends mail only when something is
# wrong or has just recovered. A healthy run is completely silent.
#
# Repeat reminders back off so an accepted, long-running condition does not mail
# every day forever. The interval doubles from one day and caps at 30 days, so
# reminders land 1, 2, 4, 8, 16 and 30 days in and monthly after that.
#
# Usage:
#   vps-health.sh              run the checks, mail on change
#   vps-health.sh --dry-run    print every check result, send nothing, touch nothing
#   vps-health.sh --test-mail  send one mail to every recipient and exit
#   vps-health.sh --help
#
# Environment overrides (also honoured from the compose .env):
#   DISK_WARN, DISK_CRIT           disk usage thresholds in percent
#   EXPECTED_CONTAINERS            space-separated container names
#   HEALTH_URLS                    space-separated "label=url" pairs
#   BACKUP_MAX_AGE_HOURS           age at which the restic backup counts as stale
#   DB_BACKUP_MAX_AGE_HOURS        age at which the Vaultwarden db dump counts as stale
#   STATE_DIR, FAKE_NOW            test hooks

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

DISK_WARN="${DISK_WARN:-85}"
DISK_CRIT="${DISK_CRIT:-92}"
EXPECTED_CONTAINERS="${EXPECTED_CONTAINERS:-vaultwarden shopware dolibarr dolibarr_db dolibarr_cron restic}"
HEALTH_URLS="${HEALTH_URLS:-vaultwarden=https://vault.sdwa5.org/alive shopware=https://sdwa5.org/ dolibarr=https://erp.sdwa5.org/}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"
DB_BACKUP_MAX_AGE_HOURS="${DB_BACKUP_MAX_AGE_HOURS:-26}"
VAULTWARDEN_RELEASE_API="${VAULTWARDEN_RELEASE_API:-https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest}"

STATE_FILE="$STATE_DIR/state"
DRY_RUN=0

# ---------------------------------------------------------------------------
# Checks
#
# Every check prints one line: STATUS<TAB>message. STATUS is OK, WARN or CRIT.
# ---------------------------------------------------------------------------

check_disk() {
    local usage avail
    usage="$(df -P / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
    avail="$(df -Ph / | awk 'NR==2 {print $4}')"

    if [[ -z "$usage" ]]; then
        printf 'CRIT\tCould not read disk usage for /\n'
    elif (( usage >= DISK_CRIT )); then
        printf 'CRIT\tDisk / at %s%%, only %s free (critical at %s%%)\n' "$usage" "$avail" "$DISK_CRIT"
    elif (( usage >= DISK_WARN )); then
        printf 'WARN\tDisk / at %s%%, %s free (warning at %s%%)\n' "$usage" "$avail" "$DISK_WARN"
    else
        printf 'OK\tDisk / at %s%%, %s free\n' "$usage" "$avail"
    fi
}

check_containers() {
    local name state problems=()

    for name in $EXPECTED_CONTAINERS; do
        state="$(docker inspect -f '{{.State.Running}} {{if .State.Health}}{{.State.Health.Status}}{{else}}nohealth{{end}}' "$name" 2>/dev/null)"
        case "$state" in
            "true healthy"|"true nohealth"|"true starting") ;;
            "") problems+=("$name: not found") ;;
            "false "*)                problems+=("$name: not running") ;;
            *)                        problems+=("$name: $state") ;;
        esac
    done

    if (( ${#problems[@]} == 0 )); then
        printf 'OK\tAll %s expected containers running\n' "$(wc -w <<< "$EXPECTED_CONTAINERS")"
    else
        printf 'CRIT\t%s\n' "$(IFS='; '; echo "${problems[*]}")"
    fi
}

check_backup() {
    local log last_result last_finish finish_ts age_hours
    log="$(docker logs --tail 400 restic 2>&1)" || {
        printf 'CRIT\tCannot read restic container logs\n'
        return
    }

    last_result="$(grep -E '^(Backup|Restic) (Successful|Failed)' <<< "$log" | tail -1)"
    last_finish="$(grep -oE 'Finished Backup at [0-9-]+ [0-9:]+' <<< "$log" | tail -1 | sed 's/^Finished Backup at //')"

    if [[ -z "$last_finish" ]]; then
        printf 'CRIT\tNo completed restic backup found in the last 400 log lines\n'
        return
    fi

    finish_ts="$(date -d "$last_finish" +%s 2>/dev/null)"
    if [[ -z "$finish_ts" ]]; then
        printf 'CRIT\tCould not parse restic backup timestamp: %s\n' "$last_finish"
        return
    fi

    age_hours=$(( ($(now) - finish_ts) / 3600 ))

    if [[ "$last_result" != *Successful ]]; then
        printf 'CRIT\tLast restic run did not succeed: %s (finished %s)\n' "${last_result:-no result line}" "$last_finish"
    elif (( age_hours >= BACKUP_MAX_AGE_HOURS )); then
        printf 'CRIT\tLast restic backup is %sh old (%s), expected within %sh\n' "$age_hours" "$last_finish" "$BACKUP_MAX_AGE_HOURS"
    else
        printf 'OK\tLast restic backup %sh ago (%s)\n' "$age_hours" "$last_finish"
    fi
}

# The restic check above only proves that a snapshot was taken. It says nothing
# about whether the Vaultwarden database inside it can be restored, because
# restic copies it hot. vaultwarden-db-backup.sh writes the consistent copy and
# is silent on success, so this is what notices when it stops running.
check_vaultwarden_db_backup() {
    local dump age_hours
    dump="${VAULTWARDEN_DB_BACKUP:-$COMPOSE_DIR/vaultwarden-db-backup/db.sqlite3}"

    if [[ ! -f "$dump" ]]; then
        printf 'CRIT\tNo consistent Vaultwarden database copy at %s, restores fall back to the hot file\n' "$dump"
        return
    fi

    age_hours=$(( ($(now) - $(stat -c %Y "$dump")) / 3600 ))

    if (( age_hours >= DB_BACKUP_MAX_AGE_HOURS )); then
        printf 'CRIT\tConsistent Vaultwarden database copy is %sh old, expected within %sh\n' "$age_hours" "$DB_BACKUP_MAX_AGE_HOURS"
    else
        printf 'OK\tConsistent Vaultwarden database copy %sh old (%s bytes)\n' "$age_hours" "$(stat -c %s "$dump")"
    fi
}

check_http() {
    local pair label url code problems=()

    for pair in $HEALTH_URLS; do
        label="${pair%%=*}"
        url="${pair#*=}"
        code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null)"
        [[ "$code" == "200" ]] || problems+=("$label ($url) returned ${code:-no response}")
    done

    if (( ${#problems[@]} == 0 )); then
        printf 'OK\tAll %s public endpoints return 200\n' "$(wc -w <<< "$HEALTH_URLS")"
    else
        printf 'CRIT\t%s\n' "$(IFS='; '; echo "${problems[*]}")"
    fi
}

check_caddy() {
    local state
    state="$(systemctl is-active caddy 2>/dev/null)"
    if [[ "$state" == "active" ]]; then
        printf 'OK\tCaddy is active\n'
    else
        printf 'CRIT\tCaddy is %s, every public site is down\n' "${state:-unknown}"
    fi
}

# The check that would have caught the September 2026 outage: Bitwarden clients
# auto-update from the stores, this server does not. A server left behind stops
# working with the extension and the mobile app while the web vault keeps going.
check_vaultwarden_version() {
    local running latest newest

    # The container prints "Vaultwarden <server>" and "Web-Vault <web vault>".
    # Only the first is comparable against the GitHub release tag.
    running="$(docker exec vaultwarden /vaultwarden --version 2>/dev/null \
        | grep -oE '^Vaultwarden [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')"
    if [[ -z "$running" ]]; then
        printf 'WARN\tCould not determine the running Vaultwarden version\n'
        return
    fi

    # Take the tag_name value itself. Scraping the response for anything
    # version-shaped also matches the release notes, and the 1.37.2 notes
    # mention 2026.8.0 and 1.37.1, which produced a multi-line result and a
    # false "1.37.2 is behind 1.37.2". Works on pretty and on compact JSON.
    latest="$(curl -fsS --max-time 20 "$VAULTWARDEN_RELEASE_API" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' \
        | head -1)"

    # Anything that is not a plain dotted version is treated as no answer.
    if [[ ! "$latest" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        latest=""
    fi

    # GitHub being unreachable is not a server fault. Stay quiet rather than
    # training the recipient to ignore this alert.
    if [[ -z "$latest" ]]; then
        printf 'OK\tVaultwarden %s running, latest release could not be checked\n' "$running"
        return
    fi

    newest="$(printf '%s\n%s\n' "$running" "$latest" | sort -V | tail -1)"
    if [[ "$running" == "$latest" || "$newest" == "$running" ]]; then
        printf 'OK\tVaultwarden %s is current (latest %s)\n' "$running" "$latest"
    else
        printf 'WARN\tVaultwarden %s is behind %s. Clients auto-update and will break against an old server\n' "$running" "$latest"
    fi
}

# ---------------------------------------------------------------------------
# Alert state and backoff
# ---------------------------------------------------------------------------

# Seconds to wait before reminder number N+1, given N reminders already sent.
# 1, 2, 4, 8, 16 days, then capped at 30.
backoff_seconds() {
    local sent="$1" days=1 i
    for (( i = 1; i < sent; i++ )); do
        days=$(( days * 2 ))
        (( days >= 30 )) && { days=30; break; }
    done
    echo $(( days * 86400 ))
}

# A short hash of the message, so a problem that changes shape (a second
# container dies) alerts again instead of waiting out the backoff.
fingerprint() {
    printf '%s' "$1" | md5sum | cut -c1-8
}

state_line() {
    local key="$1"
    [[ -r "$STATE_FILE" ]] || return 1
    awk -F'\t' -v k="$key" '$1 == k' "$STATE_FILE" 2>/dev/null | tail -1
}

state_drop() {
    local key="$1"
    [[ -r "$STATE_FILE" ]] || return 0
    awk -F'\t' -v k="$key" '$1 != k' "$STATE_FILE" > "$STATE_FILE.tmp" 2>/dev/null
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Remove state records whose key is absent from the given results.
prune_orphan_state() {
    local results="$1" keys
    [[ -s "$STATE_FILE" ]] || return 0
    keys="$(printf '%s\n' "$results" | cut -f1)"
    awk -F'\t' -v keep="$keys" '
        BEGIN { n = split(keep, a, "\n"); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
        $1 in ok
    ' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

state_put() {
    local key="$1" status="$2" fp="$3" first="$4" last="$5" count="$6"
    state_drop "$key"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$status" "$fp" "$first" "$last" "$count" >> "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

usage() {
    cat <<'USAGE'
vps-health.sh - SdWa5 VPS health check

Sends mail only when something is wrong or has just recovered. A healthy run is
completely silent. Repeat reminders for an unchanged problem back off: 1, 2, 4,
8, 16 days, then every 30 days.

  vps-health.sh              run the checks, mail on change
  vps-health.sh --dry-run    print every check result, send nothing, touch nothing
  vps-health.sh --test-mail  send one mail to every recipient and exit
  vps-health.sh --help       this text

Checks: disk, containers, restic backup age, Vaultwarden database dump age,
public HTTP endpoints, Caddy, Vaultwarden version drift.

Environment overrides (also honoured from the compose .env): DISK_WARN,
DISK_CRIT, EXPECTED_CONTAINERS, HEALTH_URLS, BACKUP_MAX_AGE_HOURS,
DB_BACKUP_MAX_AGE_HOURS, STATE_DIR, FAKE_NOW.
USAGE
}

# emit KEY CHECK-OUTPUT
#
# Normalises one check into exactly one "key<TAB>status<TAB>message" line.
#
# Without this a check that emits a newline turns every extra line into a
# phantom check with an empty status, which is then alerted on and written to
# the state file. That happened on 2026-09-02: a multi-line version string
# produced five phantom checks and an "8 problem(s)" mail.
emit() {
    local key="$1" out="$2" status message

    status="${out%%$'\t'*}"
    message="${out#*$'\t'}"
    message="$(printf '%s' "$message" | tr '\n\t' '  ' | sed 's/  */ /g; s/ *$//')"

    case "$status" in
        OK|WARN|CRIT) ;;
        *)
            message="malformed check output: ${status} ${message}"
            status="CRIT"
            ;;
    esac

    printf '%s\t%s\t%s\n' "$key" "$status" "$message"
}

run_checks() {
    emit disk                  "$(check_disk)"
    emit containers            "$(check_containers)"
    emit backup                "$(check_backup)"
    emit vaultwarden_db_backup "$(check_vaultwarden_db_backup)"
    emit http                  "$(check_http)"
    emit caddy                 "$(check_caddy)"
    emit vaultwarden_version   "$(check_vaultwarden_version)"
}

main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN=1 ;;
        --test-mail)
            if send_mail "[sdwa5] Monitoring test mail" \
                "This is a test from vps-health.sh on $(hostname) at $(date -R). If you can read it, alerting works."; then
                echo "Test mail sent to ${MONITOR_MAIL_TO}"
                exit 0
            fi
            echo "Test mail FAILED, see stderr" >&2
            exit 1
            ;;
        "") ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac

    mkdir -p "$STATE_DIR"
    touch "$STATE_FILE"

    local ts results
    ts="$(now)"
    results="$(run_checks)"

    if (( DRY_RUN )); then
        printf '%s\n' "$results" | while IFS=$'\t' read -r key status message; do
            printf '%-20s %-5s %s\n' "$key" "$status" "$message"
        done
        return 0
    fi

    local alerts=() recoveries=()
    local key status message fp line prev_status prev_fp first last count wait

    while IFS=$'\t' read -r key status message; do
        [[ -z "$key" ]] && continue
        fp="$(fingerprint "$message")"
        line="$(state_line "$key")"

        if [[ "$status" == "OK" ]]; then
            if [[ -n "$line" ]]; then
                recoveries+=("$key: $message")
                state_drop "$key"
            fi
            continue
        fi

        if [[ -z "$line" ]]; then
            alerts+=("[$status] $key: $message")
            state_put "$key" "$status" "$fp" "$ts" "$ts" 1
            continue
        fi

        IFS=$'\t' read -r _ prev_status prev_fp first last count <<< "$line"

        # A different problem, or an escalation, is news. Alert now and restart
        # the backoff from the beginning.
        if [[ "$status" != "$prev_status" || "$fp" != "$prev_fp" ]]; then
            alerts+=("[$status] $key: $message")
            state_put "$key" "$status" "$fp" "$first" "$ts" 1
            continue
        fi

        wait="$(backoff_seconds "$count")"
        if (( ts - last >= wait )); then
            alerts+=("[$status] $key: $message (unchanged since $(date -d "@$first" '+%Y-%m-%d %H:%M'), reminder $(( count + 1 )))")
            state_put "$key" "$status" "$fp" "$first" "$ts" $(( count + 1 ))
        else
            state_put "$key" "$status" "$fp" "$first" "$last" "$count"
        fi
    done <<< "$results"

    # Records for keys this run did not produce are stale, for example after a
    # check is renamed or removed, or after a malformed run wrote phantom keys.
    # Nothing else would ever clear them, because recovery is only detected for
    # keys that still appear in the results.
    prune_orphan_state "$results"

    date -d "@$ts" '+%Y-%m-%d %H:%M:%S' > "$LAST_RUN_FILE"

    (( ${#alerts[@]} + ${#recoveries[@]} == 0 )) && return 0

    local subject body
    if (( ${#alerts[@]} > 0 )); then
        subject="[sdwa5] ${#alerts[@]} problem(s) on $(hostname)"
    else
        subject="[sdwa5] recovered on $(hostname)"
    fi

    body=""
    (( ${#alerts[@]} > 0 ))     && body+="Problems:"$'\n'"$(printf '  %s\n' "${alerts[@]}")"$'\n\n'
    (( ${#recoveries[@]} > 0 )) && body+="Recovered:"$'\n'"$(printf '  %s\n' "${recoveries[@]}")"$'\n\n'
    body+="Full check output:"$'\n'
    body+="$(printf '%s\n' "$results" | awk -F'\t' '{printf "  %-20s %-5s %s\n", $1, $2, $3}')"$'\n\n'
    body+="Runbooks: docs/maintenance.md and docs/monitoring.md in /opt/docker."$'\n'
    body+="Reminders for an unchanged problem back off: 1, 2, 4, 8, 16, then every 30 days."$'\n'

    send_mail "$subject" "$body" || log "$subject"$'\n'"$body"
}

main "$@"
