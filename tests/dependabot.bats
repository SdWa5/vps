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

@test "no image line uses a YAML anchor, which Dependabot's compose updater cannot edit" {
    # dependabot-core matches the image right after "image:" in the raw text,
    # so "image: &x name:tag" and "image: *x" fail the whole update run.
    ! grep -nE '^[[:space:]]+image:[[:space:]]*[&*]' "$REPO_ROOT"/docker-compose*.yml
}

@test "both Paperless instances and both brokers pin the same image" {
    local file="$REPO_ROOT/docker-compose.yml"
    [ "$(grep -c 'image: ghcr.io/paperless-ngx/paperless-ngx:' "$file")" = 2 ]
    [ "$(grep 'image: ghcr.io/paperless-ngx/paperless-ngx:' "$file" | sort -u | wc -l)" = 1 ]
    [ "$(grep -c 'image: valkey/valkey:' "$file")" = 2 ]
    [ "$(grep 'image: valkey/valkey:' "$file" | sort -u | wc -l)" = 1 ]
}
