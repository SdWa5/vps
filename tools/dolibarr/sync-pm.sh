#!/usr/bin/env bash
#
# Roll the project and task backlog into the Dolibarr ERP.
#
# The backlog lives in a JSON spec and this script makes the ERP match it. It is
# idempotent: every project and every task is read first and skipped when it
# already carries the wanted values, so a second run is a no-op and a
# half-finished run can simply be repeated.
#
# It only ever creates and updates. Nothing is deleted, and a project the spec
# does not name is never touched, so dropping an item from the spec leaves the
# ERP alone and closing a task stays a job for the UI.
#
# It writes to production, so it is **dry-run by default** and a human starts
# it, the same split tools/dolibarr/set-address.sh uses.
#
# Usage:
#   tools/dolibarr/sync-pm.sh            show what would change
#   tools/dolibarr/sync-pm.sh --apply    write it
#   tools/dolibarr/sync-pm.sh --help
#
# Environment:
#   DOLIBARR_URL          base URL, default https://erp.sdwa5.org
#   DOLIBARR_TOKEN_FILE   file holding the API key, default ~/.config/sdwa5-dolibarr-token
#   DOLIBARR_PM_SPEC      the backlog, default tools/dolibarr/pm-spec.json
#   DOLI_CURL_TIMEOUT     seconds, default 30

set -uo pipefail

DOLIBARR_URL="${DOLIBARR_URL:-https://erp.sdwa5.org}"
DOLIBARR_TOKEN_FILE="${DOLIBARR_TOKEN_FILE:-$HOME/.config/sdwa5-dolibarr-token}"
DOLI_CURL_TIMEOUT="${DOLI_CURL_TIMEOUT:-30}"
API_ROOT="$DOLIBARR_URL/api/index.php"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOLIBARR_PM_SPEC="${DOLIBARR_PM_SPEC:-$SCRIPT_DIR/pm-spec.json}"

# The fields this script owns. Anything else on a record is left alone, so a
# value set by hand in the UI survives unless the spec names that field.
PROJECT_FIELDS=(description date_start date_end public usage_task)
TASK_FIELDS=(description date_start date_end progress planned_workload priority)

APPLY=0

usage() { sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() { printf 'sync-pm.sh: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
    --apply) APPLY=1 ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) die "unknown option: ${1}. Try --help." ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -r "$DOLIBARR_TOKEN_FILE" ]] || die "no API key at $DOLIBARR_TOKEN_FILE. See docs/dolibarr.md."
[[ -r "$DOLIBARR_PM_SPEC" ]] || die "no spec at $DOLIBARR_PM_SPEC. Copy pm-spec.example.json and fill it in."

SPEC="$(cat "$DOLIBARR_PM_SPEC")"
printf '%s' "$SPEC" | jq -e '.projects | type == "array"' >/dev/null 2>&1 \
    || die "$DOLIBARR_PM_SPEC does not parse, or has no .projects array."
printf '%s' "$SPEC" | jq -e '[.projects[] | select((.title // "") == "")] | length == 0' >/dev/null 2>&1 \
    || die "every project in the spec needs a non-empty title."

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

# A Dolibarr list endpoint answers an empty collection with a 404 object rather
# than with an empty array, so "nothing there yet" arrives looking like a
# failure. Anything else that is not an array is a real error.
api_list() {
    local path="$1" response
    response="$(api GET "$path")"

    if printf '%s' "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
        printf '%s' "$response"
        return 0
    fi
    if printf '%s' "$response" | jq -e 'type == "object" and (.error.code == 404)' >/dev/null 2>&1; then
        printf '[]'
        return 0
    fi
    die "GET $path did not return a list: $(printf '%s' "$response" | head -c 200)"
}

# A successful Dolibarr write answers with the bare id of the record, which is a
# number rather than an object. `has("error")` on a number is a jq error, so
# checking that first would call every success a failure. Only an object can
# carry an error, and an empty body is a success too.
api_write() {
    local method="$1" path="$2" body="$3" label="$4" response
    response="$(api "$method" "$path" "$body")"
    if [[ -n "${response//[[:space:]]/}" ]]; then
        printf '%s' "$response" \
            | jq -e 'if type == "object" then (has("error") | not) else true end' >/dev/null 2>&1 \
            || die "$label: $method $path failed: $(printf '%s' "$response" | head -c 200)"
    fi
    printf '%s' "$response" | tr -d '"[:space:]'
}

# A project created over the API is a draft, where every project made in the UI
# is open. `notrigger` is mandatory on this endpoint: without it Dolibarr answers
# 400 and names the field, measured on 2026-09-15.
validate_project() {
    local id="$1" label="$2"
    printf '  %-6s project %s, draft -> open\n' "valid" "$label"
    api_write POST "projects/$id/validate" '{"notrigger":0}' "project $label" >/dev/null
}

# A date in the spec is written as YYYY-MM-DD and stored by Dolibarr as epoch
# seconds, which is also what it reads back, so the conversion happens here and
# the comparison downstream is between two integers.
to_epoch() {
    local value="$1"
    [[ -z "$value" || "$value" == "null" ]] && return 0
    date -u -d "$value 00:00:00" +%s 2>/dev/null \
        || die "not a date: $value. Write dates as YYYY-MM-DD."
}

# The subset of DESIRED that CURRENT does not already carry, as a compact JSON
# object. Empty object means nothing to write.
#
# Dolibarr hands numbers back as strings and an unset number back as null, so a
# plain inequality would report a change on every run and this would never be
# idempotent. Numbers are therefore compared numerically, and an unset number on
# the server counts as zero.
diff_payload() {
    jq -c -n --argjson cur "$1" --argjson des "$2" '
        # Dolibarr HTML-escapes what it stores, so "Allen & Heath" comes back as
        # "Allen &amp; Heath". Both sides are decoded before they are compared,
        # or a description holding an ampersand would be rewritten on every run.
        # "&amp;" is decoded last, so "&amp;lt;" does not turn into "<".
        def unescape:
            gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"")
            | gsub("&#0?39;"; "\u0027") | gsub("&nbsp;"; " ") | gsub("&amp;"; "&");
        [ $des | to_entries[]
          | select(
              ($cur[.key] // null) as $c
              | if (.value | type) == "number"
                then
                    if $c == null or $c == "" then .value != 0
                    else (($c | tostring | tonumber?) // null) != .value
                    end
                else (($c // "") | tostring | unescape) != (.value | tostring | unescape)
                end
            )
        ] | from_entries'
}

# The fields of a spec entry this script owns, as a compact JSON object, with
# dates converted and empty values dropped. Dropping them is what lets an entry
# name only the fields it cares about and leave the rest of the record alone.
wanted_fields() {
    local entry="$1" field value out='{}'
    shift
    for field in "$@"; do
        value="$(printf '%s' "$entry" | jq -r --arg f "$field" '.[$f] // "" | tostring')"
        [[ -z "$value" ]] && continue
        case "$field" in
            date_start|date_end)
                value="$(to_epoch "$value")" || exit 1
                [[ -z "$value" ]] && continue
                out="$(printf '%s' "$out" | jq -c --arg f "$field" --argjson v "$value" '.[$f] = $v')"
                ;;
            progress|planned_workload|priority|public)
                out="$(printf '%s' "$out" | jq -c --arg f "$field" --argjson v "$value" '.[$f] = $v')"
                ;;
            *)
                out="$(printf '%s' "$out" | jq -c --arg f "$field" --arg v "$value" '.[$f] = $v')"
                ;;
        esac
    done
    printf '%s' "$out"
}

CREATED=0
UPDATED=0
SKIPPED=0

printf 'Dolibarr at %s\n' "$DOLIBARR_URL"
printf 'Spec %s\n' "$DOLIBARR_PM_SPEC"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

EXISTING_PROJECTS="$(api_list 'projects?limit=500')" || exit 1

# Read every task once, rather than per project through projects/{id}/tasks.
# That endpoint answers an empty list for a project the API user is not a
# contact on, and a project created over this API has no contacts, because
# /projects/{id}/contact/{contactid}/{type} exposes DELETE only. Measured
# against the live instance on 2026-09-15: project 6 held one task, the global
# list saw it and the per-project endpoint did not. Reading the global list
# costs one request instead of one per project and does not filter that way.
EXISTING_TASKS="$(api_list 'tasks?limit=2000')" || exit 1

project_count="$(printf '%s' "$SPEC" | jq '.projects | length')"
for (( p = 0; p < project_count; p++ )); do
    project="$(printf '%s' "$SPEC" | jq -c --argjson i "$p" '.projects[$i]')"
    title="$(printf '%s' "$project" | jq -r '.title')"

    current="$(printf '%s' "$EXISTING_PROJECTS" \
        | jq -c --arg t "$title" '[.[] | select(.title == $t)] | .[0] // null')"

    # A title that differs only in case is almost certainly the same project
    # typed twice. Creating the second one is the mistake that cannot be undone
    # over this API, so it aborts instead.
    if [[ "$current" == "null" ]]; then
        near="$(printf '%s' "$EXISTING_PROJECTS" | jq -r --arg t "$title" \
            '[.[] | select((.title | ascii_downcase) == ($t | ascii_downcase))] | .[0].title // ""')"
        [[ -n "$near" ]] && die "the spec says \"$title\" and the ERP already has \"$near\". Refusing to create a second one."
    fi

    wanted="$(wanted_fields "$project" "${PROJECT_FIELDS[@]}")" || exit 1
    project_id=""

    if [[ "$current" == "null" ]]; then
        printf '%-8s project %s\n' "$( (( APPLY )) && echo create || echo would )" "$title"
        CREATED=$((CREATED + 1))
        if (( APPLY )); then
            payload="$(printf '%s' "$wanted" | jq -c --arg t "$title" \
                '{usage_task: 1} + . + {ref: "auto", title: $t}')"
            project_id="$(api_write POST 'projects' "$payload" "project $title")" || exit 1
            [[ -n "$project_id" ]] || die "project $title: create returned no id"
            validate_project "$project_id" "$title" || exit 1
        fi
    else
        project_id="$(printf '%s' "$current" | jq -r '.id')"
        # A project created by an earlier run of this script, before it learned
        # to validate, is still a draft. Every project made in the UI is open.
        if (( APPLY )) && [[ "$(printf '%s' "$current" | jq -r '.statut // "1"')" == "0" ]]; then
            validate_project "$project_id" "$title" || exit 1
        fi
        payload="$(diff_payload "$current" "$wanted")"
        if [[ "$payload" == "{}" ]]; then
            printf '%-8s project %s\n' "skip" "$title"
            SKIPPED=$((SKIPPED + 1))
        else
            printf '%-8s project %s, %s\n' "$( (( APPLY )) && echo update || echo would )" \
                "$title" "$(printf '%s' "$payload" | jq -r 'keys | join(", ")')"
            UPDATED=$((UPDATED + 1))
            (( APPLY )) && { api_write PUT "projects/$project_id" "$payload" "project $title" >/dev/null || exit 1; }
        fi
    fi

    task_count="$(printf '%s' "$project" | jq '.tasks // [] | length')"
    (( task_count )) || continue

    # A project that does not exist yet has no tasks to compare against, and in
    # a dry run it has no id either, so the whole list reads as new.
    existing_tasks='[]'
    if [[ -n "$project_id" ]]; then
        existing_tasks="$(printf '%s' "$EXISTING_TASKS" \
            | jq -c --arg p "$project_id" '[.[] | select((.fk_project | tostring) == $p)]')"
    fi

    for (( t = 0; t < task_count; t++ )); do
        task="$(printf '%s' "$project" | jq -c --argjson i "$t" '.tasks[$i]')"
        label="$(printf '%s' "$task" | jq -r '.label // ""')"
        [[ -n "$label" ]] || die "project $title has a task without a label."

        task_current="$(printf '%s' "$existing_tasks" \
            | jq -c --arg l "$label" '[.[] | select(.label == $l)] | .[0] // null')"
        task_wanted="$(wanted_fields "$task" "${TASK_FIELDS[@]}")" || exit 1

        if [[ "$task_current" == "null" ]]; then
            printf '  %-6s task %s\n' "$( (( APPLY )) && echo create || echo would )" "$label"
            CREATED=$((CREATED + 1))
            if (( APPLY )); then
                payload="$(printf '%s' "$task_wanted" | jq -c \
                    --arg l "$label" --arg p "$project_id" \
                    '. + {ref: "auto", label: $l, fk_project: ($p | tonumber)}')"
                api_write POST 'tasks' "$payload" "task $label" >/dev/null || exit 1
            fi
        else
            payload="$(diff_payload "$task_current" "$task_wanted")"
            if [[ "$payload" == "{}" ]]; then
                printf '  %-6s task %s\n' "skip" "$label"
                SKIPPED=$((SKIPPED + 1))
            else
                printf '  %-6s task %s, %s\n' "$( (( APPLY )) && echo update || echo would )" \
                    "$label" "$(printf '%s' "$payload" | jq -r 'keys | join(", ")')"
                UPDATED=$((UPDATED + 1))
                (( APPLY )) && { api_write PUT "tasks/$(printf '%s' "$task_current" | jq -r '.id')" \
                    "$payload" "task $label" >/dev/null || exit 1; }
            fi
        fi
    done
done

printf '\n%d to create, %d to update, %d already current.\n' "$CREATED" "$UPDATED" "$SKIPPED"
printf 'Nothing is ever deleted here. Closing a task is a job for the Dolibarr UI.\n'
