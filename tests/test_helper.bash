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
    set_git_remote_reachable
}

# The checkout the git_remote check watches. It is a tmpdir rather than the real repository root, so
# the test never depends on whether the mounted working copy happens to carry a .git directory.
set_git_remote_reachable() {
    export GIT_CHECKOUT_DIR="$BATS_TEST_TMPDIR/checkout"
    mkdir -p "$GIT_CHECKOUT_DIR/.git"
    export STUB_GIT_LSREMOTE_RC=0
    export STUB_GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    : > "$STUB_GIT_LOG"
}

# How often the remote was actually asked. The cadence is the point of that check, so the assertion
# is the number of calls rather than the status it reported.
git_call_count() {
    [[ -f "${STUB_GIT_LOG:-}" ]] || { echo 0; return; }
    grep -c 'ls-remote' "$STUB_GIT_LOG" || true
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

# An RFC3339 UTC timestamp with a Z offset, as the GitHub release API emits one. Used to place a
# fake release relative to a fake clock, so a drift test says how old the release is rather than
# which date it carries.
iso_utc() {
    date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'
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
    # set_git_remote_reachable is deliberately NOT called here. It truncates the call log and the
    # cadence tests move the clock across several runs to count the calls.
    health "$@"
}

autoupdate() {
    run "$REPO_ROOT/monitoring/vaultwarden-autoupdate.sh" "$@"
}

# chimodiazz-deploy.sh against a faked checkout. The default state is the
# ordinary run: the remote commit equals the local one, so there is nothing to
# deploy. A test that wants a deployment calls chimo_new_commit.
chimo_deploy_setup() {
    export SRC_DIR="$BATS_TEST_TMPDIR/chimodiazz-src"
    mkdir -p "$SRC_DIR/.git"
    export STUB_GIT_LOG="$BATS_TEST_TMPDIR/chimo-git.log"
    : > "$STUB_GIT_LOG"
    export STUB_GIT_BRANCH=main
    export STUB_GIT_LOCAL=1111111111111111111111111111111111111111
    export STUB_GIT_REMOTE=1111111111111111111111111111111111111111
    export STUB_DOCKER_LOG="$BATS_TEST_TMPDIR/chimo-docker.log"
    : > "$STUB_DOCKER_LOG"
    # The script locks itself now, so the lock has to live where the test can
    # write. /run/lock is not writable in the bats container.
    export LOCK_FILE="$BATS_TEST_TMPDIR/chimo-deploy.lock"
    # Short, because the failure path waits this out. The happy path never
    # reaches the loop's sleep: the stubbed curl answers 200 on the first call.
    export HEALTH_TIMEOUT=5
}

chimo_new_commit() {
    export STUB_GIT_REMOTE=2222222222222222222222222222222222222222
}

chimo_deploy() {
    run "$REPO_ROOT/monitoring/chimodiazz-deploy.sh" "$@"
}

# Which git subcommands the run actually issued. A reset is the signature of a
# deployment, so its absence is how "nothing to do" is asserted.
chimo_git_calls() {
    cat "$STUB_GIT_LOG"
}

chimo_docker_calls() {
    cat "$STUB_DOCKER_LOG"
}

# A commit that changed nothing the container reads. The path filter is supposed
# to move the checkout and leave the storefront alone.
chimo_docs_only_commit() {
    chimo_new_commit
    export STUB_GIT_DIFF_FILES="README.md docs/90-inbetriebnahme.md"
}

db_backup() {
    run "$REPO_ROOT/monitoring/vaultwarden-db-backup.sh" "$@"
}

# tools/dolibarr/doli.sh against the faked API. The key file is a fixture, so no
# test ever touches the real one under ~/.config.
doli_setup() {
    export DOLIBARR_URL="https://erp.example.org"
    export DOLIBARR_TOKEN_FILE="$BATS_TEST_TMPDIR/dolibarr-token"
    printf 'fake-api-key-0123456789' > "$DOLIBARR_TOKEN_FILE"
    chmod 600 "$DOLIBARR_TOKEN_FILE"
    export STUB_DOLI_CONFIG="$BATS_TEST_TMPDIR/doli-config"
    export STUB_DOLI_ARGS="$BATS_TEST_TMPDIR/doli-args"
}

doli() {
    run "$REPO_ROOT/tools/dolibarr/doli.sh" "$@"
}

# tools/dolibarr/set-address.sh against the faked ERP. Fixtures carry the old
# address, so the default run is the one that has work to do.
doli_address_setup() {
    doli_setup
    export STUB_DOLI_DIR="$BATS_TEST_TMPDIR/doli"
    export STUB_DOLI_LOG="$BATS_TEST_TMPDIR/doli.log"
    mkdir -p "$STUB_DOLI_DIR"
    : > "$STUB_DOLI_LOG"

    # **THE REAL RECORD LIST IS GITIGNORED BECAUSE IT NAMES PEOPLE**, so the tests
    # bring their own. These placeholders exercise the same three shapes: two
    # person records that need street, postcode and town, and one that needs its
    # town alone.
    export DOLIBARR_ADDRESS_RECORDS="$BATS_TEST_TMPDIR/address-records.json"
    cat > "$DOLIBARR_ADDRESS_RECORDS" <<'RECORDS'
[
  { "endpoint": "members",      "id": "2",  "expect": "Example",          "label": "member Ada Example" },
  { "endpoint": "users",        "id": "2",  "expect": "Example",          "label": "user Ada Example" },
  { "endpoint": "thirdparties", "id": "10", "expect": "Example Supplies", "label": "thirdparty Example Supplies", "town_only": 1 }
]
RECORDS

    doli_fixture members_2 "$(jq -n '{id:"2",lastname:"Example",firstname:"Ada",address:"Mühlenstraße 24",zip:"5121",town:"Ostermiething"}')"
    doli_fixture users_2   "$(jq -n '{id:"2",lastname:"Example",firstname:"Ada",address:"Mühlenstraße 24",zip:"5121",town:"Ostermiething"}')"
    doli_fixture thirdparties_10 "$(jq -n '{id:"10",name:"Example Supplies",address:"Egitlweg 6",zip:"5322",town:"Elsenwang"}')"
}

doli_fixture() {
    printf '%s' "$2" > "$STUB_DOLI_DIR/$1"
}

doli_set_address() {
    run "$REPO_ROOT/tools/dolibarr/set-address.sh" "$@"
}

doli_requests() {
    cat "$STUB_DOLI_LOG"
}

doli_put_count() {
    grep -c '^PUT ' "$STUB_DOLI_LOG" || true
}

# tools/dolibarr/sync-pm.sh against the faked ERP. The ERP starts with the two
# projects the real one has and no tasks at all, which is the state measured on
# 2026-09-14, and the spec is a file under the test's own tmpdir.
doli_pm_setup() {
    doli_setup
    export STUB_DOLI_DIR="$BATS_TEST_TMPDIR/doli"
    export STUB_DOLI_LOG="$BATS_TEST_TMPDIR/doli.log"
    mkdir -p "$STUB_DOLI_DIR"
    : > "$STUB_DOLI_LOG"

    export DOLIBARR_PM_SPEC="$BATS_TEST_TMPDIR/pm-spec.json"

    doli_pm_projects "$(jq -n '[
        {id:"3",title:"Inventur",description:"Inventur",date_start:1759104000,date_end:"",
         public:"0",statut:"1",usage_task:1},
        {id:"4",title:"Buero",description:"Buero",date_start:1759104000,date_end:"",
         public:"0",statut:"1",usage_task:1}
    ]')"
    doli_pm_tasks '[]'

    # The new project comes first, so the id the stub hands back for its create
    # is the first one it hands out and a test can name it.
    doli_pm_spec "$(jq -n '{projects:[
        {title:"Krampustek", description:"Next event", date_start:"2026-09-19",
         date_end:"2026-09-19", public:0,
         tasks:[{label:"Rendering", date_end:"2026-09-19"}]},
        {title:"Inventur", tasks:[{label:"Eurokisten kaufen"}]}
    ]}')"
}

# The project list the faked ERP answers with. One fixture serves every query
# string, because the stub drops it from the fixture name.
doli_pm_projects() {
    doli_fixture projects "$1"
}

# Every task in the faked ERP, as one list. The script reads the global task
# endpoint rather than projects/{id}/tasks, because that one hides the tasks of
# a project the API user is not a contact on.
doli_pm_tasks() {
    doli_fixture tasks "$1"
}

doli_pm_spec() {
    printf '%s' "$1" > "$DOLIBARR_PM_SPEC"
}

doli_sync_pm() {
    run "$REPO_ROOT/tools/dolibarr/sync-pm.sh" "$@"
}

doli_post_count() {
    grep -c '^POST ' "$STUB_DOLI_LOG" || true
}

# tools/shopware/set-address.sh against the faked admin API. Fixtures carry the
# old address, so the default run is the one that has work to do.
sw_setup() {
    export SW_API_URL="https://shop.example.org"
    export SW_API_CLIENT_ID="fake-client"
    export SW_API_CLIENT_SECRET="fake-secret"
    export STUB_SW_DIR="$BATS_TEST_TMPDIR/sw"
    export STUB_SW_LOG="$BATS_TEST_TMPDIR/sw.log"
    mkdir -p "$STUB_SW_DIR"
    : > "$STUB_SW_LOG"

    sw_fixture_slot "Musikverein, Mühlenstraße 24, 5121 Ostermiething, Österreich"
    sw_fixture_system_config "Mühlenstraße 24<br>5121 Ostermiething<br>Österreich"
    sw_fixture_documents "Example Company" ""
}

# Every slot lookup hits the same path, so one fixture answers all three.
sw_fixture_slot() {
    printf '{"data":[{"config":{"content":{"value":%s,"source":"static"},"verticalAlign":{"value":null}}}],"total":1}' \
        "$(printf '%s' "$1" | jq -Rs .)" > "$STUB_SW_DIR/_api_search_cms-slot-translation"
}

sw_fixture_system_config() {
    printf '{"data":[{"id":"cfg1","configurationKey":"core.basicInformation.address","configurationValue":%s}],"total":1}' \
        "$(printf '%s' "$1" | jq -Rs .)" > "$STUB_SW_DIR/_api_search_system-config"
}

sw_fixture_documents() {
    local name="$1" addr="$2"
    jq -n --arg n "$name" --arg a "$addr" \
        '{data:[{id:"doc1",name:"invoice",config:{companyName:$n,companyAddress:$a,pageSize:"a4"}}],total:1}' \
        > "$STUB_SW_DIR/_api_search_document-base-config"
}

set_address() {
    run "$REPO_ROOT/tools/shopware/set-address.sh" "$@"
}

# Requests the script actually sent, one per line as "METHOD PATH BODY".
sw_requests() {
    cat "$STUB_SW_LOG"
}

sw_patch_count() {
    grep -c '^PATCH ' "$STUB_SW_LOG" || true
}

mail_count() {
    [[ -f "$STUB_MAIL_LOG" ]] || { echo 0; return; }
    # grep -c prints 0 and exits 1 when nothing matches, which is not an error here.
    grep -c '^=== MAIL ===' "$STUB_MAIL_LOG" || true
}

mail_body() {
    cat "$STUB_MAIL_LOG"
}

# tools/shopware/set-homepage-sections.sh. Each section is read by id, so each
# has its own fixture. The defaults are the live state before the theme.
SW_HOME_PAGE="695477e02ef643e5a016b83ed4cdf63a"
SW_HERO_SECTION="935477e02ef643e5a016b83ed4cdf63a"
SW_TILES_SECTION="fe11e555fd554ac69a914c34b0b2093f"

# sw_fixture_section ID CSS_CLASS SIZING_MODE [PAGE_ID]; an empty class is null.
sw_fixture_section() {
    jq -n --arg id "$1" --arg c "$2" --arg s "$3" --arg p "${4:-$SW_HOME_PAGE}" \
        '{data:{id:$id,pageId:$p,position:0,cssClass:(if $c == "" then null else $c end),sizingMode:$s,mobileBehavior:"wrap"}}' \
        > "$STUB_SW_DIR/_api_cms-section_$1"
}

sw_sections_setup() {
    sw_setup
    sw_fixture_section "$SW_HERO_SECTION" "" "boxed"
    sw_fixture_section "$SW_TILES_SECTION" "" "boxed"
}

set_homepage_sections() {
    run "$REPO_ROOT/tools/shopware/set-homepage-sections.sh" "$@"
}

# The body of the PATCH sent to one section, or nothing.
sw_patch_body() {
    grep "^PATCH /api/cms-section/$1 " "$STUB_SW_LOG" | sed "s|^PATCH /api/cms-section/$1 ||"
}
