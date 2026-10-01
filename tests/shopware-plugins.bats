#!/usr/bin/env bats
# Tests for how the Shopware plugins on sdwa5.org are recorded, see
# docs/shopware/plugins.md. Every plugin has to come from composer.lock, so a
# fresh checkout plus auth.json reproduces the whole set.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    COMPOSER_JSON="$REPO_ROOT/shopware-html-data/composer.json"
    COMPOSER_LOCK="$REPO_ROOT/shopware-html-data/composer.lock"
}

@test "no plugin in composer.lock is installed from a path" {
    # A path dist points into custom/plugins/, which is not in the repository,
    # so composer install on a fresh checkout cannot rebuild it.
    run jq -r '(.packages + ."packages-dev")[]
        | select(.type == "shopware-platform-plugin" and .dist.type == "path")
        | .name' "$COMPOSER_LOCK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "all eleven live plugins are locked" {
    run jq -r '(.packages + ."packages-dev")[]
        | select(.type == "shopware-platform-plugin") | .name' "$COMPOSER_LOCK"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l)" -eq 11 ]
}

@test "every locked plugin is a direct require with an exact version" {
    # A floating constraint would turn the next composer update into an
    # unplanned plugin upgrade on a live shop.
    for name in $(jq -r '(.packages + ."packages-dev")[]
            | select(.type == "shopware-platform-plugin") | .name' "$COMPOSER_LOCK"); do
        constraint="$(jq -r --arg n "$name" '.require[$n] // "missing"' "$COMPOSER_JSON")"
        [[ "$constraint" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
            echo "$name has constraint $constraint"
            return 1
        }
    done
}

@test "packages.shopware.com is a composer repository" {
    run jq -r '.repositories[] | select(.type == "composer") | .url' "$COMPOSER_JSON"
    [ "$status" -eq 0 ]
    [ "$output" = "https://packages.shopware.com" ]
}

@test ".gitignore lifts nothing under custom/plugins back out" {
    run grep -E '^!shopware-html-data/custom' "$REPO_ROOT/.gitignore"
    [ "$status" -eq 1 ]
}
