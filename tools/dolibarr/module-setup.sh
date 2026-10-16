#!/usr/bin/env bash
#
# Enables, disables or reports a Dolibarr module through Setup -> Modules, the page an
# administrator uses. Dolibarr's REST API has no route for it.
#
# It follows the switch link the modules page itself renders for that module, with the page's
# own CSRF token, and reads the page again afterwards to confirm the new state. Activation runs
# the module's init(), so rights, hooks, scheduled jobs and menus are registered as in the browser.
# Enabling an enabled module or disabling a disabled one changes nothing.
#
# The default target is the local dev mirror from dev-instance.sh. Production needs DOLIBARR_URL
# and an admin password file, for example DOLIBARR_ADMIN_PASSWORD_FILE=<(bw get password ID).
#
# Usage:
#   module-setup.sh status|enable|disable MODULE    MODULE is the class, e.g. modPmTools or PmTools
#   module-setup.sh --help
#
# Environment: see tools/dolibarr/lib.sh

set -uo pipefail
umask 077

# shellcheck source=tools/dolibarr/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# The switch link for module class CLASS in the modules page FILE, with "&amp;" decoded, or
# nothing. ACTION is "set" for the link that enables and "reset" for the one that disables.
# Dolibarr 24 escapes the disable link and writes the enable link with bare "&", so both forms
# are read.
switch_link() {
    grep -o "[^\"]*admin/modules\.php?[^\"]*" "$1" | sed 's/&amp;/\&/g' \
        | grep -E "[?&]action=$2&" | grep -E "[?&]value=$3(&|$)" | head -n 1 \
        | sed 's#^.*/admin/modules\.php#admin/modules.php#'
}

# enabled, disabled or unknown, read off the modules page FILE.
module_state() {
    if [[ -n "$(switch_link "$1" reset "$2")" ]]; then
        printf 'enabled'
    elif [[ -n "$(switch_link "$1" set "$2")" ]]; then
        printf 'disabled'
    else
        printf 'unknown'
    fi
}

modules_page() {
    page "admin/modules.php?mode=commonkanban&search_keyword=$1"
}

main() {
    local command="${1:-}" class="${2:-}" keyword state wanted link
    case "$command" in
        -h|--help) usage; return 0 ;;
        status|enable|disable) ;;
        *) usage >&2; return 2 ;;
    esac
    [[ "$class" =~ ^(mod)?[A-Z][A-Za-z0-9]{1,40}$ ]] || { fail "Not a module class: $class"; return 2; }
    [[ "$class" == mod* ]] || class="mod$class"
    keyword="$(printf '%s' "${class#mod}" | tr '[:upper:]' '[:lower:]')"

    ui_start || return 1
    login || return 1
    modules_page "$keyword" || return 1
    state="$(module_state "$WORK/page.html" "$class")"
    [[ "$state" != unknown ]] || { fail "Setup -> Modules lists no module $class."; return 1; }

    if [[ "$command" == status ]]; then
        printf '%s is %s.\n' "$class" "$state"
        return 0
    fi
    wanted="$([[ "$command" == enable ]] && printf 'enabled' || printf 'disabled')"
    if [[ "$state" == "$wanted" ]]; then
        printf '%s is already %s.\n' "$class" "$state"
        return 0
    fi

    link="$(switch_link "$WORK/page.html" "$([[ "$command" == enable ]] && printf set || printf reset)" "$class")"
    page "$link" || return 1
    modules_page "$keyword" || return 1
    state="$(module_state "$WORK/page.html" "$class")"
    [[ "$state" == "$wanted" ]] || { fail "$class is still $state after the switch. Dolibarr may show why in Setup -> Modules."; return 1; }
    printf '%s is now %s.\n' "$class" "$state"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
