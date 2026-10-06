#!/usr/bin/env bats
# Tests for the SdWa5Theme storefront theme, see docs/shopware/theme.md.
#
# The theme cannot be compiled here, because that needs a Shopware instance.
# These tests guard the parts that fail silently instead: a snippet key missing
# in one language, a version marker that drifts from the package, a colour
# literal that the dark mode plugin would invert, and copy that promises more
# than the association can.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    THEME="$REPO_ROOT/shopware-html-data/custom/static-plugins/SdWa5Theme"
    RES="$THEME/src/Resources"
    SCSS="$RES/app/storefront/src/scss"
    VIEWS="$RES/views/storefront"
    SNIPPET_EN="$RES/snippet/en_GB/sdwa5.en-GB.json"
    SNIPPET_DE="$RES/snippet/de_DE/sdwa5.de-DE.json"
}

# Every leaf key of a snippet file, as dotted paths, sorted.
snippet_keys() {
    jq -r 'paths(scalars) | join(".")' "$1" | sort
}

@test "every JSON file of the theme parses" {
    for f in "$THEME/composer.json" "$RES/theme.json" "$SNIPPET_EN" "$SNIPPET_DE"; do
        jq -e . "$f" >/dev/null || { echo "$f does not parse"; return 1; }
    done
}

@test "English and German snippets have the same keys" {
    run diff <(snippet_keys "$SNIPPET_EN") <(snippet_keys "$SNIPPET_DE")
    [ "$status" -eq 0 ]
}

@test "every sdwa5 snippet a template uses exists in both languages" {
    keys="$(grep -rhoE "'sdwa5\.[A-Za-z0-9_.]+'\|trans" "$VIEWS" | sed -E "s/'([^']+)'.*/\1/" | sort -u)"
    [ -n "$keys" ]
    for key in $keys; do
        for f in "$SNIPPET_EN" "$SNIPPET_DE"; do
            snippet_keys "$f" | grep -qxF "$key" || { echo "$key missing in $f"; return 1; }
        done
    done
}

@test "the plugin version, the root require, the lock and the meta marker agree" {
    version="$(jq -r .version "$THEME/composer.json")"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    [ "$(jq -r '.require["sdwa5/sdwa5-theme"]' "$REPO_ROOT/shopware-html-data/composer.json")" = "$version" ]
    [ "$(jq -r '.packages[] | select(.name == "sdwa5/sdwa5-theme") | .version' \
        "$REPO_ROOT/shopware-html-data/composer.lock")" = "$version" ]
    grep -qF "<meta name=\"sdwa5:theme\" content=\"$version\">" "$VIEWS/layout/meta.html.twig"
}

@test "the plugin class named in composer.json exists" {
    class="$(jq -r '.extra["shopware-plugin-class"]' "$THEME/composer.json")"
    [ "$class" = 'SdWa5Theme\SdWa5Theme' ]
    grep -q '^class SdWa5Theme extends Plugin implements ThemeInterface' "$THEME/src/SdWa5Theme.php"
}

@test "theme.json resolves views through Storefront, then plugins, then the theme" {
    run jq -c .views "$RES/theme.json"
    [ "$output" = '["@Storefront","@Plugins","@SdWa5Theme"]' ]
}

@test "every font the SCSS loads ships with the theme, and so does its licence" {
    fonts="$(grep -oE "/fonts/[a-z0-9-]+\.woff2" "$SCSS/_fonts.scss" | sort -u)"
    [ "$(echo "$fonts" | wc -l)" -eq 3 ]
    for f in $fonts; do
        [ -s "$RES/app/storefront/src/assets$f" ] || { echo "$f missing"; return 1; }
    done
    grep -q 'SIL Open Font License' "$RES/app/storefront/src/assets/fonts/LICENSE.md"
}

@test "the header logo the template references ships with the theme" {
    path="$(grep -oE "asset\('assets/[^']+'" "$VIEWS/layout/header/logo.html.twig" | sed -E "s/asset\('assets//; s/'//")"
    [ -n "$path" ]
    [ -s "$RES/app/storefront/src/assets$path" ]
}

# The dark mode plugin inverts every low-saturation colour literal it finds and
# skips only properties whose names end in -immutable. A literal outside the
# token file would therefore not match its token in dark mode.
@test "colour literals appear only in the token file" {
    run grep -nE '#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(' "$SCSS"/*.scss
    [ "$status" -eq 0 ]
    # Comments may name a literal, for example the one a rule overrides.
    echo "$output" | grep -v '/_tokens\.scss:' | grep -vE '^[^:]+:[0-9]+: *//' | { ! grep .; }
}

@test "light and dark token maps define the same tokens" {
    light="$(sed -n '/^\$sdwa5-light:/,/^);/p' "$SCSS/_tokens.scss" | grep -oE "^  '[a-z-]+'" | sort)"
    dark="$(sed -n '/^\$sdwa5-dark:/,/^);/p' "$SCSS/_tokens.scss" | grep -oE "^  '[a-z-]+'" | sort)"
    [ -n "$light" ]
    [ "$light" = "$dark" ]
}

@test "every colour token a rule uses is defined in the token maps" {
    defined="$(sed -n '/^\$sdwa5-light:/,/^);/p' "$SCSS/_tokens.scss" | grep -oE "^  '[a-z-]+'" | tr -d " '" | sort -u)"
    used="$(grep -ohE -- '--sdwa5-[a-z-]+-immutable' "$SCSS"/*.scss | sed 's/^--sdwa5-//; s/-immutable$//' | sort -u)"
    [ -n "$used" ]
    # A renamed token leaves var() pointing at nothing, and the browser falls back silently.
    comm -23 <(echo "$used") <(echo "$defined") | { ! grep .; }
}

@test "the dark blocks emit tokens and color-scheme only" {
    # Everything between the dark selectors and their closing brace.
    body="$(sed -n "/data-theme='dark'/,/^}/p; /prefers-color-scheme: dark/,/^}/p" "$SCSS/_tokens.scss" \
        | grep -vE "data-theme|prefers-color-scheme|^ *}|^ *$|@include sdwa5-tokens\(\\\$sdwa5-dark\);|color-scheme: dark;" || true)"
    [ -z "$body" ]
}

# The association is registered only as not aimed at profit, so the copy must
# not claim charitable status or a tax benefit, and the question whether merch
# may be tied to a donation is still open.
@test "donation copy promises nothing beyond a voluntary donation" {
    for f in "$SNIPPET_EN" "$SNIPPET_DE"; do
        run jq -r '.sdwa5.donate[], .sdwa5.footer[]' "$f"
        [ "$status" -eq 0 ]
        echo "$output" | { ! grep -iE 'gemeinn|charit|tax|steuer|absetzbar|quittung|receipt|merch|shirt|hoodie'; }
    done
}

@test "the donation label says voluntary in both languages" {
    [ "$(jq -r .sdwa5.donate.label "$SNIPPET_EN")" = "Voluntary Donation" ]
    [ "$(jq -r .sdwa5.donate.label "$SNIPPET_DE")" = "Freiwillige Spende" ]
}

@test "every donation and share link that leaves the site opens safely in a new tab" {
    for f in "$VIEWS/layout/donate-link.html.twig" "$VIEWS/layout/share/share-links.html.twig"; do
        external="$(grep -cE 'href="(\{\{ sdwa5DonateUrl|https://)' "$f")"
        safe="$(grep -c 'rel="noopener noreferrer"' "$f")"
        [ "$external" -gt 0 ]
        [ "$external" -eq "$safe" ] || { echo "$f: $external external links, $safe with rel"; return 1; }
    done
}

@test "the donation URL defaults to the association's PayPal page" {
    [ "$(jq -r '.config.fields["sdwa5-donation-url"].value' "$RES/theme.json")" = "https://paypal.me/SdWa5" ]
    [ "$(jq -r '.config.fields["sdwa5-donation-url"].scss' "$RES/theme.json")" = "false" ]
}

# The VAT notice is part of the pending legal pass. Its look may change, its
# wording may not.
@test "the theme leaves the wording of the VAT notice alone" {
    for f in "$SNIPPET_EN" "$SNIPPET_DE"; do
        run jq -r '.footer // empty' "$f"
        [ -z "$output" ]
    done
    for f in $(grep -rl 'block layout_footer_vat' "$VIEWS" || true); do
        grep -q 'parent()' "$f" || { echo "$f overrides layout_footer_vat without parent()"; return 1; }
    done
}

@test "every template override calls parent() in each block it extends" {
    # Without parent() a core block disappears entirely, and for meta.html.twig
    # that would take every Shopware meta tag with it. The exceptions are the
    # blocks the theme replaces on purpose.
    for f in $(grep -rl 'sw_extends' "$VIEWS"); do
        blocks="$(grep -cE '\{% block [a-z_]+ %\}' "$f" || true)"
        parents="$(grep -cE 'parent\(\)' "$f" || true)"
        replaced="$(grep -cE '\{% block (layout_top_bar|layout_header_navigation_toggle|layout_header_logo_image) %\}' "$f" || true)"
        [ "$parents" -ge "$(( blocks - replaced ))" ] || { echo "$f: $blocks blocks, $parents parent() calls"; return 1; }
    done
}

# resolved-uri is the technical /navigation/<id> path wherever an SEO URL exists,
# measured on /About-SdWa5/.
@test "share links carry the URL as it was requested" {
    f="$VIEWS/layout/share/share-links.html.twig"
    grep -q "attributes.get('sw-original-request-uri')" "$f"
    grep -q "attributes.get('sw-sales-channel-absolute-base-url')" "$f"
    ! grep -q "attributes.get('resolved-uri')" "$f"
}

# The English hero text styles only the subtitle inline, the German one every
# paragraph, so an attribute selector turned the German stats line green.
@test "the hero subtitle is selected by position, not by the CMS markup" {
    grep -q 'h1 + p' "$SCSS/_hero.scss"
    run grep -n 'p\[style' "$SCSS/_hero.scss"
    [ "$status" -ne 0 ]
}
