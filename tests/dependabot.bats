#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
}

@test "Dependabot watches the compose images and the workflow actions weekly" {
    local config="$REPO_ROOT/.github/dependabot.yml"
    grep -qx '  - package-ecosystem: docker-compose' "$config"
    grep -qx '  - package-ecosystem: github-actions' "$config"
    [ "$(grep -c '^      interval: weekly$' "$config")" = 5 ]
}

@test "Dependabot never proposes a MariaDB major version" {
    awk '/dependency-name: mariadb/ { m = 1; next } m { print; exit }' "$REPO_ROOT/.github/dependabot.yml" \
        | grep -q 'version-update:semver-major'
}

@test "Dependabot never proposes a MySQL major version and skips the local shop image" {
    local config="$REPO_ROOT/.github/dependabot.yml"
    awk '/dependency-name: mysql$/ { m = 1; next } m { print; exit }' "$config" \
        | grep -q 'version-update:semver-major'
    grep -qx '      - dependency-name: localhost/sdwa5-shopware' "$config"
}

@test "Dependabot watches the shop image's Dockerfile" {
    awk '/package-ecosystem: docker$/ { m = 1; next } m { print; exit }' "$REPO_ROOT/.github/dependabot.yml" \
        | grep -qx '    directory: /shopware'
}

@test "Dependabot watches the Jami Web image's Dockerfile and npm lock and skips the local image" {
    local config="$REPO_ROOT/.github/dependabot.yml"
    grep -qx '      - dependency-name: localhost/sdwa5-jami-web' "$config"
    for ecosystem in docker npm; do
        awk -v e="$ecosystem" '$0 == "  - package-ecosystem: " e { getline; print }' "$config" \
            | grep -qx '    directory: /jami-web'
    done
}

@test "no image line uses a YAML anchor, which Dependabot's compose updater cannot edit" {
    # dependabot-core matches the image right after "image:" in the raw text,
    # so "image: &x name:tag" and "image: *x" fail the whole update run.
    ! grep -nE '^[[:space:]]+image:[[:space:]]*[&*]' "$REPO_ROOT"/docker-compose*.yml
}

@test "both Paperless instances, both brokers and both Dolibarr services pin the same image" {
    local file="$REPO_ROOT/docker-compose.yml"
    [ "$(grep -c 'image: ghcr.io/paperless-ngx/paperless-ngx:' "$file")" = 2 ]
    [ "$(grep 'image: ghcr.io/paperless-ngx/paperless-ngx:' "$file" | sort -u | wc -l)" = 1 ]
    [ "$(grep -c 'image: valkey/valkey:' "$file")" = 2 ]
    [ "$(grep 'image: valkey/valkey:' "$file" | sort -u | wc -l)" = 1 ]
    [ "$(grep -c 'image: dolibarr/dolibarr:' "$file")" = 2 ]
    [ "$(grep 'image: dolibarr/dolibarr:' "$file" | sort -u | wc -l)" = 1 ]
}
