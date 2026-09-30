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
#   VAULTWARDEN_DRIFT_GRACE_HOURS  how long an unapplied Vaultwarden release stays acceptable
#   FIREWALL_PORTS                 tcp ports the INPUT chain must still accept
#   STATE_DIR, FAKE_NOW            test hooks

set -uo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_env

DISK_WARN="${DISK_WARN:-85}"
DISK_CRIT="${DISK_CRIT:-92}"
EXPECTED_CONTAINERS="${EXPECTED_CONTAINERS:-vaultwarden shopware chimodiazz_shopware dolibarr dolibarr_db dolibarr_cron restic}"
HEALTH_URLS="${HEALTH_URLS:-vaultwarden=https://vault.sdwa5.org/alive shopware=https://sdwa5.org/ dolibarr=https://erp.sdwa5.org/ chimodiazz=https://chimodiazz.sdwa5.org/}"
BACKUP_MAX_AGE_HOURS="${BACKUP_MAX_AGE_HOURS:-26}"
DB_BACKUP_MAX_AGE_HOURS="${DB_BACKUP_MAX_AGE_HOURS:-26}"
# Shopware's shortest scheduled task interval is 60 seconds, so two hours is
# generous and still catches an outage the same morning. The one this check
# exists for ran unnoticed for 47 days.
SHOPWARE_TASK_MAX_AGE_HOURS="${SHOPWARE_TASK_MAX_AGE_HOURS:-2}"
VAULTWARDEN_RELEASE_API="${VAULTWARDEN_RELEASE_API:-https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest}"
# How long a new Vaultwarden release may sit unapplied before it is worth a mail.
#
# **THIS IS NOT A ROUND NUMBER, IT IS THE UPDATE JOB'S PERIOD PLUS SLACK.** vaultwarden-autoupdate.sh
# runs daily at 03:00 host time, so a release published just after 03:00 waits almost a full day by
# design. Warning before that window closes means mailing about every upstream release, which is what
# happened with 1.37.3 on 2026-09-13. Warning after it means a WARN says the updater is not working,
# which is the only version of this alert anybody can act on.
VAULTWARDEN_DRIFT_GRACE_HOURS="${VAULTWARDEN_DRIFT_GRACE_HOURS:-26}"
FIREWALL_PORTS="${FIREWALL_PORTS:-22 80 443}"

# **HOW OFTEN THE REMOTE IS ASKED, AND WHY IT IS NOT EVERY RUN.** This check costs an authenticated
# network round trip, and what it watches changes rarely. Hourly would be 24 calls a day for a fact
# that holds for months. Once a day is the cadence, measured from the last **successful** call, which
# is why the failure path deliberately does not stamp: while it is broken it is retried every run, so
# a recovery shows up within the hour instead of a day later.
# The checkout being watched. It is the compose root on this host, and it is its own knob because the
# two are the same thing only by convention.
GIT_CHECKOUT_DIR="${GIT_CHECKOUT_DIR:-$COMPOSE_DIR}"
GIT_REMOTE_MAX_AGE_HOURS="${GIT_REMOTE_MAX_AGE_HOURS:-26}"
GIT_REMOTE_TIMEOUT="${GIT_REMOTE_TIMEOUT:-20}"
GIT_REMOTE_STAMP="${GIT_REMOTE_STAMP:-$STATE_DIR/git-remote-ok}"

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

# Shopware's scheduled tasks stop silently. Nothing in the shop, the container
# or the logs says so, and the only visible symptoms are indirect: a sitemap that
# stops advancing, a cache that stops being invalidated, tables that stop being
# pruned. That is why this reads the task list itself rather than any symptom.
#
# The newest last-execution across all tasks is the measure. A single task can
# legitimately be far behind, because the intervals range from 60 seconds to a
# month, but if the newest of them is old then nothing is running at all.
check_shopware_tasks() {
    local list newest newest_ts age_hours

    list="$(docker exec shopware php bin/console scheduled-task:list 2>&1)" || {
        printf 'CRIT\tCannot read Shopware scheduled tasks: %s\n' "$(head -1 <<< "$list")"
        return
    }

    # The table's third column is the last execution, ISO 8601 with an offset,
    # so it sorts lexicographically and cannot be misread by the host timezone.
    #
    # The year is matched as four literal digit classes rather than as {4}.
    # **The host's awk is mawk, which does not honour interval expressions**,
    # measured 2026-09-08: `/^[0-9]{4}-/` matches nothing there while
    # `/^[0-9][0-9][0-9][0-9]-/` matches. The test suite cannot catch this,
    # because tests/run.sh runs bats in an Alpine container whose busybox awk
    # does support intervals, and this workstation has GNU awk. So three awks
    # are in play and only the host's decides. Stay inside POSIX here.
    newest="$(awk -F'|' 'NF>4 {gsub(/ /, "", $4); if ($4 ~ /^[0-9][0-9][0-9][0-9]-/) print $4}' <<< "$list" | sort | tail -1)"

    if [[ -z "$newest" ]]; then
        printf 'CRIT\tNo Shopware scheduled task has ever run\n'
        return
    fi

    newest_ts="$(date -d "$newest" +%s 2>/dev/null)"
    if [[ -z "$newest_ts" ]]; then
        printf 'CRIT\tCould not parse the newest Shopware task timestamp: %s\n' "$newest"
        return
    fi

    age_hours=$(( ($(now) - newest_ts) / 3600 ))

    if (( age_hours >= SHOPWARE_TASK_MAX_AGE_HOURS )); then
        printf 'CRIT\tShopware scheduled tasks last ran %sh ago (%s), expected within %sh. The worker is not running\n' \
            "$age_hours" "$newest" "$SHOPWARE_TASK_MAX_AGE_HOURS"
    else
        printf 'OK\tShopware scheduled tasks ran %sh ago (%s)\n' "$age_hours" "$newest"
    fi
}

check_backup() {
    local json newest newest_ts age_hours log last_result

    # Ask the repository, not the container log. Two bugs came from reading the
    # log, both found on 2026-09-08:
    #
    #   1. A container recreation wipes it, and an empty log is indistinguishable
    #      from a backup that never ran. Adding `init: true` to the restic
    #      service was enough to fire a CRIT on a perfectly healthy repository.
    #   2. The log prints its timestamps in the container's timezone, which is
    #      UTC because no TZ is set there, while `date -d` evaluated them on the
    #      host in Europe/Berlin. Every backup therefore read two hours older
    #      than it was, which against a 24-hour cycle and a 26-hour threshold
    #      left no slack at all and put a false CRIT window at exactly the hour
    #      the next run starts.
    #
    # `restic snapshots --json` fixes both. It is the authoritative answer to
    # "does a backup exist", and its timestamps are RFC3339 with an explicit
    # offset, so they cannot be misread by the host's timezone.
    json="$(docker exec restic restic snapshots --json 2>&1)" || {
        printf 'CRIT\tCannot query the restic repository: %s\n' "$(head -1 <<< "$json")"
        return
    }

    # Take the maximum rather than the last element, so this does not depend on
    # restic's ordering. An RFC3339 timestamp sorts lexicographically.
    newest="$(grep -oE '"time":"[^"]+"' <<< "$json" | cut -d'"' -f4 | sort | tail -1)"

    if [[ -z "$newest" ]]; then
        printf 'CRIT\tThe restic repository holds no snapshots at all\n'
        return
    fi

    newest_ts="$(date -d "$newest" +%s 2>/dev/null)"
    if [[ -z "$newest_ts" ]]; then
        printf 'CRIT\tCould not parse the newest restic snapshot timestamp: %s\n' "$newest"
        return
    fi

    age_hours=$(( ($(now) - newest_ts) / 3600 ))

    # The log is now only an early warning. It can say "the last attempt failed"
    # sooner than the age threshold would notice, but it can no longer raise an
    # alarm merely by being absent.
    log="$(docker logs --tail 400 restic 2>/dev/null || true)"
    last_result="$(grep -E '^(Backup|Restic) (Successful|Failed)' <<< "$log" | tail -1)"

    if (( age_hours >= BACKUP_MAX_AGE_HOURS )); then
        printf 'CRIT\tNewest restic snapshot is %sh old (%s), expected within %sh\n' "$age_hours" "$newest" "$BACKUP_MAX_AGE_HOURS"
    elif [[ "$last_result" == *Failed ]]; then
        printf 'CRIT\tLast restic run reported failure: %s (newest snapshot %sh old)\n' "$last_result" "$age_hours"
    else
        printf 'OK\tNewest restic snapshot %sh ago (%s)\n' "$age_hours" "$newest"
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
check_firewall() {
    local v4 v6 docker_user problems=() port

    # A missing binary is not a passing check. Without it nothing here can be
    # confirmed, and silence would read as healthy.
    if ! command -v iptables >/dev/null 2>&1; then
        printf 'CRIT\tiptables is not available, the firewall cannot be verified\n'
        return
    fi

    v4="$(iptables -S INPUT 2>/dev/null)"
    if [[ -z "$v4" ]]; then
        printf 'CRIT\tCould not read the INPUT chain, the firewall cannot be verified\n'
        return
    fi

    grep -q '^-P INPUT DROP' <<<"$v4" \
        || problems+=("IPv4 INPUT policy is not DROP, the host is unfiltered")

    # fail2ban inserts this jump at the head of INPUT. Anything that flushes the
    # chain removes it, and SSH is then unfiltered while the chain still looks
    # right, which is exactly the failure worth catching.
    grep -q 'j f2b-sshd' <<<"$v4" \
        || problems+=("fail2ban jump is missing from INPUT, ssh brute force is unfiltered")

    # A DROP policy without the service rules is an outage, not protection.
    for port in $FIREWALL_PORTS; do
        grep -qE -- "--dport $port( |\$)" <<<"$v4" \
            || problems+=("no INPUT rule accepts tcp $port")
    done

    # DOCKER-USER is where a published container port is filtered, because such a
    # packet is DNAT'd and traverses FORWARD rather than INPUT. An INPUT-only
    # firewall reads as healthy while every published port is wide open, which is
    # exactly what was true here until 2026-09-08. A chain that is only
    # `-j RETURN` is the empty default Docker ships.
    docker_user="$(iptables -S DOCKER-USER 2>/dev/null)"
    if [[ -z "$docker_user" ]]; then
        problems+=("the DOCKER-USER chain is missing, published container ports are unfiltered")
    elif ! grep -qE -- '-j DROP' <<<"$docker_user"; then
        problems+=("DOCKER-USER has no DROP rule, so it is back to Docker's empty default and published container ports are unfiltered")
    fi

    if (( ${#problems[@]} )); then
        printf 'CRIT\t%s\n' "$(IFS='; '; echo "${problems[*]}")"
        return
    fi

    # IPv6 is a warning rather than a critical. Nothing reaches this host over
    # IPv6 today and no AAAA record is published, so a missing v6 policy is a
    # gap that matters once that changes, not a live exposure.
    v6="$(ip6tables -S INPUT 2>/dev/null)"
    if ! grep -q '^-P INPUT DROP' <<<"$v6"; then
        printf 'WARN\tIPv4 firewall is up, IPv6 INPUT policy is not DROP\n'
        return
    fi

    printf 'OK\tINPUT DROP on both families, fail2ban jump present, DOCKER-USER filtering, %s accepted\n' \
        "$(tr ' ' ',' <<<"$FIREWALL_PORTS")"
}

# **A NEW RELEASE IS NOT A FAULT. AN UNAPPLIED ONE EVENTUALLY IS, AND THE DIFFERENCE IS TIME.**
#
# vaultwarden-autoupdate.sh applies a new image daily at 03:00, this check runs hourly. Without a
# grace window the detector beats the actor by up to a day on every single upstream release and mails
# about it. That is what happened with 1.37.3: published 2026-09-13 at 15:03 UTC, found here at 17:17
# local, and two mails had gone out before the updater was ever due again.
#
# So drift younger than VAULTWARDEN_DRIFT_GRACE_HOURS reports OK and names the wait, and drift older
# than it warns. A WARN from this check therefore means the update job is not doing its work, which is
# a statement somebody can act on, rather than "upstream has shipped", which is not.
check_vaultwarden_version() {
    local running response latest published published_ts age_hours newest

    # The container prints "Vaultwarden <server>" and "Web-Vault <web vault>".
    # Only the first is comparable against the GitHub release tag.
    running="$(docker exec vaultwarden /vaultwarden --version 2>/dev/null \
        | grep -oE '^Vaultwarden [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')"
    if [[ -z "$running" ]]; then
        printf 'WARN\tCould not determine the running Vaultwarden version\n'
        return
    fi

    # One request, read twice. The age of the release is in the same payload as its tag, so asking
    # GitHub a second time for it would only add a way for the two answers to disagree.
    response="$(curl -fsS --max-time 20 "$VAULTWARDEN_RELEASE_API" 2>/dev/null)"

    # Take the tag_name value itself. Scraping the response for anything
    # version-shaped also matches the release notes, and the 1.37.2 notes
    # mention 2026.8.0 and 1.37.1, which produced a multi-line result and a
    # false "1.37.2 is behind 1.37.2". Works on pretty and on compact JSON.
    latest="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([0-9][0-9.]*\)".*/\1/p' <<< "$response" \
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
        return
    fi

    # RFC3339 with an explicit Z, parsed with date rather than awk. The host's awk is mawk and the
    # bats container's is busybox, so anything date can do belongs to date here.
    published="$(sed -n 's/.*"published_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$response" \
        | head -1)"

    # **THE EMPTINESS IS TESTED BEFORE date SEES IT, BECAUSE GNU `date -d ""` SUCCEEDS.** It resolves
    # an empty string to today at 00:00, so a payload with no published_at would have produced a
    # timestamp a few hours old and reported every such release as comfortably inside the grace
    # window. Caught by `drift with no readable release date warns rather than being waved through`.
    published_ts=""
    if [[ -n "$published" ]]; then
        published_ts="$(date -u -d "$published" +%s 2>/dev/null)"
    fi

    # The drift itself is measured and only its age is unknown, so this warns rather than falling
    # silent. Same line the firewall check takes: a check that cannot see its subject has confirmed
    # nothing, and here it has already confirmed the part that matters.
    if [[ -z "$published_ts" ]]; then
        printf 'WARN\tVaultwarden %s is behind %s, and the release date could not be read so its age is unknown. Clients auto-update and will break against an old server\n' \
            "$running" "$latest"
        return
    fi

    age_hours=$(( ($(now) - published_ts) / 3600 ))

    if (( age_hours < VAULTWARDEN_DRIFT_GRACE_HOURS )); then
        printf 'OK\tVaultwarden %s is behind %s, released %sh ago. The daily update job takes it at 03:00\n' \
            "$running" "$latest" "$age_hours"
    else
        printf 'WARN\tVaultwarden %s is behind %s, released %sh ago and still not applied, so vaultwarden-autoupdate.sh is not working. Clients auto-update and will break against an old server\n' \
            "$running" "$latest" "$age_hours"
    fi
}

# ---------------------------------------------------------------------------
# Alert state and backoff
# ---------------------------------------------------------------------------

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

Checks: disk, containers, restic backup age, Shopware scheduled task age,
Vaultwarden database dump age, public HTTP endpoints, Caddy, Vaultwarden
version drift.

Environment overrides (also honoured from the compose .env): DISK_WARN,
DISK_CRIT, EXPECTED_CONTAINERS, HEALTH_URLS, BACKUP_MAX_AGE_HOURS,
DB_BACKUP_MAX_AGE_HOURS, SHOPWARE_TASK_MAX_AGE_HOURS, FIREWALL_PORTS,
STATE_DIR, FAKE_NOW.
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

# **THE CHECK THAT WOULD HAVE CAUGHT THE SEPTEMBER 2026 DEPLOY-KEY BREAKAGE.** A deploy key belongs to
# the repository object on GitHub, so recreating the repository destroys it, and the redaction passes
# of 2026-09-12, 2026-09-13 and 2026-09-15 each did exactly that. After every one of them /opt/docker
# could no longer pull, and **nothing here noticed for three cycles**, because none of the nine checks
# asked. It does not look broken from the outside either: a dead deploy key still authenticates and
# greets with the name of the repository it died with, so only a call that actually fetches says so.
#
# One call covers three failure modes at once, namely a destroyed or revoked key, a moved remote, and
# a host that cannot reach GitHub at all. See docs/ssh-hardening.md.
check_git_remote() {
    local last=0 age

    command -v git >/dev/null 2>&1 \
        || { printf 'WARN\tgit is not installed, so whether %s can pull is unknown\n' "$GIT_CHECKOUT_DIR"; return; }
    [[ -d "$GIT_CHECKOUT_DIR/.git" ]] \
        || { printf 'WARN\t%s is not a git checkout, so it cannot pull\n' "$GIT_CHECKOUT_DIR"; return; }

    [[ -f "$GIT_REMOTE_STAMP" ]] && last="$(stat -c %Y "$GIT_REMOTE_STAMP" 2>/dev/null || echo 0)"
    age=$(( ($(now) - last) / 3600 ))
    if (( last > 0 && age < GIT_REMOTE_MAX_AGE_HOURS )); then
        printf 'OK\t%s reached its remote %sh ago, asked again after %sh\n' \
            "$GIT_CHECKOUT_DIR" "$age" "$GIT_REMOTE_MAX_AGE_HOURS"
        return
    fi

    if timeout "$GIT_REMOTE_TIMEOUT" git -C "$GIT_CHECKOUT_DIR" ls-remote origin HEAD >/dev/null 2>&1; then
        mkdir -p "$STATE_DIR" 2>/dev/null
        : > "$GIT_REMOTE_STAMP"
        touch -d "@$(now)" "$GIT_REMOTE_STAMP" 2>/dev/null
        printf 'OK\t%s can reach its remote\n' "$GIT_CHECKOUT_DIR"
    else
        printf 'WARN\t%s cannot reach its remote, so it cannot pull. A destroyed deploy key still authenticates, so check whether ssh -T against the forge names the right repository\n' \
            "$GIT_CHECKOUT_DIR"
    fi
}

run_checks() {
    emit disk                  "$(check_disk)"
    emit containers            "$(check_containers)"
    emit backup                "$(check_backup)"
    emit shopware_tasks        "$(check_shopware_tasks)"
    emit vaultwarden_db_backup "$(check_vaultwarden_db_backup)"
    emit http                  "$(check_http)"
    emit caddy                 "$(check_caddy)"
    emit firewall              "$(check_firewall)"
    emit vaultwarden_version   "$(check_vaultwarden_version)"
    emit git_remote            "$(check_git_remote)"
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
            printf '%-21s %-5s %s\n' "$key" "$status" "$message"
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
    body+="$(printf '%s\n' "$results" | awk -F'\t' '{printf "  %-21s %-5s %s\n", $1, $2, $3}')"$'\n\n'
    body+="Runbooks: docs/maintenance.md and docs/monitoring.md in /opt/docker."$'\n'
    body+="Reminders for an unchanged problem back off: 1, 2, 4, 8, 16, then every 30 days."$'\n'

    send_mail "$subject" "$body" || log "$subject"$'\n'"$body"
}

main "$@"
