# shellcheck shell=bash
#
# Shared by tools/paperless/setup.sh and tools/paperless/visibility-check.sh.
# Sourced, never run.
#
# Both scripts talk to the Paperless-ngx REST API with a token per user. The
# credentials go to curl on a pipe, so neither a password nor a token shows up
# in the process list, in the terminal or in a log.

PAPERLESS_CURL_TIMEOUT="${PAPERLESS_CURL_TIMEOUT:-60}"

die() { printf '%s: %s\n' "$(basename "$0")" "$*" >&2; exit 1; }

# The spec is the single source of what an instance should hold, so its URL and
# admin password file are read from it rather than from a second config.
spec_value() { jq -r "$1 // empty" "$SPEC"; }

# Expands a leading ~ the way a shell would, because the path comes out of JSON.
expand_path() {
    local path="$1"
    # shellcheck disable=SC2088 # the literal tilde is what is being matched
    [[ "$path" == '~/'* ]] && path="$HOME/${path#'~/'}"
    printf '%s' "$path"
}

password_file() { printf '%s/%s' "$PASSWORD_DIR" "$1"; }

# Reads SPEC into PAPERLESS_URL and PASSWORD_DIR. PAPERLESS_URL from the
# environment wins, which is how the mirror is addressed with a production spec.
load_spec() {
    [[ -r "$SPEC" ]] || die "no spec at $SPEC."
    jq -e . "$SPEC" >/dev/null 2>&1 || die "$SPEC is not valid JSON."
    PAPERLESS_URL="${PAPERLESS_URL:-$(spec_value .url)}"
    PAPERLESS_URL="${PAPERLESS_URL%/}"
    [[ -n "$PAPERLESS_URL" ]] || die "the spec names no url."
    PASSWORD_DIR="$(expand_path "$(spec_value .password_dir)")"
    [[ -n "$PASSWORD_DIR" ]] || die "the spec names no password_dir."
    # shellcheck disable=SC2034 # read by the scripts that source this file
    ADMIN="${PAPERLESS_ADMIN:-admin}"
}

token_file() { printf '%s/%s.token' "$PASSWORD_DIR" "$1"; }

# USER's API token, fetched once from /api/token/ with the password file and
# cached next to it. Basic auth is not used, because it answers a right
# password differently from a wrong one without any throttle, so production's
# Caddy rejects it (docs/paperless.md). /api/token/ is throttled to 5 per
# minute and refuses a user with TOTP unless a code is given, so a user who
# enrolled TOTP before the first run needs a token made on the host:
#   docker exec -u paperless paperless_sdwa5 python3 manage.py drf_create_token USER
# with the third word of its output piped straight into the token file.
ensure_token() {
    local user="$1" password_file token
    [[ -s "$(token_file "$user")" ]] && return 0
    password_file="$(password_file "$user")"
    [[ -r "$password_file" ]] || die "no token or password file for $user in $PASSWORD_DIR."
    local attempt answer wait
    for (( attempt = 0; attempt < 4; attempt++ )); do
        answer="$(jq -cn --arg u "$user" --rawfile p "$password_file" '{username: $u, password: ($p | rtrimstr("\n"))}' \
            | curl --silent --show-error --max-time "$PAPERLESS_CURL_TIMEOUT" \
                --header 'Content-Type: application/json' --data-binary @- "$PAPERLESS_URL/api/token/")" || answer='{}'
        token="$(jq -r '.token // empty' <<< "$answer" 2>/dev/null || true)"
        [[ -n "$token" ]] && break
        # Throttled answers name the wait in seconds. Anything else is final.
        wait="$(jq -r '.detail // empty' <<< "$answer" 2>/dev/null | grep -o 'available in [0-9]*' | grep -o '[0-9]*$' || true)"
        [[ -n "$wait" ]] || break
        printf 'Token for %s throttled, waiting %s s.\n' "$user" "$wait" >&2
        sleep "$((wait + 1))"
    done
    [[ -n "$token" ]] || die "could not get a token for $user. Wrong password, TOTP enrolled, or throttled."
    printf '%s' "$token" > "$(token_file "$user")"
}

# curl_as USER CURL_ARGS... runs curl as USER with the token, handed over as a
# config file on a pipe so it never shows up in the process list.
curl_as() {
    local user="$1"
    shift
    ensure_token "$user"
    curl --silent --show-error --max-time "$PAPERLESS_CURL_TIMEOUT" \
        --config <(printf 'header = "Authorization: Token %s"\n' "$(< "$(token_file "$user")")") \
        --header 'Accept: application/json; version=10' "$@"
}

# api USER METHOD PATH [JSON] prints the body and fails on any status outside
# 2xx. A multipart upload passes its -F arguments after an empty JSON.
api() {
    local user="$1" method="$2" path="$3" body="${4:-}" status response
    shift 4 2>/dev/null || shift $#
    response="$(mktemp)"
    local -a data=("$@")
    [[ -n "$body" ]] && data+=(--header 'Content-Type: application/json' --data-binary "$body")
    status="$(curl_as "$user" --request "$method" "${data[@]}" \
        --output "$response" --write-out '%{http_code}' \
        "$PAPERLESS_URL$path")" || { rm -f -- "$response"; die "$method $path failed to connect."; }
    if [[ "$status" != 2* ]]; then
        printf '%s %s answered %s: %s\n' "$method" "$path" "$status" "$(head -c 400 "$response")" >&2
        rm -f -- "$response"
        return 1
    fi
    cat -- "$response"
    rm -f -- "$response"
}

# Every page of a list endpoint as one JSON array.
api_all() {
    local user="$1" path="$2" page=1 chunk out='[]' separator='?'
    [[ "$path" == *'?'* ]] && separator='&'
    while :; do
        chunk="$(api "$user" GET "$path${separator}page_size=100&page=$page")" || return 1
        out="$(jq -c --argjson add "$(jq -c '.results' <<< "$chunk")" '. + $add' <<< "$out")"
        [[ "$(jq -r '.next // empty' <<< "$chunk")" ]] || break
        page=$((page + 1))
    done
    printf '%s' "$out"
}
