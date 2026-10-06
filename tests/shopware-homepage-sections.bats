#!/usr/bin/env bats
# Tests for tools/shopware/set-homepage-sections.sh

load test_helper

setup() {
    common_setup
    sw_sections_setup
}

@test "help needs no credentials and names both switches" {
    unset SW_API_URL
    export SHOPWARE_MCP_CONFIG=/nonexistent
    set_homepage_sections --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--apply"* ]]
    [[ "$output" == *"--revert"* ]]
}

@test "an unknown option is rejected" {
    set_homepage_sections --frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"frobnicate"* ]]
}

@test "a dry run writes nothing and names both sections" {
    set_homepage_sections
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry run"* ]]
    [[ "$output" == *"hero section"* ]]
    [[ "$output" == *"tiles section"* ]]
    [[ "$output" == *"2 to change, 0 already current"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
    run grep -c '^DELETE ' "$STUB_SW_LOG"
    [ "$output" = "0" ]
}

@test "apply makes the hero full width and gives each section its class" {
    set_homepage_sections --apply
    [ "$status" -eq 0 ]
    [ "$(sw_patch_body "$SW_HERO_SECTION")" = '{"cssClass":"sdwa5-hero","sizingMode":"full_width"}' ]
    [ "$(sw_patch_body "$SW_TILES_SECTION")" = '{"cssClass":"sdwa5-tiles","sizingMode":"boxed"}' ]
}

@test "apply clears the cache after a change" {
    set_homepage_sections --apply
    [ "$status" -eq 0 ]
    grep -q '^DELETE /api/_action/cache' "$STUB_SW_LOG"
}

@test "a class the section already carries is kept" {
    sw_fixture_section "$SW_TILES_SECTION" "my-own" "boxed"
    set_homepage_sections --apply
    [ "$status" -eq 0 ]
    [ "$(sw_patch_body "$SW_TILES_SECTION")" = '{"cssClass":"my-own sdwa5-tiles","sizingMode":"boxed"}' ]
}

@test "sections already in place are skipped and the cache is left alone" {
    sw_fixture_section "$SW_HERO_SECTION" "sdwa5-hero" "full_width"
    sw_fixture_section "$SW_TILES_SECTION" "sdwa5-tiles" "boxed"
    set_homepage_sections --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to change, 2 already current"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
    run grep -c '^DELETE ' "$STUB_SW_LOG"
    [ "$output" = "0" ]
}

@test "revert restores a boxed hero and removes only the theme's classes" {
    sw_fixture_section "$SW_HERO_SECTION" "sdwa5-hero" "full_width"
    sw_fixture_section "$SW_TILES_SECTION" "my-own sdwa5-tiles" "boxed"
    set_homepage_sections --revert --apply
    [ "$status" -eq 0 ]
    [ "$(sw_patch_body "$SW_HERO_SECTION")" = '{"cssClass":null,"sizingMode":"boxed"}' ]
    [ "$(sw_patch_body "$SW_TILES_SECTION")" = '{"cssClass":"my-own","sizingMode":"boxed"}' ]
}

@test "revert on an untouched homepage changes nothing" {
    set_homepage_sections --revert --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 to change, 2 already current"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
}

@test "a missing section fails loudly instead of silently doing nothing" {
    rm "$STUB_SW_DIR/_api_cms-section_$SW_HERO_SECTION"
    set_homepage_sections --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
}

@test "a pinned id that now belongs to another page is refused" {
    sw_fixture_section "$SW_HERO_SECTION" "" "boxed" "0123456789abcdef0123456789abcdef"
    set_homepage_sections --apply
    [ "$status" -ne 0 ]
    [[ "$output" == *"not to the homepage"* ]]
    [ "$(sw_patch_count)" -eq 0 ]
}

@test "the pinned ids in the script match the ones the tests fake" {
    script="$REPO_ROOT/tools/shopware/set-homepage-sections.sh"
    grep -q "^HOME_PAGE=\"$SW_HOME_PAGE\"" "$script"
    grep -q "^HERO_SECTION=\"$SW_HERO_SECTION\"" "$script"
    grep -q "^TILES_SECTION=\"$SW_TILES_SECTION\"" "$script"
}

@test "the classes the script sets are the ones the theme styles" {
    scss="$REPO_ROOT/shopware-html-data/custom/static-plugins/SdWa5Theme/src/Resources/app/storefront/src/scss/_hero.scss"
    grep -q '\.sdwa5-hero\b' "$scss"
    grep -q '\.sdwa5-tiles\b' "$scss"
}

@test "a refused token stops the script before it touches anything" {
    export STUB_SW_NO_TOKEN=1
    set_homepage_sections --apply
    [ "$status" -ne 0 ]
    [ "$(sw_patch_count)" -eq 0 ]
}
