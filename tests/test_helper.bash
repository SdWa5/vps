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
    set_shopware_tasks_fresh
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
    # DOCKER-USER as sdwa5-firewall.sh leaves it. The DROP is what the check
    # looks for, because a chain holding only `-j RETURN` is Docker's empty
    # default and filters nothing.
    export STUB_IPT_DOCKER_USER='-N DOCKER-USER
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i docker0 -j RETURN
-A DOCKER-USER -i eth0 -p tcp -m tcp --dport 25565 -j RETURN
-A DOCKER-USER -i eth0 -j DROP
-A DOCKER-USER -j RETURN'
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
# snapshot list has to move with the fake clock.
#
# The timestamp is deliberately written in **UTC** while the tests run in
# whatever zone the host is in. That is the shape of the bug this replaced: the
# old check read a UTC log timestamp with a local `date -d` and every backup
# came out two hours older than it was. An RFC3339 timestamp with an explicit
# offset cannot be misread that way, and a fixture in a foreign zone is what
# proves it.
set_backup_fresh() {
    local ref snapshots
    ref="${FAKE_NOW:-$(date +%s)}"
    snapshots="$(restic_snapshots_json "$(( ref - 3600 ))")"
    export STUB_RESTIC_SNAPSHOTS="$snapshots"

    # The log is now only an early warning for an explicit failure, so the
    # default fixture is a plain successful run.
    local started finished
    started="$(date -u -d "@$(( ref - 3660 ))" '+%Y-%m-%d %H:%M:%S')"
    finished="$(date -u -d "@$(( ref - 3600 ))" '+%Y-%m-%d %H:%M:%S')"
    export STUB_RESTIC_LOG="Starting Backup at $started
Backup Successful
Finished Backup at $finished after 47 seconds"
}

# Shopware's scheduled tasks last ran the given number of hours ago.
#
# The check reads the newest last-execution across every task, because the
# intervals range from 60 seconds to a month and a single old task proves
# nothing. So the fixture carries a spread: one task at the given age and two
# deliberately older, which is what a healthy list looks like.
set_shopware_tasks() {
    local hours_ago="${1:-1}" ref newest older oldest
    ref="${FAKE_NOW:-$(date +%s)}"
    newest="$(date -u -d "@$(( ref - hours_ago * 3600 ))" '+%Y-%m-%dT%H:%M:%S+00:00')"
    older="$(date -u -d "@$(( ref - (hours_ago + 24) * 3600 ))" '+%Y-%m-%dT%H:%M:%S+00:00')"
    oldest="$(date -u -d "@$(( ref - (hours_ago + 700) * 3600 ))" '+%Y-%m-%dT%H:%M:%S+00:00')"

    export STUB_SHOPWARE_TASKS="+------------------+---------------------------+---------------------------+--------------+-----------+
| Name             | Next execution            | Last execution            | Run interval | Status    |
+------------------+---------------------------+---------------------------+--------------+-----------+
| log_entry.cleanup | $older                   | $older                    | 86400        | scheduled |
| shopware.invalidate_cache | $newest          | $newest                   | 300          | scheduled |
| app.system_heartbeat | $oldest               | $oldest                   | 604800       | scheduled |
| shopware.elasticsearch.create.alias | $newest | -                       | 300          | skipped   |
+------------------+---------------------------+---------------------------+--------------+-----------+"
}

set_shopware_tasks_fresh() {
    set_shopware_tasks 1
}

# A restic `snapshots --json` array, newest last, for the epoch seconds given.
# Emits UTC with a `Z` offset, exactly as restic does.
restic_snapshots_json() {
    local out='[' first=1 ts
    for ts in "$@"; do
        [[ $first -eq 1 ]] || out+=','
        first=0
        out+="{\"time\":\"$(date -u -d "@$ts" '+%Y-%m-%dT%H:%M:%S.000000000Z')\""
        out+=',"tree":"deadbeef","paths":["/data"],"hostname":"testhost"'
        out+=',"username":"root","id":"abcdef0123456789","short_id":"abcdef01"}'
    done
    printf '%s]\n' "$out"
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
    set_shopware_tasks_fresh
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
