#!/usr/bin/env bash
#
# Upload folder trees into Paperless-ngx as one user. Dry-run by default.
#
# Every file below each ROOT is skipped, found in Paperless by its SHA-256
# checksum, or uploaded as USER. The uploader becomes the owner, so every
# document starts out private. Each folder between ROOT and the file becomes a
# tag, plus "Offen" when the name contains _OFFEN. A missing tag is created as
# USER and is therefore private as well. A name YYYY-MM-DD_rest.ext gives that
# created date and the title "rest", with _ and - as spaces and _OFFEN dropped.
# Any other name keeps its basename as the title, and Paperless dates the
# document from its content. Titles are cut to 128 characters.
#
# Output lines are tab-separated:
#   stdout  exists ID SHA256 PATH                         held already
#   stdout  would-create-tag NAME                         dry-run, once per tag
#   stdout  would-upload SHA256 PATH TITLE CREATED TAGS   dry-run, TAGS joined by /
#   stdout  tag ID NAME                                   --apply created the tag
#   stdout  uploaded ID SHA256 PATH                       --apply
#   stderr  skip junk|secret|name|local:MIME|duplicate PATH
#
# A rerun resumes through the exists lines. A dry-run after the upload is the
# verification, and its exists lines name the originals that are held.
#
# Usage:
#   tools/paperless/upload-tree.sh [--apply] [--limit N] SPEC USER ROOT...
#   tools/paperless/upload-tree.sh --help
#
#   --apply     create tags and upload. Without it nothing is written
#   --limit N   stop after N uploads, or after N would-upload lines in a dry-run
#
# USER needs a token file next to the spec's password files. A user with TOTP
# gets one with drf_create_token, as lib.sh describes.
#
# Environment:
#   PAPERLESS_URL           base URL, default the spec's url
#   PAPERLESS_CURL_TIMEOUT  seconds per request, default 1800 here
#   PAPERLESS_TASK_WAIT     seconds to wait for one upload to be consumed, default 900 here

set -euo pipefail
umask 077
export LC_ALL=C.UTF-8

# A home uplink sent 36 KB/s on 2026-11-04, so a 30 MB scan took ca. 14 minutes
# to send, and its OCR comes on top. Both limits are well above lib.sh's defaults.
: "${PAPERLESS_CURL_TIMEOUT:=1800}" "${PAPERLESS_TASK_WAIT:=900}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tools/paperless/lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() { sed -n '3,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# Tag name to id, as USER sees them. A dry-run marks a missing tag as "new".
declare -A TAGS=()
# Checksums seen in this run, to report a second copy in a dry-run.
declare -A SEEN=()
# Set by describe and tags_for.
TITLE=""
CREATED=""
FILE_TAGS=()

# Why PATH is not uploaded, or nothing when it is. curl's quoted -F filename
# cannot carry a double quote or a backslash, and the output lines cannot carry
# a tab or a newline.
skip_reason() {
    local path="$1" name mime
    name="${path##*/}"
    case "$name" in
        Thumbs.db|desktop.ini|.DS_Store|'~$'*|'.~lock.'*'#'|*.sync-conflict-*) printf junk; return 0 ;;
    esac
    [[ "${name,,}" == *_sensibel* ]] && { printf secret; return 0; }
    [[ "$path" == *[$'\t\n"\\']* ]] && { printf name; return 0; }
    mime="$(file --brief --mime-type -- "$path")"
    case "$mime" in
        application/pdf|image/jpeg|image/png) ;;
        *) printf 'local:%s' "$mime" ;;
    esac
}

# Squeezes runs of spaces and trims both ends.
squeeze() {
    local text="$1"
    while [[ "$text" == *'  '* ]]; do text="${text//  / }"; done
    text="${text# }"
    printf '%s' "${text% }"
}

# describe NAME sets TITLE and CREATED from a file's basename.
describe() {
    local name="$1" stem rest
    stem="${name%.*}"
    [[ -n "$stem" ]] || stem="$name"
    TITLE="$stem"
    CREATED=""
    if [[ "$stem" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_(.*)$ ]] \
        && [[ "$(date -d "${BASH_REMATCH[1]}" +%F 2>/dev/null || true)" == "${BASH_REMATCH[1]}" ]]; then
        CREATED="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]//_OFFEN/}"
        rest="$(squeeze "${rest//[_-]/ }")"
        [[ -n "$rest" ]] && TITLE="$rest"
    fi
    TITLE="$(squeeze "${TITLE:0:128}")"
}

# tags_for ROOT PATH sets FILE_TAGS to the folders between ROOT and PATH, plus
# Offen for a name with _OFFEN.
tags_for() {
    local root="$1" path="$2" relative
    FILE_TAGS=()
    relative="${path#"$root"/}"
    [[ "$relative" == */* ]] && IFS=/ read -r -a FILE_TAGS <<< "${relative%/*}"
    [[ "${path##*/}" == *_OFFEN* ]] && FILE_TAGS+=(Offen)
    return 0
}

# ensure_tag USER NAME creates NAME as USER unless the map holds it.
ensure_tag() {
    local user="$1" name="$2" answer
    [[ -n "${TAGS[$name]:-}" ]] && return 0
    answer="$(api "$user" POST /api/tags/ "$(jq -cn --arg n "$name" '{name: $n, matching_algorithm: 0}')")" \
        || die "could not create the tag $name."
    TAGS[$name]="$(jq -r .id <<< "$answer")"
    printf 'tag\t%s\t%s\n' "${TAGS[$name]}" "$name"
}

main() {
    local apply=0 limit=0
    while (( $# )); do
        case "$1" in
            -h|--help) usage; return 0 ;;
            --apply) apply=1; shift ;;
            --limit)
                [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "--limit needs a positive number."
                limit="$2"; shift 2 ;;
            -*) die "unknown option $1." ;;
            *) break ;;
        esac
    done
    (( $# >= 3 )) || { usage >&2; exit 2; }
    SPEC="$1"
    local user="$2" root
    shift 2
    local -a roots=()
    for root; do
        [[ -d "$root" ]] || die "$root is not a directory."
        roots+=("$(realpath -- "$root")")
    done
    load_spec
    ensure_token "$user"

    local tags name id
    tags="$(api_all "$user" /api/tags/)" || die "could not list the tags of $user."
    while IFS=$'\t' read -r name id; do
        [[ -n "$name" ]] && TAGS[$name]="$id"
    done <<< "$(jq -r '.[] | [.name, (.id | tostring)] | @tsv' <<< "$tags")"

    local count=0 path reason sha found tag answer
    local -a fields
    for root in "${roots[@]}"; do
        while IFS= read -r -d '' path; do
            reason="$(skip_reason "$path")"
            if [[ -n "$reason" ]]; then
                printf 'skip\t%s\t%s\n' "$reason" "$path" >&2
                continue
            fi
            sha="$(sha256sum < "$path")"
            sha="${sha%% *}"
            answer="$(api "$user" GET "/api/documents/?checksum__iexact=$sha&fields=id")" \
                || die "could not look up $path."
            found="$(jq -r '.results[0].id // empty' <<< "$answer")"
            if [[ -n "$found" ]]; then
                printf 'exists\t%s\t%s\t%s\n' "$found" "$sha" "$path"
                continue
            fi
            if [[ -n "${SEEN[$sha]:-}" ]]; then
                printf 'skip\tduplicate\t%s\n' "$path" >&2
                continue
            fi
            SEEN[$sha]=1
            describe "${path##*/}"
            tags_for "$root" "$path"
            if (( apply )); then
                fields=(-F "document=@\"$path\"" --form-string "title=$TITLE")
                [[ -n "$CREATED" ]] && fields+=(--form-string "created=$CREATED")
                for tag in "${FILE_TAGS[@]}"; do
                    ensure_tag "$user" "$tag"
                    fields+=(-F "tags=${TAGS[$tag]}")
                done
                id="$(post_and_wait "$user" "$path" "${fields[@]}")"
                printf 'uploaded\t%s\t%s\t%s\n' "$id" "$sha" "$path"
            else
                for tag in "${FILE_TAGS[@]}"; do
                    if [[ -z "${TAGS[$tag]:-}" ]]; then
                        printf 'would-create-tag\t%s\n' "$tag"
                        TAGS[$tag]=new
                    fi
                done
                printf 'would-upload\t%s\t%s\t%s\t%s\t%s\n' "$sha" "$path" "$TITLE" "$CREATED" \
                    "$(IFS=/; printf '%s' "${FILE_TAGS[*]}")"
            fi
            count=$((count + 1))
            if (( limit && count >= limit )); then
                return 0
            fi
        done < <(find "$root" -type f -print0 | LC_ALL=C sort -z)
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
