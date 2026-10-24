#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
}

@test "every MariaDB service runs mariadb-upgrade after a version bump" {
    local file images upgrades
    for file in "$REPO_ROOT"/docker-compose*.yml; do
        images="$(grep -c 'image: mariadb:' "$file" || true)"
        upgrades="$(grep -c 'MARIADB_AUTO_UPGRADE: "1"' "$file" || true)"
        [ "$images" = "$upgrades" ] || { echo "$file: $images MariaDB services, $upgrades with auto-upgrade"; return 1; }
    done
}

@test "docker-compose.yml interpolates no secret from .env except Vaultwarden's argon2 ADMIN_TOKEN" {
    local leaks
    leaks="$(grep -v '^[[:space:]]*#' "$REPO_ROOT/docker-compose.yml" \
        | grep -oE '\$\{[A-Z0-9_]*(PASS|TOKEN|SECRET|_KEY)[A-Z0-9_]*' | grep -vx '${VAULTWARDEN_ADMIN_TOKEN' || true)"
    [ -z "$leaks" ] || { echo "still interpolated: $leaks"; return 1; }
}

@test "every declared secret is the gitignored ./secrets file of its own name" {
    local bad
    bad="$(awk '/^secrets:/ { s = 1; next } s && /^[^ ]/ { s = 0 }
        s && /^  [a-z0-9_]+:$/ { name = substr($1, 1, length($1) - 1); next }
        s && /^    file:/ { if ($2 != "./secrets/" name) print name " -> " $2; n++ }
        END { if (!n) print "no secrets block" }' "$REPO_ROOT/docker-compose.yml")"
    [ -z "$bad" ] || { echo "$bad"; return 1; }
    grep -qx '/secrets/' "$REPO_ROOT/.gitignore"
}

@test "every *_FILE that points into /run/sdwa5-secrets is mounted in the same service" {
    local bad
    bad="$(awk '/^services:/ { s = 1; next } s && /^[^ #]/ { s = 0 }
        function flush() { for (r in ref) if (!(r in mounted)) print svc ": " r; delete ref; delete mounted }
        s && /^  [a-z0-9_]+:$/ { flush(); svc = $1; next }
        s && /_FILE: \/run\/sdwa5-secrets\// { ref[$2] = 1 }
        s && /target: \/run\/sdwa5-secrets\// { mounted[$2] = 1 }
        END { flush() }' "$REPO_ROOT/docker-compose.yml")"
    [ -z "$bad" ] || { echo "referenced but not mounted: $bad"; return 1; }
}

@test "both dockware shops mount the boot hook read-only, and only the main shop stops mailcatcher" {
    grep -q '\./hardening/dockware-boot-end.sh:/var/www/boot_end.sh:ro' "$REPO_ROOT/docker-compose.yml"
    grep -q '\./hardening/dockware-boot-end.sh:/var/www/boot_end.sh:ro' "$REPO_ROOT/docker-compose.projects.yml"
    grep -q 'SDWA5_STOP_MAILCATCHER=1' "$REPO_ROOT/docker-compose.yml"
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/docker-compose.projects.yml" | grep -q 'SDWA5_STOP_MAILCATCHER' || false
}

@test "every running service except the two dockware shops sets no-new-privileges" {
    local missing extra
    missing="$(awk '/^services:/ { s = 1; next } s && /^[^ #]/ { s = 0 }
        function flush() { if (svc != "" && !profile && !nnp && svc != "shopware:" && svc != "chimodiazz_shopware:") print svc }
        s && /^  [a-z0-9_]+:$/ { flush(); svc = $1; profile = 0; nnp = 0; next }
        s && /^    profiles:/ { profile = 1 }
        s && /^    security_opt: \["no-new-privileges:true"\]$/ { nnp = 1 }
        END { flush() }' "$REPO_ROOT/docker-compose.yml" "$REPO_ROOT/docker-compose.projects.yml")"
    [ -z "$missing" ] || { echo "without no-new-privileges: $missing"; return 1; }
    extra="$(awk '/^  [a-z0-9_]+:$/ { svc = $1 } /^    security_opt:.*no-new-privileges/ && (svc == "shopware:" || svc == "chimodiazz_shopware:") { print svc }' \
        "$REPO_ROOT/docker-compose.yml" "$REPO_ROOT/docker-compose.projects.yml")"
    [ -z "$extra" ] || { echo "dockware needs setuid sudo: $extra"; return 1; }
    [ "$(grep -c 'no-new-privileges:true' "$REPO_ROOT/docker-compose.yml")" -eq 11 ]
}

@test "every PHP web service mounts the PHP security mitigation ini read-only" {
    local ini=./hardening/php/99-php-security-mitigation.ini svc missing=
    for svc in shopware dolibarr dolibarr_cron; do
        awk -v svc="  $svc:" '$0 == svc { s = 1; next } s && /^  [a-z0-9_]+:$/ { s = 0 } s' \
            "$REPO_ROOT/docker-compose.yml" | grep -qF -- "- $ini:" || missing+=" $svc"
    done
    [ -z "$missing" ] || { echo "without the mitigation ini:$missing"; return 1; }
    ! grep -F -- "$ini:" "$REPO_ROOT/docker-compose.yml" | grep -vq ':ro$' || false
    grep -qx 'session.upload_progress.enabled = 0' "$REPO_ROOT/hardening/php/99-php-security-mitigation.ini"
}
