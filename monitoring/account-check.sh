#!/usr/bin/env bash
#
# Check the host's login accounts, root-equivalent groups, sudoers rules and root's SSH keys.
#
# The image's cloud-init created an account `debian` with passwordless sudo at the first Debian 13
# boot on 2026-10-15, although cloud-init was disabled. Nothing noticed it until the compromise
# check of 2026-10-24. An added account, sudoers rule or root key is also the classic way to keep
# access to a broken-into host, so vps-health.sh runs this every hour as "accounts" and
# security-recheck.sh --host as "accounts:host".
#
# It prints one line "STATUS<TAB>message" and exits 0 for every status, 2 for a usage error.
#   CRIT  an account other than root with uid 0; a login shell on an account outside
#         EXPECTED_LOGIN_ACCOUNTS; a member of a root-equivalent group; a sudoers rule other than
#         Debian's two defaults, an include other than "@includedir /etc/sudoers.d", or a Defaults
#         line that touches authentication; a root key outside the allowlist, a key line ssh-keygen
#         cannot read, or an authorized_keys2 next to root's key file
#   WARN  an unreadable passwd, group or sudoers file, or no allowlist
# It never reads /etc/shadow and prints account names, file names and key fingerprints only.
#
# Usage, on the host as root:
#   monitoring/account-check.sh
#   monitoring/account-check.sh --help
#
# Environment:
#   ACCOUNT_CHECK_ETC          the /etc to read (default /etc, test hook)
#   EXPECTED_LOGIN_ACCOUNTS    accounts that may have a login shell (default "root")
#   ROOT_AUTHORIZED_KEYS       root's key file (default /root/.ssh/authorized_keys)
#   ROOT_KEYS_ALLOW            allowed SHA256 fingerprints, one per line (default
#                              $ACCOUNT_CHECK_ETC/vps-health/root-authorized-keys)

set -uo pipefail

ETC="${ACCOUNT_CHECK_ETC:-/etc}"
EXPECTED_LOGIN_ACCOUNTS="${EXPECTED_LOGIN_ACCOUNTS:-root}"
ROOT_AUTHORIZED_KEYS="${ROOT_AUTHORIZED_KEYS:-/root/.ssh/authorized_keys}"
ROOT_KEYS_ALLOW="${ROOT_KEYS_ALLOW:-$ETC/vps-health/root-authorized-keys}"
# Groups whose members are root in all but name.
PRIVILEGED_GROUPS="sudo admin wheel docker disk shadow lxd"

crit=()
warn=()
logins=""
keys=0

usage() {
    sed -n '/^# Usage/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

check_passwd() {
    local name extra=()

    if [[ ! -r "$ETC/passwd" ]]; then
        warn+=("cannot read passwd")
        return
    fi
    while IFS= read -r name; do
        extra+=("$name")
    done < <(awk -F: '$3 == 0 && $1 != "root" { print $1 }' "$ETC/passwd")
    if (( ${#extra[@]} )); then
        crit+=("uid 0 account(s): ${extra[*]}")
    fi

    extra=()
    while IFS= read -r name; do
        if [[ " $EXPECTED_LOGIN_ACCOUNTS " == *" $name "* ]]; then
            logins+="${logins:+ }$name"
        else
            extra+=("$name")
        fi
    done < <(awk -F: '$7 !~ /(nologin|false)$/ && $7 != "/bin/sync" { print $1 }' "$ETC/passwd")
    if (( ${#extra[@]} )); then
        crit+=("unexpected login account(s): ${extra[*]}")
    fi
}

check_groups() {
    local members

    if [[ ! -r "$ETC/group" ]]; then
        warn+=("cannot read group")
        return
    fi
    members="$(awk -F: -v groups=" $PRIVILEGED_GROUPS " \
        'index(groups, " " $1 " ") && $4 != "" { s = s (s ? " " : "") $1 "=" $4 } END { print s }' "$ETC/group")"
    if [[ -n "$members" ]]; then
        crit+=("members of root-equivalent groups: $members")
    fi
}

# check_sudoers FILE MAIN
#
# MAIN is 1 for /etc/sudoers, the only file that may hold Debian's two rules and the include of
# sudoers.d. "#include" and "#includedir" are directives, not comments, so they are checked too.
check_sudoers() {
    local file="$1" main="$2" name="${1#"$ETC"/}" line words

    if [[ ! -f "$file" || ! -r "$file" ]]; then
        warn+=("cannot read $name")
        return
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        read -r -a words <<<"$line"
        line="${words[*]}"
        case "$line" in
            '') ;;
            '#include '*|'#includedir '*|'@include '*|'@includedir '*)
                if (( ! main )) || [[ "$line" != '@includedir /etc/sudoers.d' ]]; then
                    crit+=("unexpected include in $name")
                fi
                ;;
            '#'*) ;;
            Defaults*)
                if [[ "$line" == *authenticate* ]]; then
                    crit+=("Defaults touching authentication in $name")
                fi
                ;;
            *)
                if (( ! main )) || [[ "$line" != 'root ALL=(ALL:ALL) ALL' && "$line" != '%sudo ALL=(ALL:ALL) ALL' ]]; then
                    crit+=("unexpected sudoers rule for ${line%% *} in $name")
                fi
                ;;
        esac
    done < "$file"
}

check_root_keys() {
    local dir active fingerprints fp unknown=()

    dir="$(dirname "$ROOT_AUTHORIZED_KEYS")"
    if [[ -e "$dir/authorized_keys2" ]]; then
        crit+=("$dir/authorized_keys2 exists")
    fi
    if [[ ! -r "$ROOT_AUTHORIZED_KEYS" ]]; then
        warn+=("cannot read $ROOT_AUTHORIZED_KEYS")
        return
    fi
    active="$(grep -cvE '^[[:space:]]*(#|$)' "$ROOT_AUTHORIZED_KEYS")"
    fingerprints="$(ssh-keygen -lf "$ROOT_AUTHORIZED_KEYS" 2>/dev/null | awk '{ print $2 }')"
    keys="$(grep -c . <<<"$fingerprints")"
    if (( keys != active )); then
        crit+=("$(( active - keys )) unparseable line(s) in $ROOT_AUTHORIZED_KEYS")
    fi
    if [[ ! -r "$ROOT_KEYS_ALLOW" ]]; then
        warn+=("no root key allowlist at $ROOT_KEYS_ALLOW")
        return
    fi
    while IFS= read -r fp; do
        [[ -z "$fp" ]] || grep -qxF -- "$fp" "$ROOT_KEYS_ALLOW" || unknown+=("$fp")
    done <<<"$fingerprints"
    if (( ${#unknown[@]} )); then
        crit+=("root key(s) outside the allowlist: ${unknown[*]}")
    fi
}

# join_unique ITEM...
#
# The items in order, duplicates dropped, joined with "; ".
join_unique() {
    printf '%s\n' "$@" | awk '!seen[$0]++' | paste -sd ';' - | sed 's/;/; /g'
}

main() {
    local file

    case "${1:-}" in
        --help|-h) usage; return 0 ;;
        '') ;;
        *) usage >&2; return 2 ;;
    esac

    check_passwd
    check_groups
    check_sudoers "$ETC/sudoers" 1
    for file in "$ETC"/sudoers.d/*; do
        if [[ -e "$file" || -L "$file" ]]; then
            check_sudoers "$file" 0
        fi
    done
    check_root_keys

    if (( ${#crit[@]} )); then
        printf 'CRIT\t%s\n' "$(join_unique "${crit[@]}")"
    elif (( ${#warn[@]} )); then
        printf 'WARN\t%s\n' "$(join_unique "${warn[@]}")"
    else
        printf 'OK\tlogin accounts: %s; no member in a root-equivalent group; only the default sudoers rules; %s root key(s), all allowed\n' \
            "${logins:-none}" "$keys"
    fi
}

main "$@"
