#!/usr/bin/env bash
#
# Compares or writes Dolibarr's cron security key (Setup -> Modules -> Scheduled jobs) against a
# key file, through the setup page an administrator uses. The REST API cannot write the constant.
#
# The key has two homes that must agree: the CRON_KEY constant in the database, which this page
# writes, and secrets/dolibarr_cron_key, which dolibarr_cron passes to cron_run_jobs.php when it
# starts. The image writes the constant only when it creates an empty database, so a new key file
# alone locks every scheduled job out. docs/dolibarr.md#rotating-the-cron-key has the whole order.
#
# The key goes to curl as a file and is compared inside the shell, so it reaches neither the
# process list nor the terminal. A fresh GET is compared after saving, because the page answering
# the POST shows the posted value instead of the stored one.
#
# Usage:
#   cron-key-setup.sh check|set    DOLIBARR_CRON_KEY_FILE names the key file
#   cron-key-setup.sh --help
#
# Environment: DOLIBARR_CRON_KEY_FILE, and see tools/dolibarr/lib.sh

set -uo pipefail
umask 077

# shellcheck source=tools/dolibarr/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() { sed -n '3,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

SETUP_PAGE=cron/admin/cron.php

# The stored key in the setup page FILE, with "&amp;" decoded, or nothing. Dolibarr renders it
# as a text field, or as a hidden one when CRON_DISABLE_KEY_CHANGE is 1.
stored_key() {
    grep -o 'id="CRON_KEY" name="CRON_KEY" value="[^"]*"' "$1" | head -n 1 \
        | sed 's/.*value="//; s/"$//; s/&amp;/\&/g'
}

# The key file without a trailing newline, copied to $WORK/cron-key. Refuses anything but the
# URL-safe characters write-secret-files.sh produces, which survive the cron line and the form.
read_key_file() {
    [[ -n "${DOLIBARR_CRON_KEY_FILE:-}" ]] || { fail "DOLIBARR_CRON_KEY_FILE is not set."; return 1; }
    [[ -r "$DOLIBARR_CRON_KEY_FILE" ]] || { fail "Cannot read $DOLIBARR_CRON_KEY_FILE"; return 1; }
    tr -d '\n' < "$DOLIBARR_CRON_KEY_FILE" > "$WORK/cron-key"
    [[ "$(< "$WORK/cron-key")" =~ ^[A-Za-z0-9_-]{16,128}$ ]] \
        || { fail "$DOLIBARR_CRON_KEY_FILE holds no key of 16 to 128 URL-safe characters."; return 1; }
}

key_matches() { [[ "$(stored_key "$WORK/page.html")" == "$(< "$WORK/cron-key")" ]]; }

main() {
    local command="${1:-}"
    case "$command" in
        -h|--help) usage; return 0 ;;
        check|set) ;;
        *) usage >&2; return 2 ;;
    esac
    [[ -n "${DOLIBARR_CRON_KEY_FILE:-}" ]] || { fail "DOLIBARR_CRON_KEY_FILE is not set."; return 2; }

    ui_start || return 1
    read_key_file || return 1
    login || return 1
    page "$SETUP_PAGE" || return 1
    grep -q 'name="CRON_KEY"' "$WORK/page.html" || { fail "The scheduled jobs setup page shows no key field."; return 1; }

    if key_matches; then
        printf 'The stored cron key matches %s.\n' "$DOLIBARR_CRON_KEY_FILE"
        return 0
    fi
    if [[ "$command" == check ]]; then
        printf 'The stored cron key differs from %s.\n' "$DOLIBARR_CRON_KEY_FILE"
        return 1
    fi

    page "$SETUP_PAGE" --data-urlencode "token=$(form_token "$WORK/page.html")" \
        --data-urlencode save=1 --data-urlencode "CRON_KEY@$WORK/cron-key" || return 1
    page "$SETUP_PAGE" || return 1
    key_matches || { fail "The stored cron key still differs after saving."; return 1; }
    printf 'The stored cron key now matches %s.\n' "$DOLIBARR_CRON_KEY_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
