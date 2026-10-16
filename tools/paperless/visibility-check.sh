#!/usr/bin/env bash
#
# Prove that a Paperless-ngx instance shows each user exactly the documents the
# spec says it should, by uploading test documents and looking as every user.
#
# Every user of the spec uploads one private document, and every user in a
# share's group also uploads one carrying the share's tag. Then each user lists
# the test documents and searches their full text, and both must show exactly
# this set:
#   - the user's own documents
#   - every document carrying a share's tag, when the user is in that share's group
# A user who sees one document more is a leak, one less a broken share.
#
# The test documents are tiny generated PDFs titled "visibility-check <run id>
# ...". They are deleted and purged from the trash at the end, also after a
# failure, so the check leaves nothing behind. It needs the password files that
# setup.sh wrote, and it writes to the instance, so a human starts it.
#
# Usage:
#   tools/paperless/visibility-check.sh SPEC
#   tools/paperless/visibility-check.sh --help
#
# Exit status 0 when every user sees exactly the expected set, 1 otherwise.
#
# Environment:
#   PAPERLESS_URL           base URL, default the spec's url
#   PAPERLESS_ADMIN         the superuser that cleans up, default admin
#   PAPERLESS_CURL_TIMEOUT  seconds, default 60
#   PAPERLESS_TASK_WAIT     seconds to wait for one upload to be consumed, default 300

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/paperless/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

TASK_WAIT="${PAPERLESS_TASK_WAIT:-300}"
WORK_DIR=""
UPLOADED=()

# A one-page PDF holding TEXT, with a correct cross-reference table, so the
# consumer accepts it and its checksum is unique per document.
make_pdf() {
    local text="$1" out="$2" stream object offset=0
    local -a objects offsets
    stream="BT /F1 12 Tf 72 720 Td ($text) Tj ET"
    objects=(
        '<< /Type /Catalog /Pages 2 0 R >>'
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>'
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'
        "<< /Length ${#stream} >>"$'\n'"stream"$'\n'"$stream"$'\n'"endstream"
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    )
    {
        printf '%%PDF-1.4\n'
        offset=9
        for object in "${!objects[@]}"; do
            offsets+=("$offset")
            local chunk
            chunk="$((object + 1)) 0 obj"$'\n'"${objects[$object]}"$'\n'"endobj"$'\n'
            printf '%s' "$chunk"
            offset=$((offset + ${#chunk}))
        done
        printf 'xref\n0 %d\n0000000000 65535 f \n' "$(( ${#objects[@]} + 1 ))"
        for object in "${offsets[@]}"; do printf '%010d 00000 n \n' "$object"; done
        printf 'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' "$(( ${#objects[@]} + 1 ))" "$offset"
    } > "$out"
}

# Uploads as USER and waits for the consumer. Prints the new document's id.
upload() {
    local user="$1" title="$2" tag_id="$3" file task attempt result status
    file="$WORK_DIR/$(tr ' ' '-' <<< "$title").pdf"
    make_pdf "$title" "$file"
    local -a fields=(-F "document=@$file;type=application/pdf" -F "title=$title")
    [[ -n "$tag_id" ]] && fields+=(-F "tags=$tag_id")
    task="$(api "$user" POST /api/documents/post_document/ "" "${fields[@]}" | tr -d '"')" \
        || die "$user could not upload."
    for (( attempt = 0; attempt < TASK_WAIT; attempt += 2 )); do
        result="$(api "$user" GET "/api/tasks/?task_id=$task")"
        status="$(jq -r '.results[0].status // empty' <<< "$result")"
        case "$status" in
            success) jq -r '.results[0].related_document_ids[0]' <<< "$result"; return 0 ;;
            failure|revoked) die "the upload of \"$title\" failed: $(jq -c '.results[0].result_data' <<< "$result")" ;;
        esac
        sleep 2
    done
    die "\"$title\" was not consumed within $TASK_WAIT s."
}

# Delete, then purge from the trash, so the next run starts clean and no test
# document lingers for 30 days.
cleanup() {
    [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
    (( ${#UPLOADED[@]} )) || return 0
    local id ids
    for id in "${UPLOADED[@]}"; do
        api "$ADMIN" DELETE "/api/documents/$id/" >/dev/null || true
    done
    ids="$(printf '%s\n' "${UPLOADED[@]}" | jq -cs .)"
    api "$ADMIN" POST /api/trash/ "$(jq -cn --argjson d "$ids" '{action: "empty", documents: $d}')" >/dev/null \
        || printf 'Could not purge the test documents %s from the trash.\n' "$ids" >&2
    printf 'Removed %s test document(s).\n' "${#UPLOADED[@]}"
}

in_group() { jq -e --arg u "$1" --arg g "$2" '.users[] | select(.username == $u) | .groups // [] | index($g)' "$SPEC" >/dev/null; }

main() {
    case "${1:-}" in
        -h|--help) usage; return 0 ;;
        "") usage; exit 2 ;;
    esac
    SPEC="$1"
    load_spec

    local run tags users user tag group tag_id title id expected seen searched failed=0
    run="$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    WORK_DIR="$(mktemp -d)"
    trap cleanup EXIT
    tags="$(api_all "$ADMIN" /api/tags/)"
    mapfile -t users < <(jq -r '.users[].username' "$SPEC")

    # Who uploaded what, as lines of "id<TAB>title<TAB>owner<TAB>share group or -".
    local documents=""
    printf 'Uploading test documents (run %s).\n' "$run"
    for user in "${users[@]}"; do
        title="visibility-check $run $user private"
        id="$(upload "$user" "$title" "")"
        UPLOADED+=("$id")
        documents+="$id"$'\t'"$title"$'\t'"$user"$'\t-\n'
        while IFS=$'\t' read -r tag group; do
            in_group "$user" "$group" || continue
            tag_id="$(jq -r --arg n "$tag" '.[] | select(.name == $n) | .id' <<< "$tags")"
            [[ -n "$tag_id" ]] || die "the tag $tag does not exist. Run setup.sh --apply first."
            title="visibility-check $run $user shared $tag"
            id="$(upload "$user" "$title" "$tag_id")"
            UPLOADED+=("$id")
            documents+="$id"$'\t'"$title"$'\t'"$user"$'\t'"$group"$'\n'
        done < <(jq -r '.shares[]? | [.tag, .group] | @tsv' "$SPEC")
    done

    for user in "${users[@]}"; do
        expected="$(while IFS=$'\t' read -r id title owner group; do
            [[ -n "$id" ]] || continue
            if [[ "$owner" == "$user" ]] || { [[ "$group" != - ]] && in_group "$user" "$group"; }; then
                printf '%s\n' "$id"
            fi
        done <<< "$documents" | sort -n | paste -sd' ')"
        seen="$(api_all "$user" "/api/documents/?title__icontains=visibility-check%20$run&fields=id" \
            | jq -r '.[].id' | sort -n | paste -sd' ')"
        searched="$(api_all "$user" "/api/documents/?query=$run&fields=id" \
            | jq -r '.[].id' | sort -n | paste -sd' ')"
        if [[ "$seen" == "$expected" && "$searched" == "$expected" ]]; then
            printf 'ok      %s sees [%s]\n' "$user" "$expected"
        else
            printf 'FAIL    %s expected [%s], list shows [%s], search shows [%s]\n' \
                "$user" "$expected" "$seen" "$searched"
            failed=1
        fi
    done
    return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
