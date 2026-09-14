#!/usr/bin/env bash
#
# Read-only client for the Dolibarr REST API at erp.sdwa5.org.
#
# Reading is all this script does. Dolibarr's REST API can write, but a write
# against the live ERP is a production mutation, so it belongs in its own
# idempotent script that a human starts. This is the same split the Shopware
# work uses and it is deliberate.
#
# The API key never reaches the process list or the terminal. curl reads it from
# a config file on stdin, exactly as send_mail in monitoring/lib.sh passes the
# SMTP password.
#
# Usage:
#   doli.sh status                 the API's own status endpoint, the reachability test
#   doli.sh company                the organisation record behind invoices and documents
#   doli.sh get PATH               any GET, e.g. get "thirdparties?limit=5"
#   doli.sh --help
#
# Environment:
#   DOLIBARR_URL          base URL, default https://erp.sdwa5.org
#   DOLIBARR_TOKEN_FILE   file holding the API key, default ~/.config/sdwa5-dolibarr-token
#   DOLI_CURL_TIMEOUT     seconds, default 30

set -uo pipefail

DOLIBARR_URL="${DOLIBARR_URL:-https://erp.sdwa5.org}"
DOLIBARR_TOKEN_FILE="${DOLIBARR_TOKEN_FILE:-$HOME/.config/sdwa5-dolibarr-token}"
DOLI_CURL_TIMEOUT="${DOLI_CURL_TIMEOUT:-30}"

API_ROOT="$DOLIBARR_URL/api/index.php"

usage() {
    sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf 'doli.sh: %s\n' "$*" >&2
    exit 1
}

# Fail early and with an instruction rather than with a 401 the caller has to
# decode. The key is never read into a variable here; only its file is checked.
require_token() {
    [[ -r "$DOLIBARR_TOKEN_FILE" ]] || die \
        "no API key at $DOLIBARR_TOKEN_FILE. Create it from the key in the Dolibarr user card, for example with: xclip -selection clipboard -o > $DOLIBARR_TOKEN_FILE && chmod 600 $DOLIBARR_TOKEN_FILE"

    local mode
    mode="$(stat -c %a "$DOLIBARR_TOKEN_FILE" 2>/dev/null || echo '')"
    if [[ -n "$mode" && "$mode" != "600" && "$mode" != "400" ]]; then
        printf 'doli.sh: warning, %s is mode %s. chmod 600 it.\n' \
            "$DOLIBARR_TOKEN_FILE" "$mode" >&2
    fi
}

# api_get PATH
#
# Prints the response body on stdout and the HTTP status on fd 3 is not worth
# the complexity here, so the status is appended as a last line and split off by
# the caller. Anything but 200 is an error with the body shown, because
# Dolibarr answers a disabled module with 200 and an HTML sentence.
api_get() {
    local path="$1" response status body
    require_token

    response="$(printf 'header = "DOLAPIKEY: %s"\n' "$(cat "$DOLIBARR_TOKEN_FILE")" \
        | curl --silent --show-error --config - \
            --max-time "$DOLI_CURL_TIMEOUT" \
            --header 'Accept: application/json' \
            --write-out $'\n%{http_code}' \
            --url "$API_ROOT/$path")" || die "curl failed against $API_ROOT/$path"

    status="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [[ "$status" != "200" ]]; then
        printf '%s\n' "$body" >&2
        die "HTTP $status for $path"
    fi

    # The API module being switched off is the one failure that arrives as a
    # successful response, so it is caught on the body rather than the status.
    if [[ "$body" == *"Module"*"must be enabled"* ]]; then
        die "the Api module is disabled in Dolibarr. Switch it on under Home, Setup, Modules, then create an API key on a dedicated user."
    fi

    printf '%s\n' "$body"
}

# Pretty-print when jq is there, pass through when it is not.
emit() {
    if command -v jq >/dev/null 2>&1; then
        jq . 2>/dev/null || cat
    else
        cat
    fi
}

cmd_status() {
    api_get "status" | emit
}

# The organisation record is what invoices and every generated document carry,
# so it is the one read this repository actually needs today.
cmd_company() {
    api_get "setup/company" | emit
}

cmd_get() {
    [[ $# -ge 1 ]] || die "get needs a path, for example: get 'thirdparties?limit=5'"
    api_get "$1" | emit
}

main() {
    [[ $# -ge 1 ]] || { usage; exit 1; }

    case "$1" in
        -h|--help) usage ;;
        status)    cmd_status ;;
        company)   cmd_company ;;
        get)       shift; cmd_get "$@" ;;
        *)         die "unknown command: $1. Try --help." ;;
    esac
}

main "$@"
