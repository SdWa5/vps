#!/usr/bin/env bash
# Shared bats setup: put the stubs first on PATH and give every script an
# isolated state directory, so no test touches the real host.

common_setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"

    export STATE_DIR="$BATS_TEST_TMPDIR/state"
    export ENV_FILE=/dev/null
    export MONITOR_SMTP_PASSWORD=dummy
    export MONITOR_MAIL_TO="alerts@example.com"
    export STUB_MAIL_LOG="$BATS_TEST_TMPDIR/mail.log"
    : > "$STUB_MAIL_LOG"

    # Healthy defaults. Individual tests break exactly one of them.
    export STUB_DISK_PCT=30
    export STUB_HTTP_CODE=200
    export STUB_CADDY_STATE=active
    export STUB_VW_VERSION=1.37.2
    export STUB_GITHUB_TAG=1.37.2
    set_backup_fresh
    set_db_backup_fresh
    set_firewall_healthy
}

# A healthy INPUT chain as the firewall check expects to find it: DROP policy,
# the fail2ban jump at the head, and an accept rule per service port.
set_firewall_healthy() {
    export STUB_IPT_V4='-P INPUT DROP
-A INPUT -p tcp -m multiport --dports 22 -j f2b-sshd
-A INPUT -i lo -j ACCEPT
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A INPUT -p udp -m udp --dport 443 -j ACCEPT'
    export STUB_IPT_V6='-P INPUT DROP
-A INPUT -p ipv6-icmp -j ACCEPT'
}

# vps-health.sh reads the age of the consistent database copy off the file's
# mtime, so the fixture has to move with FAKE_NOW just like the restic log does.
set_db_backup_fresh() {
    local ref
    ref="${FAKE_NOW:-$(date +%s)}"
    export VAULTWARDEN_DB_BACKUP="$BATS_TEST_TMPDIR/vaultwarden-db-backup/db.sqlite3"
    mkdir -p "$(dirname "$VAULTWARDEN_DB_BACKUP")"
    printf 'SQLite format 3' > "$VAULTWARDEN_DB_BACKUP"
    touch -d "@$(( ref - 3600 ))" "$VAULTWARDEN_DB_BACKUP"
}

# The backup check compares against now(), which honours FAKE_NOW, so the fake
# restic log has to move with the fake clock.
set_backup_fresh() {
    local ref started finished
    ref="${FAKE_NOW:-$(date +%s)}"
    started="$(date -d "@$(( ref - 3660 ))" '+%Y-%m-%d %H:%M:%S')"
    finished="$(date -d "@$(( ref - 3600 ))" '+%Y-%m-%d %H:%M:%S')"
    export STUB_RESTIC_LOG="Starting Backup at $started
Backup Successful
Finished Backup at $finished after 47 seconds"
}

health() {
    run "$REPO_ROOT/monitoring/vps-health.sh" "$@"
}

# Run a check at a faked point in time. The restic log has to move with the
# clock, otherwise the backup check reports a different age on every run and its
# changed fingerprint triggers an alert that the backoff test did not ask for.
health_at() {
    export FAKE_NOW="$1"
    shift
    set_backup_fresh
    set_db_backup_fresh
    health "$@"
}

autoupdate() {
    run "$REPO_ROOT/monitoring/vaultwarden-autoupdate.sh" "$@"
}

db_backup() {
    run "$REPO_ROOT/monitoring/vaultwarden-db-backup.sh" "$@"
}

mail_count() {
    [[ -f "$STUB_MAIL_LOG" ]] || { echo 0; return; }
    # grep -c prints 0 and exits 1 when nothing matches, which is not an error here.
    grep -c '^=== MAIL ===' "$STUB_MAIL_LOG" || true
}

mail_body() {
    cat "$STUB_MAIL_LOG"
}
