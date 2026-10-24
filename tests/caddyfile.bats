#!/usr/bin/env bats

load test_helper

setup() {
    common_setup
}

# The lines of one top-level site block of the Caddyfile.
site_block() {
    awk -v site="$1" '$0 == site " {" { s = 1 } s { print } s && /^}$/ { exit }' "$REPO_ROOT/Caddyfile"
}

@test "sdwa5.org sends the storefront CSP report-only and leaves the admin and the APIs out" {
    local block
    block="$(site_block https://sdwa5.org)"
    grep -q '@storefront not path /admin /admin/\* /api /api/\* /store-api /store-api/\* /csp-report$' <<<"$block"
    grep -q "header @storefront Content-Security-Policy-Report-Only \"default-src 'self';.*object-src 'none';.*report-uri /csp-report\"" <<<"$block"
    ! grep -q 'header @storefront Content-Security-Policy "' <<<"$block" || false
}

@test "only sdwa5.org carries a CSP, so the other sites keep their upstream behaviour" {
    [ "$(grep -cE '^[[:space:]]*header .*Content-Security-Policy' "$REPO_ROOT/Caddyfile")" -eq 1 ]
}

@test "csp reports are answered by Caddy and logged without the client address" {
    local block
    block="$(site_block https://sdwa5.org)"
    grep -q 'respond 204' <<<"$block"
    grep -q 'log_name csp_report$' <<<"$block"
    grep -q 'log csp_report {$' <<<"$block"
    grep -q 'no_hostname$' <<<"$block"
    grep -q 'request>remote_ip delete' <<<"$block"
    grep -q 'request>client_ip delete' <<<"$block"
    grep -q 'request>headers>Cookie delete' <<<"$block"
}

@test "erp.sdwa5.org answers the API explorer and the cron URL with a flat 404 before the proxy" {
    local block
    block="$(site_block erp.sdwa5.org)"
    grep -q '@blocked path /api/index.php/explorer /api/index.php/explorer/\* /public/cron /public/cron/\*$' <<<"$block"
    [ "$(grep -A1 'handle @blocked {' <<<"$block" | tail -n 1 | tr -s ' ')" = ' respond "Not Found" 404' ]
    [ "$(grep -n 'handle @blocked' <<<"$block" | cut -d: -f1)" -lt "$(grep -n 'reverse_proxy' <<<"$block" | cut -d: -f1)" ]
}

@test "every site imports the access log under its own name" {
    local pair block
    for pair in https://sdwa5.org:sdwa5.org vault.sdwa5.org:vault.sdwa5.org erp.sdwa5.org:erp.sdwa5.org \
        paper.sdwa5.org:paper.sdwa5.org paper.ripper.sdwa5.org:paper.ripper.sdwa5.org \
        chimodiazz.sdwa5.org:chimodiazz.sdwa5.org; do
        block="$(site_block "${pair%:*}")"
        grep -q "import access_log ${pair##*:}\$" <<<"$block" || { echo "no access log in ${pair%:*}"; return 1; }
    done
}

@test "the access log drops credentials and the referrer and redacts token values" {
    local field
    for field in 'request>headers>Cookie' 'request>headers>Authorization' 'request>headers>Proxy-Authorization' \
        'request>headers>Referer' 'request>headers>Dolapikey' 'request>headers>Sw-Context-Token' 'resp_headers>Set-Cookie'; do
        grep -qF "$field delete" "$REPO_ROOT/Caddyfile" || { echo "$field not deleted"; return 1; }
    done
    [ "$(grep -cF '"${1}${2}REDACTED"' "$REPO_ROOT/Caddyfile")" -eq 2 ]
    grep -q 'request>uri regexp ' "$REPO_ROOT/Caddyfile"
    grep -q 'resp_headers>Location regexp ' "$REPO_ROOT/Caddyfile"
}
