#!/usr/bin/env bash
#
# Roll the new postal address through the Dolibarr ERP.
#
# Three person records carry it and all three are writable over the REST API.
# The organisation's own record is **not**: `/setup/company` exposes GET only,
# measured against the live instance on 2026-09-14, so Home, Setup, Company is a
# UI step and this script only reminds you of it.
#
# The script is idempotent. Every record is read first and skipped when it
# already carries the new value, so a second run is a no-op and a half-finished
# run can simply be repeated.
#
# It writes to production, so it is **dry-run by default** and a human starts
# it, the same split tools/shopware/set-address.sh uses.
#
# Usage:
#   tools/dolibarr/set-address.sh            show what would change
#   tools/dolibarr/set-address.sh --apply    write it
#   tools/dolibarr/set-address.sh --help
#
# Environment: the same DOLIBARR_URL and DOLIBARR_TOKEN_FILE that doli.sh reads.

set -uo pipefail

DOLIBARR_URL="${DOLIBARR_URL:-https://erp.sdwa5.org}"
DOLIBARR_TOKEN_FILE="${DOLIBARR_TOKEN_FILE:-$HOME/.config/sdwa5-dolibarr-token}"
DOLI_CURL_TIMEOUT="${DOLI_CURL_TIMEOUT:-30}"
API_ROOT="$DOLIBARR_URL/api/index.php"

NEW_ADDRESS="Egitlweg 6"
NEW_ZIP="5322"
NEW_TOWN="Hof bei Salzburg"

APPLY=0

usage() { sed -n '3,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'set-address.sh: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
    --apply) APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) die "unknown option: ${1}. Try --help." ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -r "$DOLIBARR_TOKEN_FILE" ]] || die "no API key at $DOLIBARR_TOKEN_FILE. See docs/dolibarr.md."

# The key goes to curl through a config file on stdin, never as an argument.
api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(--silent --show-error --config -
        --max-time "$DOLI_CURL_TIMEOUT"
        -X "$method"
        --header 'Accept: application/json'
        --header 'Content-Type: application/json'
        --url "$API_ROOT/$path")
    [[ -n "$body" ]] && args+=(--data "$body")
    printf 'header = "DOLAPIKEY: %s"\n' "$(cat "$DOLIBARR_TOKEN_FILE")" | curl "${args[@]}"
}

CHANGED=0
SKIPPED=0

# update_record ENDPOINT ID EXPECTED_SURNAME LABEL [town-only]
#
# The id is pinned and the surname is verified before anything is written. A
# pinned id alone would silently rewrite whoever happens to sit at that id after
# a merge or a re-import, and a name lookup alone could match the wrong person.
update_record() {
    local endpoint="$1" id="$2" expect="$3" label="$4" town_only="${5:-0}"
    local record actual address zip town payload

    record="$(api GET "$endpoint/$id")"
    printf '%s' "$record" | jq -e 'type == "object" and has("id")' >/dev/null 2>&1 \
        || die "$label: $endpoint/$id did not return a record"

    # A member and a user carry lastname; a thirdparty carries name.
    actual="$(printf '%s' "$record" | jq -r '.lastname // .name // ""')"
    [[ "$actual" == *"$expect"* ]] \
        || die "$label: $endpoint/$id is \"$actual\", expected a record for $expect. Refusing to write."

    address="$(printf '%s' "$record" | jq -r '.address // ""')"
    zip="$(printf '%s' "$record" | jq -r '.zip // ""')"
    town="$(printf '%s' "$record" | jq -r '.town // ""')"

    if [[ "$town" == "$NEW_TOWN" ]] \
       && { (( town_only )) || { [[ "$address" == "$NEW_ADDRESS" && "$zip" == "$NEW_ZIP" ]]; }; }; then
        printf '  %-8s %s, already current\n' "skip" "$label"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    if (( town_only )); then
        printf '  %-8s %s, town %s -> %s\n' "$( (( APPLY )) && echo update || echo would )" \
            "$label" "$town" "$NEW_TOWN"
        payload="$(jq -c -n --arg t "$NEW_TOWN" '{town: $t}')"
    else
        printf '  %-8s %s, %s %s -> %s %s\n' "$( (( APPLY )) && echo update || echo would )" \
            "$label" "$address" "$town" "$NEW_ADDRESS" "$NEW_TOWN"
        payload="$(jq -c -n --arg a "$NEW_ADDRESS" --arg z "$NEW_ZIP" --arg t "$NEW_TOWN" \
            '{address: $a, zip: $z, town: $t}')"
    fi

    CHANGED=$((CHANGED + 1))
    (( APPLY )) || return 0

    local response
    response="$(api PUT "$endpoint/$id" "$payload")"
    # Dolibarr answers a successful PUT with the id of the record, which is a
    # bare number rather than an object. `has("error")` on a number is a jq
    # error, so checking that first would call every success a failure. Only an
    # object can carry an error, and an empty body is a success too.
    if [[ -n "${response//[[:space:]]/}" ]]; then
        printf '%s' "$response" \
            | jq -e 'if type == "object" then (has("error") | not) else true end' >/dev/null 2>&1 \
            || die "$label: write failed: $(printf '%s' "$response" | head -c 200)"
    fi
}

printf 'Dolibarr at %s\n' "$DOLIBARR_URL"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

update_record "members"      "2"  "Example" "member Ada Example"
update_record "users"        "2"  "Example" "user Ada Example"
# Example Supplies's street and postcode were already right; only the town was wrong,
# and that wrong town is where "Elsenwang" entered the documentation in the
# first place. Elsenwang is a hamlet inside the municipality of Hof bei
# Salzburg, so it is not a postal town.
update_record "thirdparties" "10" "Example Supplies"   "thirdparty Example Supplies" 1

printf '\n%d to change, %d already current.\n' "$CHANGED" "$SKIPPED"
printf '\nThe organisation record is not part of this. /setup/company is GET only,\n'
printf 'so set it under Home, Setup, Company/Organization:\n'
printf '  %s, %s %s\n' "$NEW_ADDRESS" "$NEW_ZIP" "$NEW_TOWN"
