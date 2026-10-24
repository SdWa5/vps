#!/usr/bin/env bats
# Tests for monitoring/security-recheck.sh

load test_helper

setup() {
    recheck_setup
}

# --- usage --------------------------------------------------------------------

@test "help prints usage and exits 0" {
    recheck --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--external"* ]]
}

@test "an unknown option is a usage error" {
    recheck --bogus
    [ "$status" -eq 2 ]
}

# --- external -----------------------------------------------------------------

@test "a healthy external run reports only OK and exits 0" {
    recheck --external
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\tWARN\t'* ]]
    [[ "$output" != *$'\tCRIT\t'* ]]
    [ "$(recheck_status ports:v4)" = OK ]
    [ "$(recheck_status ports:v6)" = OK ]
    [ "$(recheck_status http3:sdwa5.org)" = OK ]
    [ "$(recheck_status hsts:vault.sdwa5.org)" = OK ]
    [ "$(recheck_status blocked:vault.sdwa5.org/admin)" = OK ]
}

@test "an unexpected open port is CRIT" {
    export STUB_NC_OPEN_V4="22 80 443 3306"
    recheck --external
    [ "$status" -eq 1 ]
    [ "$(recheck_status ports:v4)" = CRIT ]
    [[ "$output" == *"3306"* ]]
}

@test "an expected port that does not answer is CRIT" {
    export STUB_NC_OPEN_V6="22 443"
    recheck --external
    [ "$status" -eq 1 ]
    [ "$(recheck_status ports:v6)" = CRIT ]
}

@test "a refused port is WARN, because DROP makes closed ports time out" {
    export STUB_NC_REFUSED_V4="25"
    recheck --external
    [ "$status" -eq 0 ]
    [ "$(recheck_status ports:v4)" = WARN ]
}

@test "a family with nothing open is WARN, not a pass" {
    export STUB_NC_OPEN_V6=""
    recheck --external
    [ "$(recheck_status ports:v6)" = WARN ]
    [[ "$output" == *"not verified"* ]]
}

@test "an empty v6 target skips the v6 scan" {
    export RECHECK_TARGET_V6=""
    recheck --external
    [ -z "$(recheck_status ports:v6)" ]
}

@test "strict turns a WARN into a failure" {
    export STUB_NC_REFUSED_V4="25"
    recheck --external --strict
    [ "$status" -eq 1 ]
}

@test "no HTTP/3 answer is CRIT" {
    export STUB_HTTP3_VERSION=2
    recheck --external
    [ "$(recheck_status http3:sdwa5.org)" = CRIT ]
}

@test "a curl without HTTP/3 support is WARN" {
    export STUB_CURL_NO_HTTP3=1
    recheck --external
    [ "$(recheck_status http3:sdwa5.org)" = WARN ]
}

@test "a site that does not answer 200 is CRIT" {
    export STUB_SITE_STATUS="erp.sdwa5.org=502"
    recheck --external
    [ "$status" -eq 1 ]
    [ "$(recheck_status site:erp.sdwa5.org)" = CRIT ]
    [ "$(recheck_status site:sdwa5.org)" = OK ]
}

@test "a Server header is CRIT" {
    export STUB_SERVER_HEADER="chimodiazz.sdwa5.org"
    recheck --external
    [ "$(recheck_status site:chimodiazz.sdwa5.org)" = CRIT ]
    [[ "$output" == *"Server"* ]]
}

@test "a missing HSTS header is CRIT" {
    export STUB_HSTS_AGE=""
    recheck --external
    [ "$(recheck_status hsts:vault.sdwa5.org)" = CRIT ]
}

@test "a short HSTS max-age is CRIT" {
    export STUB_HSTS_AGE=300
    recheck --external
    [ "$(recheck_status hsts:erp.sdwa5.org)" = CRIT ]
}

@test "every blocked path is probed with its bypass variants" {
    export BLOCKED_PATHS="vault.sdwa5.org=/admin"
    recheck --external
    [[ "$output" == *"all 11 variants"* ]]
}

@test "a variant that reaches the upstream 404 is WARN" {
    export STUB_UPSTREAM_PATHS="vault.sdwa5.org/%61dmin"
    recheck --external
    [ "$(recheck_status blocked:vault.sdwa5.org/admin)" = WARN ]
    [[ "$output" == *"/%61dmin"* ]]
}

@test "a variant the upstream answers is CRIT" {
    export STUB_OPEN_PATHS="vault.sdwa5.org//admin"
    recheck --external
    [ "$status" -eq 1 ]
    [ "$(recheck_status blocked:vault.sdwa5.org/admin)" = CRIT ]
    [[ "$output" == *"//admin (200)"* ]]
}

@test "a nested blocked path gets its variants on the last segment" {
    export BLOCKED_PATHS="erp.sdwa5.org=/api/index.php/explorer"
    export STUB_OPEN_PATHS="erp.sdwa5.org/api/index.php/Explorer"
    recheck --external
    [ "$(recheck_status blocked:erp.sdwa5.org/api/index.php/explorer)" = CRIT ]
}

@test "no body, cookie or header value reaches the report" {
    export STUB_UPSTREAM_PATHS="vault.sdwa5.org/%61dmin"
    export STUB_OPEN_PATHS="erp.sdwa5.org//api/index.php/explorer"
    recheck --external
    [[ "$output" != *"SECRET"* ]]
}

# --- host ---------------------------------------------------------------------

@test "a healthy host run reports only OK and exits 0" {
    recheck --host
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\tWARN\t'* ]]
    [[ "$output" != *$'\tCRIT\t'* ]]
    [ "$(recheck_status firewall:v6)" = OK ]
    [ "$(recheck_status isolation:dolibarr)" = OK ]
    [ "$(recheck_status accounts:host)" = OK ]
    [ "$(recheck_status host:complete)" = OK ]
}

@test "an INPUT policy other than DROP is CRIT" {
    export STUB_IPT_V4="${STUB_IPT_V4/-P INPUT DROP/-P INPUT ACCEPT}"
    recheck --host
    [ "$(recheck_status firewall:v4)" = CRIT ]
}

@test "a missing udp 443 accept is CRIT" {
    export STUB_IPT_V6="$(grep -v 'udp' <<<"$STUB_IPT_V6")"
    recheck --host
    [ "$(recheck_status firewall:v6)" = CRIT ]
    [[ "$output" == *"udp 443 not accepted"* ]]
}

@test "a fail2ban jump behind other rules is WARN" {
    export STUB_IPT_V4='-P INPUT DROP
-A INPUT -i lo -j ACCEPT
-A INPUT -p tcp -m multiport --dports 22 -j f2b-sshd
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
-A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
-A INPUT -p udp -m udp --dport 443 -j ACCEPT'
    recheck --host
    [ "$(recheck_status firewall:v4)" = WARN ]
}

@test "a DOCKER-USER without the eth0 drop is CRIT" {
    export STUB_IPT_DOCKER_USER='-N DOCKER-USER
-A DOCKER-USER -j RETURN'
    recheck --host
    [ "$(recheck_status firewall:docker-user)" = CRIT ]
}

@test "isolation probes every non-loopback listener of the other applications" {
    recheck --host
    grep -qx 'shopware 172.20.0.2:3306' "$STUB_PROBE_LOG"
    grep -qx 'shopware 172.23.0.2:1080' "$STUB_PROBE_LOG"
    grep -qx 'dolibarr 172.21.0.2:80' "$STUB_PROBE_LOG"
    [ -z "$(grep '^shopware 172.18.0.2:' "$STUB_PROBE_LOG")" ]
    [ -z "$(grep '^dolibarr 172.19.0.3:' "$STUB_PROBE_LOG")" ]
    [ -z "$(grep ':3306$' "$STUB_PROBE_LOG" | grep '0.0.0.0\|127.0.0.1')" ]
}

@test "the vault and the backup container are probed, restic through nc" {
    export STUB_NO_BASH="restic" STUB_SHELL_LOG="$BATS_TEST_TMPDIR/shells"
    recheck --host
    grep -qx 'restic 172.21.0.2:80' "$STUB_PROBE_LOG"
    grep -qx 'vaultwarden 172.20.0.2:3306' "$STUB_PROBE_LOG"
    grep -qx 'restic sh' "$STUB_SHELL_LOG"
    grep -qx 'vaultwarden bash' "$STUB_SHELL_LOG"
    [ -z "$(grep '^restic bash' "$STUB_SHELL_LOG")" ]
    [ "$(recheck_status isolation:restic)" = OK ]
    [ "$(recheck_status isolation:vaultwarden)" = OK ]
}

@test "a reachable foreign listener is CRIT and names the container" {
    export ISOLATION_SOURCES="chimodiazz_shopware shopware dolibarr"
    export STUB_PROBE_OPEN="dolibarr>172.20.0.2:3306 chimodiazz_shopware>172.18.0.2:3306"
    recheck --host
    [ "$status" -eq 1 ]
    [ "$(recheck_status isolation:chimodiazz_shopware)" = CRIT ]
    [[ "$output" == *"shopware:3306"* ]]
}

@test "the database path that must stay open is CRIT when it closes" {
    export STUB_PROBE_OPEN=""
    recheck --host
    [ "$(recheck_status isolation:dolibarr)" = CRIT ]
    [[ "$output" == *"dolibarr_db:3306, which it needs"* ]]
}

@test "a stopped source container is CRIT" {
    export STUB_STOPPED="shopware"
    recheck --host
    [ "$(recheck_status isolation:shopware)" = CRIT ]
}

@test "a host port reachable from a container is CRIT" {
    export STUB_PROBE_OPEN="dolibarr>172.20.0.2:3306 shopware>172.18.0.1:2019"
    recheck --host
    [ "$(recheck_status gateway:shopware)" = CRIT ]
    [[ "$output" == *"172.18.0.1:2019"* ]]
}

@test "database egress is CRIT" {
    export STUB_PROBE_OPEN="dolibarr>172.20.0.2:3306 dolibarr_db>1.1.1.1:443"
    recheck --host
    [ "$(recheck_status egress:dolibarr_db)" = CRIT ]
}

@test "a healthy host run accepts file paths, not-set, argon2 and empty values in container envs" {
    recheck --host
    [ "$(recheck_status env:vaultwarden)" = OK ]
    [[ "$output" == *$'env:vaultwarden\tOK\tno secret in docker inspect or in any process environment'* ]]
    [[ "$output" != *argon2* ]]
}

@test "a secret value in docker inspect is WARN and names the variable, never the value" {
    export STUB_CONFIG_ENV_LEAK="dolibarr:DOLI_DB_PASSWORD restic:RESTIC_PASSWORD paperless_sdwa5:PAPERLESS_DBPASS dolibarr:DOLI_CRON_KEY"
    recheck --host
    [ "$(recheck_status env:dolibarr)" = WARN ]
    [ "$(recheck_status env:restic)" = WARN ]
    [ "$(recheck_status env:paperless_sdwa5)" = WARN ]
    [[ "$output" == *'secret values for DOLI_CRON_KEY DOLI_DB_PASSWORD'* ]]
    [[ "$output" != *leaked* ]]
    [ "$(recheck_status env:dolibarr_cron)" = OK ]
}

@test "a value a process exported from its _FILE stays OK but is named as residual" {
    recheck --host
    [ "$(recheck_status env:paperless_sdwa5)" = OK ]
    [[ "$output" == *$'env:paperless_sdwa5\tOK\tno secret in docker inspect; process environment still carries PAPERLESS_DBPASS PAPERLESS_SECRET_KEY'* ]]
    [ "$(recheck_status env:dolibarr_db)" = OK ]
    [[ "$output" == *$'env:dolibarr_db\tOK\tno secret in docker inspect or in any process environment'* ]]
    [[ "$output" != *residual* ]]
}

@test "process environments are read on the host, and an unreadable one is WARN" {
    export STUB_ENVIRON_UNREADABLE="vaultwarden"
    recheck --host
    [ "$(recheck_status env:vaultwarden)" = WARN ]
    [[ "$output" == *'vaultwarden: 1 of 2 process environments not readable'* ]]
    [ "$(recheck_status env:shopware)" = OK ]
}

@test "a container whose processes cannot be listed is WARN, not OK" {
    export STUB_TOP_FAIL="restic"
    recheck --host
    [ "$(recheck_status env:restic)" = WARN ]
    [[ "$output" == *'restic: no process environment found to read'* ]]
}

@test "a shop with dockware's sshd or the main shop's mailcatcher still listening is WARN" {
    recheck --host
    [ "$(recheck_status listeners:shopware)" = OK ]
    [ "$(recheck_status listeners:chimodiazz_shopware)" = OK ]
    export STUB_EXTRA_LISTEN="shopware:1080 chimodiazz_shopware:22"
    recheck --host
    [ "$(recheck_status listeners:shopware)" = WARN ]
    [ "$(recheck_status listeners:chimodiazz_shopware)" = WARN ]
    [[ "$output" == *'shopware listens on 1080'* ]]
}

@test "a deployed revision behind origin is WARN" {
    export STUB_GIT_REMOTE=2222222222222222222222222222222222222222
    recheck --host
    [ "$status" -eq 0 ]
    [ "$(recheck_status revision:main)" = WARN ]
}

@test "an unreachable origin is WARN" {
    export STUB_GIT_REMOTE=""
    recheck --host
    [ "$(recheck_status revision:main)" = WARN ]
}

@test "a modified tracked file is WARN" {
    export STUB_GIT_MODIFIED=" M Caddyfile"
    recheck --host
    [ "$(recheck_status revision:main)" = WARN ]
}

@test "the checkout is only read" {
    recheck --host
    [ -s "$STUB_GIT_LOG" ]
    [ -z "$(grep -E '(^| )(fetch|pull|reset|checkout)( |$)' "$STUB_GIT_LOG")" ]
}

@test "a drifted deployed file is WARN and named" {
    printf 'edited on the host\n' > "$BATS_TEST_TMPDIR/deployed/b.conf"
    recheck --host
    [ "$(recheck_status deployed:files)" = WARN ]
    [[ "$output" == *"deployed/b.conf"* ]]
}

@test "an added root key is CRIT on the host" {
    printf '%s\n' "$TEST_KEY_B" >> "$ROOT_AUTHORIZED_KEYS"
    recheck --host
    [ "$status" -eq 1 ]
    [ "$(recheck_status accounts:host)" = CRIT ]
    [[ "$output" == *"$TEST_KEY_B_FP"* ]]
}

@test "restore checks run only with --restore" {
    export RESTORE_CHECK="$BATS_TEST_TMPDIR/restore"
    printf '#!/bin/sh\necho "restore of $1 ok"\n' > "$RESTORE_CHECK"
    chmod +x "$RESTORE_CHECK"
    recheck --host
    [ -z "$(recheck_status restore:shopware)" ]
    recheck --host --restore
    [ "$(recheck_status restore:shopware)" = OK ]
    [[ "$output" == *"restore of dolibarr_db ok"* ]]
}

@test "a failed restore check is CRIT" {
    export RESTORE_CHECK="$BATS_TEST_TMPDIR/restore" DATABASE_BACKUP_CONTAINERS="dolibarr_db chimodiazz_shopware"
    printf '#!/bin/sh\nexit 1\n' > "$RESTORE_CHECK"
    chmod +x "$RESTORE_CHECK"
    recheck --host --restore
    [ "$status" -eq 1 ]
    [ "$(recheck_status restore:chimodiazz_shopware)" = CRIT ]
}

# --- both parts -----------------------------------------------------------------

@test "the default run adds the host part over ssh" {
    export STUB_SSH_OUTPUT=$'firewall:v4\tOK\tfine\nhost:complete\tOK\thost part finished'
    recheck
    [ "$status" -eq 0 ]
    [ "$(recheck_status firewall:v4)" = OK ]
    grep -q 'BatchMode=yes' "$STUB_SSH_LOG"
    grep -q 'security-recheck.sh --host$' "$STUB_SSH_LOG"
}

@test "--restore is passed to the host part" {
    export STUB_SSH_OUTPUT=$'host:complete\tOK\tdone'
    recheck --restore
    grep -q -- '--host --restore$' "$STUB_SSH_LOG"
}

@test "a host CRIT fails the whole run" {
    export STUB_SSH_OUTPUT=$'egress:dolibarr_db\tCRIT\treaches the internet\nhost:complete\tOK\tdone'
    export STUB_SSH_RC=1
    recheck
    [ "$status" -eq 1 ]
    [ "$(recheck_status egress:dolibarr_db)" = CRIT ]
}

@test "an ssh failure is CRIT" {
    export STUB_SSH_RC=255
    recheck
    [ "$status" -eq 1 ]
    [ "$(recheck_status host:ssh)" = CRIT ]
}

@test "a host part cut short is CRIT" {
    export STUB_SSH_OUTPUT=$'firewall:v4\tOK\tfine'
    recheck
    [ "$status" -eq 1 ]
    [ "$(recheck_status host:complete)" = CRIT ]
}

@test "a malformed host line is CRIT" {
    export STUB_SSH_OUTPUT=$'firewall:v4\tMAYBE\tfine\nsomething odd\nhost:complete\tOK\tdone'
    recheck
    [ "$status" -eq 1 ]
    [ "$(recheck_status firewall:v4)" = CRIT ]
    [ "$(recheck_status host:output)" = CRIT ]
}

@test "a site with a path is checked at that path" {
    export STUB_SITE_STATUS="paper.sdwa5.org=500"
    recheck --external
    [ "$(recheck_status site:paper.sdwa5.org/accounts/login/)" = CRIT ]
    [ "$(recheck_status site:paper.ripper.sdwa5.org/accounts/login/)" = OK ]
}
