#!/usr/bin/env bash
#
# Roll the project, task and ticket backlog into the Dolibarr ERP.
#
# The backlog lives in a JSON spec and this script makes the ERP match it. It is
# idempotent: every project, task and ticket is read first and skipped when it
# already carries the wanted values, so a second run is a no-op and a
# half-finished run can simply be repeated.
#
# Tickets carry the backlog, because their severity is what the UI shows as a
# priority. A task's priority is stored and displayed nowhere. Tasks stay
# supported for the projects that still hold them.
#
# It only ever creates, updates, closes and reopens. Nothing is deleted, and a
# project the spec does not name is never touched, so dropping an item from the
# spec leaves the ERP alone.
#
# A ticket entry with a `ref` is matched by that ref, in whatever project it
# sits, so its subject and its project can change. Its `status` (open, closed
# or canceled) and the spec's `dictionaries` go through the PmTools module
# (SdWa5/dolibarr-pmtools), because the core API can neither close a ticket the
# way the UI does nor write a ticket dictionary. A spec that uses neither runs
# without the module.
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

usage() { sed -n '3,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
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
        # A ticket message is HTML, and a line break in it is stored as
        # "<br>" followed by a newline, measured on 2026-10-15. Both forms
        # are reduced to the newline, so the spec can be written as plain text.
        def plain:
            unescape | gsub("\r"; "") | gsub("<br\\s*/?>\n?"; "\n");
        [ $des | to_entries[]
          | select(
              ($cur[.key] // null) as $c
              | if (.value | type) == "number"
                then
                    if $c == null or $c == "" then .value != 0
                    else (($c | tostring | tonumber?) // null) != .value
                    end
                else (($c // "") | tostring | plain) != (.value | tostring | plain)
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

# A new ticket's entry is laid over .ticket_defaults, so a spec states a common
# severity or assignee once. An existing ticket gets no defaults, or a spec
# entry that only adds to a ticket's message would also reset the severity and
# the assignee set in the UI. Its record fields as a compact JSON object: the
# message turns from plain text into the "<br>" lines the ERP stores, and the
# assignee from a login into the user id.
ticket_fields() {
    local entry="$1" defaults="$2" assignee user_id=""
    entry="$(printf '%s' "$defaults" | jq -c --argjson e "$entry" '. + $e')"
    assignee="$(printf '%s' "$entry" | jq -r '.assignee // ""')"
    if [[ -n "$assignee" ]]; then
        user_id="$(printf '%s' "$USERS" | jq -r --arg l "$assignee" \
            '[.[] | select(.login == $l)] | .[0].id // ""')"
        [[ -n "$user_id" ]] || die "the ticket assignee \"$assignee\" is no user login in the ERP."
    fi
    printf '%s' "$entry" | jq -c --arg u "$user_id" '
        def named($k): (.[$k] // "") | tostring | . != "";
        {}
        + (if named("message") then {message: (.message | split("\n") | join("<br>\n"))} else {} end)
        + (if named("severity") then {severity_code: .severity} else {} end)
        + (if named("type") then {type_code: .type} else {} end)
        + (if named("category") then {category_code: .category} else {} end)
        + (if $u != "" then {fk_user_assign: ($u | tonumber)} else {} end)'
}

# The PmTools module answers its own routes. Without it, Dolibarr answers 501
# or 404, so the first use is probed and a missing module named, rather than
# failing later with a bare HTTP error.
PMTOOLS_CHECKED=0
require_pmtools() {
    (( PMTOOLS_CHECKED )) && return 0
    local response
    response="$(api GET 'pmtools/dictionary/ticket_types')"
    printf '%s' "$response" | jq -e 'type == "array"' >/dev/null 2>&1 \
        || die "the spec uses $1, which needs the Dolibarr module PmTools 1.x enabled. The ERP answered: $(printf '%s' "$response" | head -c 200)"
    PMTOOLS_CHECKED=1
}

# The ticket dictionaries the spec maintains, under .dictionaries keyed by the
# PmTools name (ticket_types, ticket_severities, ticket_categories). An entry is
# matched by its code and only the fields it names are written, the same rule
# as for a project. Entries the spec does not name are left alone.
sync_dictionaries() {
    local names name entries count i entry code current wanted payload
    names="$(printf '%s' "$SPEC" | jq -r '.dictionaries // {} | keys[]')"
    [[ -n "$names" ]] || return 0
    require_pmtools dictionaries || exit 1
    for name in $names; do
        case "$name" in
            ticket_types|ticket_severities|ticket_categories) ;;
            *) die "unknown dictionary $name. Use ticket_types, ticket_severities or ticket_categories." ;;
        esac
        entries="$(api_list "pmtools/dictionary/$name")" || exit 1
        count="$(printf '%s' "$SPEC" | jq --arg n "$name" '.dictionaries[$n] | length')"
        for (( i = 0; i < count; i++ )); do
            entry="$(printf '%s' "$SPEC" | jq -c --arg n "$name" --argjson i "$i" \
                '.dictionaries[$n][$i] | .code = ((.code // "") | ascii_upcase)')"
            code="$(printf '%s' "$entry" | jq -r '.code')"
            [[ -n "$code" ]] || die "dictionary $name has an entry without a code."
            current="$(printf '%s' "$entries" | jq -c --arg c "$code" '[.[] | select(.code == $c)] | .[0] // null')"
            wanted="$(printf '%s' "$entry" | jq -c 'del(.code)')"
            if [[ "$current" == "null" ]]; then
                printf '%s' "$wanted" | jq -e '(.label // "") != ""' >/dev/null \
                    || die "dictionary $name entry $code is new and needs a label."
                printf '%-8s %s %s\n' "$( (( APPLY )) && echo create || echo would )" "$name" "$code"
                CREATED=$((CREATED + 1))
            else
                payload="$(diff_payload "$current" "$wanted")"
                if [[ "$payload" == "{}" ]]; then
                    printf '%-8s %s %s\n' "skip" "$name" "$code"
                    SKIPPED=$((SKIPPED + 1))
                    continue
                fi
                printf '%-8s %s %s, %s\n' "$( (( APPLY )) && echo update || echo would )" \
                    "$name" "$code" "$(printf '%s' "$payload" | jq -r 'keys | join(", ")')"
                UPDATED=$((UPDATED + 1))
            fi
            (( APPLY )) && { api_write POST "pmtools/dictionary/$name" "$entry" "$name $code" >/dev/null || exit 1; }
        done
    done
    printf '\n'
}

# The wanted end state of a ticket as a PmTools route, or nothing. Dolibarr's
# status 8 is closed and 9 is canceled. Switching between the two needs a
# reopen first, which the module insists on, so that case yields both steps.
status_steps() {
    local wanted="$1" current="$2"
    case "$wanted" in
        "") ;;
        open) [[ "$current" == 8 || "$current" == 9 ]] && printf 'reopen\n' ;;
        closed)
            [[ "$current" == 9 ]] && printf 'reopen\n'
            [[ "$current" != 8 ]] && printf 'close\n' ;;
        canceled)
            [[ "$current" == 8 ]] && printf 'reopen\n'
            [[ "$current" != 9 ]] && printf 'cancel\n' ;;
        *) die "unknown ticket status $wanted. Use open, closed or canceled." ;;
    esac
    return 0
}

# A severity, type or category code that is not in its dictionary is stored
# anyway and shows up blank in the UI, so every code the spec uses is checked
# against the ERP before anything is written.
check_ticket_codes() {
    local key="$1" dictionary="$2" used known unknown
    used="$(printf '%s' "$SPEC" | jq -c --arg k "$key" \
        '[(.ticket_defaults // {})[$k], (.projects[].tickets // [])[][$k]]
         | map(select(. != null and . != "")) | unique')"
    [[ "$used" == "[]" ]] && return 0
    known="$(api_list "setup/dictionary/$dictionary")" || exit 1
    # Codes the spec's own dictionaries add count as known, so a dry run of a
    # spec that introduces a type and uses it in the same run passes.
    known="$(printf '%s' "$known" | jq -c --argjson spec "$SPEC" --arg d "$dictionary" \
        '[.[].code] + [($spec.dictionaries // {})[$d] // [] | .[]
          | select((.active // 1) != 0) | (.code // "") | ascii_upcase] | unique')"
    unknown="$(jq -rn --argjson u "$used" --argjson k "$known" '$u - $k | join(", ")')"
    [[ -z "$unknown" ]] \
        || die "unknown ticket $key $unknown. The ERP knows $(jq -rn --argjson k "$known" '$k | join(", ")')."
}

# Runs the PmTools status routes STEPS (reopen, close, cancel, one per line)
# for ticket ID in order.
apply_status() {
    local id="$1" label="$2" steps="$3" step
    for step in $steps; do
        api_write POST "pmtools/tickets/$id/$step" '' "ticket $label" >/dev/null || exit 1
    done
}

# The tickets of one project. A ticket is matched by its ref when the entry has
# one, else by its exact subject within its project, the same way a task is
# matched by its label.
sync_tickets() {
    local project="$1" project_id="$2" title="$3"
    local count i entry subject ref status current near wanted payload id steps label new_id existing='[]'
    count="$(printf '%s' "$project" | jq '.tickets // [] | length')"
    (( count )) || return 0

    if [[ -n "$project_id" ]]; then
        existing="$(printf '%s' "$EXISTING_TICKETS" \
            | jq -c --arg p "$project_id" '[.[] | select((.fk_project | tostring) == $p)]')"
    fi

    for (( i = 0; i < count; i++ )); do
        entry="$(printf '%s' "$project" | jq -c --argjson i "$i" '.tickets[$i]')"
        subject="$(printf '%s' "$entry" | jq -r '.subject // ""')"
        ref="$(printf '%s' "$entry" | jq -r '.ref // ""')"
        status="$(printf '%s' "$entry" | jq -r '.status // ""')"
        [[ -n "$subject" || -n "$ref" ]] || die "project $title has a ticket without a subject."
        case "$status" in
            ""|open|closed|canceled) ;;
            *) die "ticket ${ref:-$subject} has the unknown status $status. Use open, closed or canceled." ;;
        esac
        [[ -n "$status" ]] && { require_pmtools "a ticket status" || exit 1; }

        if [[ -n "$ref" ]]; then
            current="$(printf '%s' "$EXISTING_TICKETS" | jq -c --arg r "$ref" '[.[] | select(.ref == $r)] | .[0] // null')"
            [[ "$current" != "null" ]] || die "no ticket $ref in the ERP. A ref names an existing ticket; leave it out to create one."
            [[ -n "$subject" ]] || subject="$ref"
        else
            current="$(printf '%s' "$existing" | jq -c --arg s "$subject" '
                def unescape: gsub("&quot;"; "\"") | gsub("&#0?39;"; "\u0027") | gsub("&amp;"; "&");
                [.[] | select((.subject // "" | unescape) == $s)] | .[0] // null')"
        fi
        if [[ "$current" == "null" ]]; then
            near="$(printf '%s' "$existing" | jq -r --arg s "$subject" \
                '[.[] | select((.subject // "" | ascii_downcase) == ($s | ascii_downcase))] | .[0].subject // ""')"
            [[ -n "$near" ]] && die "the spec says ticket \"$subject\" and project $title already has \"$near\". Refusing to create a second one."
        fi

        if [[ "$current" == "null" ]]; then
            wanted="$(ticket_fields "$entry" "$TICKET_DEFAULTS")" || exit 1
        else
            wanted="$(ticket_fields "$entry" '{}')" || exit 1
            # Matched by ref, the spec also states the subject and the project,
            # which is how a ticket is renamed or moved.
            if [[ -n "$ref" ]]; then
                wanted="$(printf '%s' "$wanted" | jq -c --argjson e "$entry" --arg p "$project_id" '
                    . + (if ($e.subject // "") != "" then {subject: $e.subject} else {} end)
                      + (if $p != "" then {fk_project: ($p | tonumber)} else {} end)')"
            fi
        fi

        if [[ "$current" == "null" ]]; then
            printf '%s' "$wanted" | jq -e 'has("message")' >/dev/null \
                || die "ticket $subject is new and needs a message, which Dolibarr requires."
            printf '  %-6s ticket %s\n' "$( (( APPLY )) && echo create || echo would )" "$subject"
            CREATED=$((CREATED + 1))
            if (( APPLY )); then
                # A ticket assigned in the UI moves to status 2, Assigned, while
                # Ticket::create() writes 0, Not read, unless it is told
                # otherwise. Read off the Dolibarr 23.0 source on 2026-10-15.
                payload="$(printf '%s' "$wanted" | jq -c \
                    --arg s "$subject" --arg p "$project_id" \
                    '. + {subject: $s, fk_project: ($p | tonumber)}
                     + (if has("fk_user_assign") then {status: 2} else {} end)')"
                new_id="$(api_write POST 'tickets' "$payload" "ticket $subject")" || exit 1
                [[ -z "$status" || "$status" == open ]] || apply_status "$new_id" "$subject" "$(status_steps "$status" 0)"
            fi
        else
            payload="$(diff_payload "$current" "$wanted")"
            id="$(printf '%s' "$current" | jq -r '.id')"
            steps="$(status_steps "$status" "$(printf '%s' "$current" | jq -r '.status // .fk_statut // "0"')")" || exit 1
            label="$subject${ref:+ ($ref)}"
            if [[ "$payload" == "{}" && -z "$steps" ]]; then
                printf '  %-6s ticket %s\n' "skip" "$label"
                SKIPPED=$((SKIPPED + 1))
            else
                printf '  %-6s ticket %s, %s\n' "$( (( APPLY )) && echo update || echo would )" "$label" \
                    "$(jq -rn --argjson p "$payload" --arg s "$steps" \
                        '[($p | keys[]), ($s | split("\n")[] | select(. != ""))] | join(", ")')"
                UPDATED=$((UPDATED + 1))
                if (( APPLY )); then
                    # A closed ticket is reopened before its fields change and
                    # closed after, so the close is the last thing that happens.
                    [[ "$steps" == reopen* ]] && { apply_status "$id" "$label" reopen || exit 1; steps="${steps#reopen}"; }
                    [[ "$payload" != "{}" ]] && { api_write PUT "tickets/$id" "$payload" "ticket $label" >/dev/null || exit 1; }
                    apply_status "$id" "$label" "$steps" || exit 1
                fi
            fi
        fi
    done
}

printf 'Dolibarr at %s\n' "$DOLIBARR_URL"
printf 'Spec %s\n' "$DOLIBARR_PM_SPEC"
(( APPLY )) || printf 'Dry run. Nothing is written. Pass --apply to write.\n'
printf '\n'

CREATED=0
UPDATED=0
SKIPPED=0

sync_dictionaries

EXISTING_PROJECTS="$(api_list 'projects?limit=500')" || exit 1

# Read every task once, rather than per project through projects/{id}/tasks.
# That endpoint answers an empty list for a project the API user is not a
# contact on, and a project created over this API has no contacts, because
# /projects/{id}/contact/{contactid}/{type} exposes DELETE only. Measured
# against the live instance on 2026-09-15: project 6 held one task, the global
# list saw it and the per-project endpoint did not. Reading the global list
# costs one request instead of one per project and does not filter that way.
EXISTING_TASKS="$(api_list 'tasks?limit=2000')" || exit 1

# Tickets, their dictionaries and the users are read only when the spec names a
# ticket, so a spec of projects and tasks costs no extra request.
EXISTING_TICKETS='[]'
TICKET_DEFAULTS="$(printf '%s' "$SPEC" | jq -c '.ticket_defaults // {}')"
USERS='[]'
if printf '%s' "$SPEC" | jq -e '[.projects[].tickets // [] | length] | add // 0 | . > 0' >/dev/null; then
    EXISTING_TICKETS="$(api_list 'tickets?limit=2000')" || exit 1
    check_ticket_codes severity ticket_severities
    check_ticket_codes type ticket_types
    check_ticket_codes category ticket_categories
    if printf '%s' "$SPEC" | jq -e \
        '[(.ticket_defaults // {}).assignee, (.projects[].tickets // [])[].assignee] | map(select(. != null and . != "")) | length > 0' \
        >/dev/null; then
        USERS="$(api_list 'users?limit=500')" || exit 1
    fi
fi

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

    sync_tickets "$project" "$project_id" "$title"

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
printf 'Nothing is ever deleted here. Closing a task stays a job for the Dolibarr UI.\n'
