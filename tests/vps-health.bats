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
    [[ "$output" == *"vaultwarden_db_backup"* ]]
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

@test "a missing Vaultwarden database dump is critical" {
    rm -f "$VAULTWARDEN_DB_BACKUP"
    health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"No consistent Vaultwarden database copy"* ]]
}

@test "a stale Vaultwarden database dump is critical" {
    touch -d '-30 hours' "$VAULTWARDEN_DB_BACKUP"
    health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"database copy is 30h old"* ]]
}

@test "a fresh Vaultwarden database dump is silent" {
    health
    [ "$(mail_count)" -eq 0 ]
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

# --- firewall -------------------------------------------------------------

@test "an ACCEPT policy on INPUT is critical" {
    STUB_IPT_V4='-P INPUT ACCEPT
-A INPUT -p tcp -m multiport --dports 22 -j f2b-sshd
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"IPv4 INPUT policy is not DROP"* ]]
}

@test "a missing fail2ban jump is critical even when the policy is DROP" {
    STUB_IPT_V4='-P INPUT DROP
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"fail2ban jump is missing"* ]]
}

@test "a DROP policy that no longer accepts a service port is critical" {
    STUB_IPT_V4='-P INPUT DROP
-A INPUT -p tcp -m multiport --dports 22 -j f2b-sshd
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"no INPUT rule accepts tcp 443"* ]]
}

@test "an unreadable INPUT chain is critical, not silently healthy" {
    STUB_IPT_V4='' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"Could not read the INPUT chain"* ]]
}

@test "an open IPv6 policy warns while IPv4 is still filtered" {
    STUB_IPT_V6='-P INPUT ACCEPT' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"IPv6 INPUT policy is not DROP"* ]]
}

@test "several firewall faults are reported together rather than one at a time" {
    STUB_IPT_V4='-P INPUT ACCEPT
-A INPUT -i lo -j ACCEPT' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"policy is not DROP"* ]]
    [[ "$(mail_body)" == *"fail2ban jump is missing"* ]]
    [[ "$(mail_body)" == *"no INPUT rule accepts tcp 22"* ]]
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

@test "the web vault version is not mistaken for the server version" {
    # The container prints both. Reading the wrong one hid drift completely:
    # 2026.7.0 sorts above every 1.x release, so an old server looked current.
    STUB_VW_VERSION=1.36.0 STUB_WEB_VAULT_VERSION=2026.7.0 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"1.36.0 is behind 1.37.2"* ]]
    [[ "$(mail_body)" != *"2026.7.0"* ]]
}

@test "the release notes are not mistaken for the release tag" {
    # Regression, 2026-09-02. The 1.37.2 notes mention 2026.8.0, 1.37.1 and
    # 1.37.0. Scraping the response for anything version-shaped returned all of
    # them, sort -V picked 2026.8.0, and a current server was reported as
    # "1.37.2 is behind 1.37.2" across seven lines.
    STUB_VW_VERSION=1.37.2 STUB_GITHUB_TAG=1.37.2 health
    [ "$(mail_count)" -eq 0 ]
}

@test "a v-prefixed release tag is understood" {
    STUB_VW_VERSION=1.36.0 STUB_GITHUB_TAG=v1.37.2 health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"1.36.0 is behind 1.37.2"* ]]
}

@test "a compact single-line release payload is parsed correctly" {
    STUB_VW_VERSION=1.37.2 \
    STUB_GITHUB_JSON='{"tag_name":"1.37.2","body":"required for clients v2026.8.0+, fixes 1.37.1"}' \
    STUB_GITHUB_TAG="" health
    [ "$(mail_count)" -eq 0 ]
}

@test "a nonsense release tag is treated as no answer, not as drift" {
    STUB_VW_VERSION=1.36.0 STUB_GITHUB_JSON='{"tag_name":"nightly"}' STUB_GITHUB_TAG="" health
    [ "$(mail_count)" -eq 0 ]
}

@test "a multi-line check message cannot become extra checks" {
    # Regression, 2026-09-02. Extra lines were parsed as further checks with an
    # empty status, alerted on, and written to the state file. One run produced
    # an "8 problem(s)" mail from a single failing check.
    STUB_CADDY_STATE=$'"'"'failed\ninjected\nlines'"'"' health
    [ "$(mail_count)" -eq 1 ]
    [[ "$(mail_body)" == *"1 problem(s)"* ]]
    run bash -c "wc -l < '$STATE_DIR/state'"
    [ "$output" -eq 1 ]
}

@test "stale state records are pruned" {
    mkdir -p "$STATE_DIR"
    printf 'phantom\tCRIT\tdeadbeef\t1\t1\t1\n' > "$STATE_DIR/state"
    health
    run grep -c phantom "$STATE_DIR/state"
    [ "$output" -eq 0 ]
}

@test "an unreachable GitHub API does not alert" {
    STUB_VW_VERSION=1.36.0 STUB_GITHUB_TAG="" STUB_GITHUB_JSON="" health
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
