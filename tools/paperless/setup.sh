#!/usr/bin/env bash
#
# Make a Paperless-ngx instance hold the groups, users, shared tags and sharing
# workflows a JSON spec names.
#
# It is idempotent. Every object is read first and skipped when it already
# carries the wanted values, so a second run is a no-op and a half-finished run
# can simply be repeated. It only creates and updates. Nothing is deleted, and
# an object the spec does not name is never touched.
#
# A user it creates gets a random password, written once into the spec's
# password_dir under the username and readable by the owner only. It is never
# printed. An existing user's password is never changed.
#
# A tag it creates has no owner, so every user of the instance can see and
# assign it. Each entry of `shares` becomes one workflow that grants a group
# view and edit rights on every document carrying the tag, triggered when a
# document is added and when it is updated, from every upload source. Removing
# the tag later does not take the rights back. A share without a tag grants the
# group those rights on every document of the instance when it is added,
# whoever uploads it, which is how the Verein instance shares everything with
# its board. See docs/paperless.md.
#
# It writes to the instance, so it is **dry-run by default** and a human starts
# it, the same split tools/dolibarr/sync-pm.sh uses.
#
# Usage:
#   tools/paperless/setup.sh SPEC            show what would change
#   tools/paperless/setup.sh --apply SPEC    write it
#   tools/paperless/setup.sh --help
#
# The format of SPEC is tools/paperless/paperless-spec.example.json. The real
# specs name people and stay out of the repository.
#
# Environment:
#   PAPERLESS_URL           base URL, default the spec's url
#   PAPERLESS_ADMIN         the superuser that writes, default admin
#   PAPERLESS_CURL_TIMEOUT  seconds, default 60

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/paperless/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '3,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

APPLY=0
CHANGES=0

# One line per object, then either the write or nothing.
report() { printf '%-7s %s\n' "$1" "$2"; [[ "$1" == skip ]] || CHANGES=$((CHANGES + 1)); }

write() {
    (( APPLY )) || return 0
    api "$ADMIN" "$@" >/dev/null || die "the write failed. Nothing after it was applied."
}

id_of() { jq -r --arg name "$2" '.[] | select(.'"$3"' == $name) | .id' <<< "$1"; }

ensure_groups() {
    local groups name wanted current id
    groups="$(api_all "$ADMIN" /api/groups/)"
    while IFS= read -r name; do
        wanted="$(jq -c --arg n "$name" '.groups[] | select(.name == $n) | .permissions | sort' "$SPEC")"
        id="$(id_of "$groups" "$name" name)"
        if [[ -z "$id" ]]; then
            report create "group $name"
            write POST /api/groups/ "$(jq -cn --arg n "$name" --argjson p "$wanted" '{name: $n, permissions: $p}')"
            continue
        fi
        current="$(jq -c --argjson id "$id" '.[] | select(.id == $id) | .permissions | sort' <<< "$groups")"
        if [[ "$current" == "$wanted" ]]; then
            report skip "group $name"
        else
            report update "group $name (permissions)"
            write PATCH "/api/groups/$id/" "$(jq -cn --argjson p "$wanted" '{permissions: $p}')"
        fi
    done < <(jq -r '.groups[]?.name' "$SPEC")
}

# Group names to ids. A group that exists only after this run's --apply is
# missing in a dry run, which is reported as a change rather than a failure.
group_ids() {
    local groups="$1" names="$2"
    jq -c --argjson names "$names" '[.[] | select(.name as $n | $names | index($n)) | .id] | sort' <<< "$groups"
}

ensure_users() {
    local users groups username entry wanted_groups id current wanted body
    users="$(api_all "$ADMIN" /api/users/)"
    groups="$(api_all "$ADMIN" /api/groups/)"
    while IFS= read -r username; do
        [[ "$username" =~ ^[A-Za-z0-9._@+-]+$ ]] || die "not a username: $username"
        entry="$(jq -c --arg u "$username" '.users[] | select(.username == $u)' "$SPEC")"
        wanted_groups="$(group_ids "$groups" "$(jq -c '.groups // []' <<< "$entry")")"
        wanted="$(jq -c --argjson g "$wanted_groups" \
            '{email: (.email // ""), first_name: (.first_name // ""), last_name: (.last_name // ""), groups: $g}' <<< "$entry")"
        id="$(id_of "$users" "$username" username)"
        if [[ -z "$id" ]]; then
            report create "user $username"
            (( APPLY )) || continue
            mkdir -p "$PASSWORD_DIR"
            [[ -s "$(password_file "$username")" ]] || random_password > "$(password_file "$username")"
            # The password is merged in by jq from its file, so it never sits
            # on a command line.
            body="$(jq -c --arg u "$username" --rawfile p "$(password_file "$username")" \
                '. + {username: $u, password: ($p | rtrimstr("\n")), is_staff: false, is_superuser: false, is_active: true}' <<< "$wanted")"
            write POST /api/users/ "$body"
            continue
        fi
        current="$(jq -c --argjson id "$id" \
            '.[] | select(.id == $id) | {email, first_name, last_name, groups: (.groups | sort)}' <<< "$users")"
        if [[ "$current" == "$wanted" ]]; then
            report skip "user $username"
        else
            report update "user $username"
            write PATCH "/api/users/$id/" "$wanted"
        fi
    done < <(jq -r '.users[]?.username' "$SPEC")
}

random_password() { head -c 24 /dev/urandom | base64 | tr -d '/+=\n'; }

ensure_tags() {
    local tags name id owner
    tags="$(api_all "$ADMIN" '/api/tags/?full_perms=true')"
    while IFS= read -r name; do
        id="$(id_of "$tags" "$name" name)"
        if [[ -z "$id" ]]; then
            report create "tag $name"
            write POST /api/tags/ "$(jq -cn --arg n "$name" '{name: $n, owner: null, matching_algorithm: 0}')"
            continue
        fi
        owner="$(jq -r --argjson id "$id" '.[] | select(.id == $id) | .owner // empty' <<< "$tags")"
        if [[ -z "$owner" ]]; then
            report skip "tag $name"
        else
            report update "tag $name (owner removed)"
            write PATCH "/api/tags/$id/" '{"owner": null}'
        fi
    done < <(jq -r '.tags[]?.name' "$SPEC")
}

# The workflow a share stands for, in the shape the API returns, so the
# comparison is a plain string match.
share_workflow() {
    jq -cn --arg name "$1" --argjson tag "$2" --argjson group "$3" '{
        name: $name, enabled: true,
        triggers: (if $tag == null then [2] else [2, 3] end
            | map({type: ., sources: [1, 2, 3, 4], matching_algorithm: 0, filter_has_tags: ([$tag] - [null])})),
        actions: [{type: 1, assign_view_groups: [$group], assign_change_groups: [$group]}]
    }'
}

normalise_workflow() {
    jq -c '{
        name, enabled,
        triggers: (.triggers | sort_by(.type) | map({type, sources: (.sources | map(tonumber) | sort), matching_algorithm, filter_has_tags: (.filter_has_tags | sort)})),
        actions: (.actions | map({type, assign_view_groups: (.assign_view_groups | sort), assign_change_groups: (.assign_change_groups | sort)}))
    }'
}

ensure_shares() {
    local workflows tags groups share tag group name tag_id group_id wanted id current
    workflows="$(api_all "$ADMIN" /api/workflows/)"
    tags="$(api_all "$ADMIN" /api/tags/)"
    groups="$(api_all "$ADMIN" /api/groups/)"
    while IFS= read -r share; do
        tag="$(jq -r '.tag // empty' <<< "$share")"
        group="$(jq -r '.group' <<< "$share")"
        if [[ -n "$tag" ]]; then
            name="Share tag $tag with group $group"
            tag_id="$(id_of "$tags" "$tag" name)"
        else
            name="Share all documents with group $group"
            tag_id=null
        fi
        group_id="$(id_of "$groups" "$group" name)"
        id="$(id_of "$workflows" "$name" name)"
        if [[ -z "$tag_id" || -z "$group_id" ]]; then
            (( APPLY )) && die "$name: tag or group does not exist."
            if [[ -n "$id" ]]; then report update "workflow \"$name\""; else report create "workflow \"$name\""; fi
            continue
        fi
        wanted="$(share_workflow "$name" "$tag_id" "$group_id")"
        if [[ -z "$id" ]]; then
            report create "workflow \"$name\""
            write POST /api/workflows/ "$(jq -c '. + {order: 0}' <<< "$wanted")"
            continue
        fi
        current="$(jq -c --argjson id "$id" '.[] | select(.id == $id)' <<< "$workflows" | normalise_workflow)"
        if [[ "$current" == "$(normalise_workflow <<< "$wanted")" ]]; then
            report skip "workflow \"$name\""
        else
            report update "workflow \"$name\""
            write PUT "/api/workflows/$id/" "$(jq -c '. + {order: 0}' <<< "$wanted")"
        fi
    done < <(jq -c '.shares[]?' "$SPEC")
}

main() {
    SPEC=""
    while (( $# )); do
        case "$1" in
            --apply) APPLY=1 ;;
            -h|--help) usage; return 0 ;;
            -*) die "unknown option: $1. Try --help." ;;
            *) SPEC="$1" ;;
        esac
        shift
    done
    [[ -n "$SPEC" ]] || { usage; exit 2; }
    load_spec

    printf 'Instance %s\n' "$PAPERLESS_URL"
    ensure_groups
    ensure_users
    ensure_tags
    ensure_shares
    if (( APPLY )); then
        printf '%s change(s) written.\n' "$CHANGES"
    else
        printf '%s change(s). Dry run, nothing written. Run with --apply to write.\n' "$CHANGES"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
