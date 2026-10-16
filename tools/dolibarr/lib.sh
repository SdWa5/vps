#!/usr/bin/env bash
#
# Shared helpers for the scripts in tools/dolibarr/ that drive Dolibarr's own setup pages, for the
# settings its REST API cannot write. Sourced, not executable on its own.
#
# The pages are used the way an administrator uses them in the browser: a session cookie from a
# real login, and the CSRF token of the page served last. No secret reaches the process list or
# the terminal, because curl reads the admin password from a file.
#
# The sourcing script calls ui_start once, then login, then page as often as it needs.
#
# Environment:
#   DOLIBARR_URL                    default http://localhost:8089, the dev mirror
#   DOLIBARR_ADMIN_LOGIN            default admin
#   DOLIBARR_ADMIN_PASSWORD_FILE    default ~/.local/share/sdwa5-dolibarr-dev/admin-password

DOLIBARR_URL="${DOLIBARR_URL:-http://localhost:8089}"
DOLIBARR_ADMIN_LOGIN="${DOLIBARR_ADMIN_LOGIN:-admin}"
DOLIBARR_ADMIN_PASSWORD_FILE="${DOLIBARR_ADMIN_PASSWORD_FILE:-$HOME/.local/share/sdwa5-dolibarr-dev/admin-password}"

WORK=""
LAST=""

fail() { printf '%s\n' "$*" >&2; return 1; }

# A private scratch directory for the cookie jar and the pages, removed on exit.
ui_start() {
    [[ -r "$DOLIBARR_ADMIN_PASSWORD_FILE" ]] || { fail "Cannot read $DOLIBARR_ADMIN_PASSWORD_FILE"; return 1; }
    WORK="$(mktemp -d)"
    # shellcheck disable=SC2064 # WORK is fixed from here on, so it is expanded now.
    trap "rm -rf -- '$WORK'" EXIT
}

# The CSRF token of the page in FILE. Dolibarr accepts only the token of the last page it served.
form_token() {
    grep -o 'name="token" value="[0-9a-f]*"' "$1" | head -n 1 | sed 's/.*value="//; s/"$//'
}

# GET or POST against Dolibarr with the session jar. The page lands in $WORK/page.html.
page() {
    local path="$1"
    shift
    LAST="$(curl -s -o "$WORK/page.html" -w '%{http_code}' -b "$WORK/jar" -c "$WORK/jar" "$@" "$DOLIBARR_URL/$path")"
    [[ "$LAST" =~ ^(200|302|303)$ ]] || { fail "HTTP $LAST from $path"; return 1; }
}

login() {
    page index.php || return 1
    page index.php --data-urlencode "token=$(form_token "$WORK/page.html")" \
        --data-urlencode actionlogin=login --data-urlencode loginfunction=loginfunction \
        --data-urlencode "username=$DOLIBARR_ADMIN_LOGIN" \
        --data-urlencode "password@$DOLIBARR_ADMIN_PASSWORD_FILE" || return 1
    page index.php || return 1
    grep -q 'logout\.php' "$WORK/page.html" || { fail "Login as $DOLIBARR_ADMIN_LOGIN failed."; return 1; }
}
