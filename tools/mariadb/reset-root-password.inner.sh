#!/usr/bin/env bash
#
# Runs inside the throwaway container that reset-root-password.sh starts, fed on
# stdin. Starts the server with grants and networking off, sets the password of
# every existing root account to the service's configured root password, proves
# it with a root login and shuts the server down again.

set -uo pipefail

pw="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
[[ -n "$pw" ]] || { echo 'The service has no root password configured.' >&2; exit 1; }

sock=/run/mysqld/reset.sock
gosu mysql mariadbd --skip-grant-tables --skip-networking --socket="$sock" \
    --loose-innodb_buffer_pool_dump_at_shutdown=0 > /tmp/reset.log 2>&1 &
server=$!
client=(mariadb --no-defaults --socket="$sock" --batch --skip-column-names)

fail() {
    echo "$1" >&2
    kill "$server" 2> /dev/null
    wait "$server"
    exit 1
}

for _ in $(seq 60); do
    "${client[@]}" --execute='SELECT 1' > /dev/null 2>&1 && break
    sleep 1
done
hosts="$("${client[@]}" --execute="SELECT Host FROM mysql.user WHERE User = 'root'")" \
    || fail "The temporary server did not answer: $(tail -3 /tmp/reset.log)"
[[ -n "$hosts" ]] || fail 'No root account exists; nothing was changed.'

# The same escaping the image's entrypoint applies to MYSQL_ROOT_PASSWORD.
literal() {
    local escaped="${1//\\/\\\\}"
    escaped="${escaped//$'\n'/\\n}"
    printf '%s' "${escaped//\'/\\\'}"
}

{
    echo 'FLUSH PRIVILEGES;'
    while read -r host; do
        printf "SET PASSWORD FOR 'root'@'%s' = PASSWORD('%s');\n" "$(literal "$host")" "$(literal "$pw")"
    done <<< "$hosts"
} | "${client[@]}" || fail 'Setting the password failed.'

MYSQL_PWD="$pw" "${client[@]}" --user=root --execute='SELECT 1' > /dev/null \
    || fail 'The new root password does not log in.'

kill "$server"
wait "$server"
echo "Root password set for root@$(paste -sd, - <<< "$hosts") and verified with a login."
