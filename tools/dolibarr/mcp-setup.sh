#!/usr/bin/env bash
#
# Sets up the core MCP server of Dolibarr 24 (module "ai") through Dolibarr's own setup pages.
#
# The MCP server runs every tool as one service user and accepts one API key. This script creates
# that user when it is missing, grants it the listed rights, selects it as AI_MCP_USER_ID, switches
# AI_MCP_ENABLED on, generates the key when none exists and stores it in a private file. It then
# calls tools/list and prints the tool names. Every step goes through the same pages and actions an
# administrator uses in the browser, so Dolibarr validates, logs and encrypts as usual.
#
# No secret reaches the process list or the terminal. curl reads the admin password and the
# service user's random password from files, and sends the API key from a private header file.
# The default target is the local dev mirror from dev-instance.sh. Production needs DOLIBARR_URL
# and an admin password file, for example DOLIBARR_ADMIN_PASSWORD_FILE=<(bw get password ID).
#
# Usage:
#   mcp-setup.sh [--login LOGIN] [--rights ID,ID,...] [--rotate-key]
#   mcp-setup.sh --help
#
# Environment:
#   DOLIBARR_URL                    default http://localhost:8089
#   DOLIBARR_ADMIN_LOGIN            default admin
#   DOLIBARR_ADMIN_PASSWORD_FILE    default ~/.local/share/sdwa5-dolibarr-dev/admin-password
#   DOLIBARR_MCP_KEY_FILE           default ~/.local/share/sdwa5-dolibarr-dev/mcp-api-key

set -uo pipefail
umask 077

DOLIBARR_URL="${DOLIBARR_URL:-http://localhost:8089}"
DOLIBARR_ADMIN_LOGIN="${DOLIBARR_ADMIN_LOGIN:-admin}"
DOLIBARR_ADMIN_PASSWORD_FILE="${DOLIBARR_ADMIN_PASSWORD_FILE:-$HOME/.local/share/sdwa5-dolibarr-dev/admin-password}"
DOLIBARR_MCP_KEY_FILE="${DOLIBARR_MCP_KEY_FILE:-$HOME/.local/share/sdwa5-dolibarr-dev/mcp-api-key}"
# Ticket read, write and manage; project read, also for private projects.
DEFAULT_RIGHTS="56001,56002,56004,41,141"

WORK=""
LAST=""

fail() { printf '%s\n' "$*" >&2; return 1; }

usage() { sed -n '3,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# The CSRF token of the page in FILE. Dolibarr accepts only the token of the last page it served.
form_token() {
    grep -o 'name="token" value="[0-9a-f]*"' "$1" | head -n 1 | sed 's/.*value="//; s/"$//'
}

# The id of the user LOGIN in the user list FILE, empty when there is none. Each list row carries
# its user id in data-rowid and the login as the whole text of one cell.
user_id_from_list() {
    awk -v login="$2" 'BEGIN { RS = "<tr data-rowid=\""; gsub(/\./, "\\.", login) }
        NR > 1 {
            id = substr($0, 1, index($0, "\"") - 1)
            row = substr($0, 1, index($0 "</tr>", "</tr>"))
            if (row ~ (">[[:space:]]*" login "[[:space:]]*<")) { printf "%s", id; exit }
        }' "$1"
}

# Writes the MCP key shown on the setup page FILE into TARGET without printing it.
store_key() {
    local key
    key="$(grep -o 'id="apikey" value="[^"]*"' "$1" | head -n 1 | sed 's/.*value="//; s/"$//')"
    [[ "$key" =~ ^[A-Za-z0-9]{32,}$ ]] || { fail 'The setup page shows no MCP key.'; return 1; }
    printf '%s' "$key" > "$2.part" && mv -- "$2.part" "$2"
    printf 'MCP key stored in %s (%s characters).\n' "$2" "${#key}"
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

ensure_user() {
    local login="$1" id
    page "user/list.php?search_status=-1&limit=1000" || return 1
    id="$(user_id_from_list "$WORK/page.html" "$login")"
    if [[ -z "$id" ]]; then
        openssl rand -base64 33 | tr -d '\n' > "$WORK/service-password"
        page 'user/card.php?action=create' || return 1
        page user/card.php --data-urlencode "token=$(form_token "$WORK/page.html")" \
            --data-urlencode action=add --data-urlencode "login=$login" \
            --data-urlencode 'lastname=MCP service' --data-urlencode admin=0 \
            --data-urlencode "password@$WORK/service-password" || return 1
        page "user/list.php?search_status=-1&limit=1000" || return 1
        id="$(user_id_from_list "$WORK/page.html" "$login")"
        [[ -n "$id" ]] || { fail "Creating user $login failed."; return 1; }
        printf 'Created user %s (id %s).\n' "$login" "$id" >&2
    fi
    printf '%s' "$id"
}

grant_rights() {
    local id="$1" right
    for right in ${2//,/ }; do
        [[ "$right" =~ ^[0-9]+$ ]] || { fail "Not a right id: $right"; return 1; }
        page "user/perms.php?id=$id" || return 1
        page "user/perms.php?id=$id&action=addrights&confirm=yes&entity=1&rights=$right&token=$(form_token "$WORK/page.html")" \
            || return 1
    done
    printf 'Granted rights %s to user %s.\n' "$2" "$id"
}

configure_server() {
    local id="$1" rotate="$2"
    page ai/admin/server_mcp.php || return 1
    page "core/ajax/constantonoff.php?action=set&name=AI_MCP_ENABLED&entity=1&token=$(form_token "$WORK/page.html")" \
        || return 1
    page ai/admin/server_mcp.php || return 1
    page ai/admin/server_mcp.php --data-urlencode "token=$(form_token "$WORK/page.html")" \
        --data-urlencode action=update_external --data-urlencode "AI_MCP_USER_ID=$id" || return 1
    page ai/admin/server_mcp.php || return 1
    if [[ "$rotate" == 1 ]] || ! grep -q 'id="apikey"' "$WORK/page.html"; then
        page "ai/admin/server_mcp.php?action=generate_key&token=$(form_token "$WORK/page.html")" || return 1
        page ai/admin/server_mcp.php || return 1
    fi
    store_key "$WORK/page.html" "$DOLIBARR_MCP_KEY_FILE"
}

list_tools() {
    { printf 'X-API-Key: '; cat "$DOLIBARR_MCP_KEY_FILE"; printf '\n'; } > "$WORK/key-header"
    curl -s -H @"$WORK/key-header" -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
        "$DOLIBARR_URL/ai/server/mcp_server.php" > "$WORK/tools.json"
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
if "error" in data:
    sys.exit("MCP error: " + data["error"].get("message", ""))
tools = [t["name"] for t in data["result"]["tools"]]
print(f"MCP tools/list returned {len(tools)} tools: " + ", ".join(sorted(tools)))
' "$WORK/tools.json"
}

main() {
    local login=mcp rights="$DEFAULT_RIGHTS" rotate=0 id
    while (( $# )); do
        case "$1" in
            --login) login="${2:-}"; shift 2 ;;
            --rights) rights="${2:-}"; shift 2 ;;
            --rotate-key) rotate=1; shift ;;
            -h|--help) usage; return 0 ;;
            *) usage >&2; return 2 ;;
        esac
    done
    [[ "$login" =~ ^[a-z][a-z0-9._-]{1,23}$ ]] || { fail "Not a login: $login"; return 2; }
    [[ -r "$DOLIBARR_ADMIN_PASSWORD_FILE" ]] || { fail "Cannot read $DOLIBARR_ADMIN_PASSWORD_FILE"; return 1; }
    WORK="$(mktemp -d)"
    trap 'rm -rf -- "$WORK"' EXIT
    login || return 1
    id="$(ensure_user "$login")" || return 1
    grant_rights "$id" "$rights" || return 1
    configure_server "$id" "$rotate" || return 1
    list_tools
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
