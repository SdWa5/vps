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
