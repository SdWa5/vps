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
    grep -q 'log_skip @not_csp_report' <<<"$block"
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
