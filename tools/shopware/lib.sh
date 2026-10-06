#!/usr/bin/env bash
#
# Shared helpers for the scripts in tools/shopware/ that write to the live shop
# through the admin API. Sourced, not executable on its own.
#
# The sourcing script sets APPLY (0 for a dry run, 1 to write) before calling
# sw_report, and calls sw_auth once before the first sw_api.
#
# Environment:
#   SHOPWARE_MCP_CONFIG   json holding the api credentials,
#                         default ~/.claude.json
#   SW_API_URL, SW_API_CLIENT_ID, SW_API_CLIENT_SECRET
#                         override the config file entirely

SW_SCRIPT="${SW_SCRIPT:-$(basename "$0")}"

die() { printf '%s: %s\n' "$SW_SCRIPT" "$*" >&2; exit 1; }

# Prints the comment block at the top of the calling script as its help text.
# The block runs from line 3 to the first line that is not a comment.
sw_usage() {
    sed -n '3,/^[^#]/{/^#/p}' "$0" | sed 's/^# \{0,1\}//'
}

# --- authentication --------------------------------------------------------
#
# The client secret goes from the config file straight into the request body
# without passing through a variable that anything later prints.

sw_token_payload() {
    if [[ -n "${SW_API_CLIENT_ID:-}" && -n "${SW_API_CLIENT_SECRET:-}" ]]; then
        jq -c -n --arg i "$SW_API_CLIENT_ID" --arg s "$SW_API_CLIENT_SECRET" \
            '{grant_type:"client_credentials",client_id:$i,client_secret:$s}'
    else
        jq -c '{grant_type:"client_credentials",
                client_id:     .mcpServers["shopware-admin-mcp"].env.SHOPWARE_API_CLIENT_ID,
                client_secret: .mcpServers["shopware-admin-mcp"].env.SHOPWARE_API_CLIENT_SECRET}' \
            "$SW_CONFIG"
    fi
}

# Sets SW_API_URL and SW_TOKEN, or dies with an instruction.
sw_auth() {
    command -v jq >/dev/null 2>&1 || die "jq is required"

    SW_CONFIG="${SHOPWARE_MCP_CONFIG:-$HOME/.claude.json}"

    if [[ -z "${SW_API_URL:-}" ]]; then
        [[ -r "$SW_CONFIG" ]] || die "no credentials: set SW_API_URL and friends, or provide $SW_CONFIG"
        SW_API_URL="$(jq -r '.mcpServers["shopware-admin-mcp"].env.SHOPWARE_API_URL // empty' "$SW_CONFIG")"
    fi
    [[ -n "${SW_API_URL:-}" ]] || die "no Shopware URL found"
    SW_API_URL="${SW_API_URL%/}"

    SW_TOKEN="$(sw_token_payload | curl -s --max-time 30 -X POST "$SW_API_URL/api/oauth/token" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' --data @- \
        | jq -r '.access_token // empty')"
    [[ -n "$SW_TOKEN" ]] || die "could not obtain an access token from $SW_API_URL"
}

# sw_api METHOD PATH [BODY] [EXTRA_HEADER]
sw_api() {
    local method="$1" path="$2" body="${3:-}" extra="${4:-}"
    local args=(-s --max-time 60 -X "$method" "$SW_API_URL/api$path"
        -H "Authorization: Bearer $SW_TOKEN"
        -H 'Content-Type: application/json' -H 'Accept: application/json')
    [[ -n "$extra" ]] && args+=(-H "$extra")
    [[ -n "$body" ]] && args+=(--data "$body")
    curl "${args[@]}"
}

# A successful Shopware write answers 204 with an empty body. `jq -e` on empty
# input exits 4, so an empty response has to be recognised as success before jq
# ever sees it. Getting this wrong made every successful write look like a
# failure.
sw_write_ok() {
    local response="$1" what="$2"
    [[ -z "${response//[[:space:]]/}" ]] && return 0
    printf '%s' "$response" | jq -e 'has("errors") | not' >/dev/null 2>&1 \
        || die "writing $what failed: $response"
}

# sw_report VERB WHAT prints one line of the plan, as "would" in a dry run.
sw_report() {
    local verb="$1" what="$2"
    if (( APPLY )); then
        printf '  %-8s %s\n' "$verb" "$what"
    else
        printf '  %-8s %s\n' "would" "$what"
    fi
}

sw_skip() {
    printf '  %-8s %s\n' "skip" "$1"
}
