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
