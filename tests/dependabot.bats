#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
}

@test "Dependabot watches the compose images and the workflow actions weekly" {
    local config="$REPO_ROOT/.github/dependabot.yml"
    grep -qx '  - package-ecosystem: docker-compose' "$config"
    grep -qx '  - package-ecosystem: github-actions' "$config"
    [ "$(grep -c '^      interval: weekly$' "$config")" = 2 ]
}

@test "Dependabot never proposes a MariaDB major version" {
    awk '/dependency-name: mariadb/ { m = 1; next } m { print; exit }' "$REPO_ROOT/.github/dependabot.yml" \
        | grep -q 'version-update:semver-major'
}
