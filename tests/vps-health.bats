#!/usr/bin/env bats
# Tests for monitoring/vps-health.sh

load test_helper

setup() {
    common_setup
}

# --- silence when healthy -------------------------------------------------

@test "an all-green run sends no mail at all" {
    health
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 0 ]
}

@test "an all-green run still records that it ran" {
    health
    [ -f "$STATE_DIR/last-run" ]
}

@test "dry run prints every check and sends nothing" {
    health --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk"* ]]
    [[ "$output" == *"containers"* ]]
    [[ "$output" == *"backup"* ]]
    [[ "$output" == *"http"* ]]
    [[ "$output" == *"caddy"* ]]
    [[ "$output" == *"vaultwarden_version"* ]]
    [ "$(mail_count)" -eq 0 ]
}

@test "dry run writes no state" {
    health --dry-run
    [ ! -f "$STATE_DIR/last-run" ]
}

# --- individual checks ----------------------------------------------------

@test "disk below the warning threshold stays quiet" {
    STUB_DISK_PCT=84 health
    [ "$(mail_count)" -eq 0 ]
}

@test "disk at the warning threshold alerts as WARN" {
    STUB_DISK_PCT=85 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"[WARN] disk"* ]]
}

@test "disk at the critical threshold alerts as CRIT" {
    STUB_DISK_PCT=92 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"[CRIT] disk"* ]]
}

@test "thresholds are overridable, which is how an alert is rehearsed" {
    DISK_WARN=1 health --dry-run
    [[ "$output" == *"disk"*"WARN"* ]]
}

@test "a missing container is critical and names it" {
    STUB_CONTAINER_shopware="" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"shopware"* ]]
}

@test "a stopped container is critical" {
    STUB_CONTAINER_dolibarr_db="false nohealth" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"dolibarr_db: not running"* ]]
}

@test "an unhealthy container is critical" {
    STUB_CONTAINER_vaultwarden="true unhealthy" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"vaultwarden: true unhealthy"* ]]
}

@test "a container still starting up is not an alert" {
    STUB_CONTAINER_vaultwarden="true starting" health
    [ "$(mail_count)" -eq 0 ]
}

@test "a stale restic backup is critical" {
    STUB_RESTIC_LOG="Backup Successful
Finished Backup at $(date -d '-30 hours' '+%Y-%m-%d %H:%M:%S') after 47 seconds" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"restic backup is 30h old"* ]]
}

@test "a failed restic run is critical even when it is recent" {
    STUB_RESTIC_LOG="Backup Failed
Finished Backup at $(date '+%Y-%m-%d %H:%M:%S') after 3 seconds" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"did not succeed"* ]]
}

@test "a non-200 public endpoint is critical" {
    STUB_HTTP_CODE=502 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"502"* ]]
}

@test "an inactive Caddy is critical" {
    STUB_CADDY_STATE=failed health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"Caddy is failed"* ]]
}

# --- version drift, the check that would have caught this outage ----------

@test "a Vaultwarden behind the latest release warns" {
    STUB_VW_VERSION=1.36.0 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"1.36.0 is behind 1.37.2"* ]]
}

@test "a Vaultwarden newer than the latest release is fine" {
    STUB_VW_VERSION=1.38.0 health
    [ "$(mail_count)" -eq 0 ]
}

@test "an unreachable GitHub API does not alert" {
    STUB_VW_VERSION=1.36.0 STUB_GITHUB_JSON="" health
    [ "$(mail_count)" -eq 0 ]
}

@test "an unreadable Vaultwarden version warns rather than staying silent" {
    STUB_VW_VERSION="" health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"Could not determine the running Vaultwarden version"* ]]
}

# --- backoff --------------------------------------------------------------

@test "a repeat within the first day sends no reminder" {
    local t0=1800000000
    export STUB_DISK_PCT=95
    health_at $t0
    health_at $((t0 + 43200))
    [ "$(mail_count)" -eq 1 ]
}

@test "reminders land at 1, 2, 4, 8 and 16 days and cap at 30" {
    local t0=1800000000 offset
    export STUB_DISK_PCT=95
    # Notification times follow from the doubling intervals: 1, 2, 4, 8, 16, 30 days.
    for offset in 0 86400 259200 604800 1296000 2678400 5270400; do
        health_at $((t0 + offset))
    done
    [ "$(mail_count)" -eq 7 ]
}

@test "the interval never grows past 30 days" {
    local t0=1800000000 offset
    export STUB_DISK_PCT=95
    # Initial alert plus five reminders at 1, 2, 4, 8 and 16 day intervals.
    for offset in 0 86400 259200 604800 1296000 2678400; do
        health_at $((t0 + offset))
    done
    [ "$(mail_count)" -eq 6 ]
    # The next interval would double to 32 days. It must cap at 30.
    health_at $((t0 + 2678400 + 2591000))   # 29.99 days later, still quiet
    [ "$(mail_count)" -eq 6 ]
    health_at $((t0 + 2678400 + 2592000))   # exactly 30 days
    [ "$(mail_count)" -eq 7 ]
}

@test "a problem that changes shape alerts immediately, without waiting out the backoff" {
    STUB_DISK_PCT=95 health
    [ "$(mail_count)" -eq 1 ]
    STUB_DISK_PCT=96 health
    [ "$(mail_count)" -eq 2 ]
}

@test "an escalation from WARN to CRIT alerts immediately" {
    STUB_DISK_PCT=86 health
    STUB_DISK_PCT=93 health
    [ "$(mail_count)" -eq 2 ]
    [[ "$(mail_body)" == *"[CRIT] disk"* ]]
}

# --- recovery -------------------------------------------------------------

@test "recovery sends exactly one mail and then goes quiet" {
    STUB_DISK_PCT=95 health
    health
    [ "$(mail_count)" -eq 2 ]
    [[ "$(mail_body)" == *"Recovered:"* ]]
    health
    [ "$(mail_count)" -eq 2 ]
}

@test "a fault that returns after recovery alerts at once" {
    local t0=1800000000
    STUB_DISK_PCT=95 health_at $t0
    STUB_DISK_PCT=30 health_at $((t0 + 3600))     # recovered
    STUB_DISK_PCT=95 health_at $((t0 + 7200))     # back again
    [ "$(mail_count)" -eq 3 ]
}

# --- mail plumbing --------------------------------------------------------

@test "test mail goes out on demand" {
    health --test-mail
    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"Monitoring test mail"* ]]
}

@test "a missing SMTP password fails loudly instead of silently dropping the alert" {
    MONITOR_SMTP_PASSWORD="" health --test-mail
    [ "$status" -eq 1 ]
    [ "$(mail_count)" -eq 0 ]
}

@test "an unknown option is rejected" {
    health --nonsense
    [ "$status" -eq 2 ]
}
