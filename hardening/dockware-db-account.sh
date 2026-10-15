#!/usr/bin/env bash
# Gives a dockware Shopware container a database account of its own and removes
# the network-wide root login dockware ships with.
#
# dockware creates root@'%' with the password `root`, and Shopware's .env
# connects as that root. Measured 2026-10-15: from one shop container, a root
# login into the other shop's database succeeded over the shared Docker network.
#
# root@localhost keeps the default password on purpose. dockware's entrypoint runs
# /var/www/scripts/shopware6/update_domain.sh on every start whenever SHOP_DOMAIN
# is not localhost, that script logs in as root/root over 127.0.0.1, and the
# entrypoint runs under `set -e`, so a changed root password stops the container
# from booting. A TCP login from 127.0.0.1 matches root@localhost here because
# skip_name_resolve is off, measured with current_user(). So dropping root@'%'
# leaves the boot intact and closes the remote path.
#
# The new account uses mysql_native_password like dockware's root, because
# PHP's PDO over plain TCP cannot complete a caching_sha2_password full login
# without TLS or an RSA key exchange.
#
# The password is generated here, goes to MySQL and to .env through stdin only,
# and is never printed or put on a command line. Its one copy is Shopware's .env
# in the container's html volume, which restic backs up.
#
# Usage: dockware-db-account.sh CONTAINER
# Idempotent. A container already on its own account only gets root@'%' checked.
set -euo pipefail

container="${1:?usage: dockware-db-account.sh CONTAINER}"
app_user="${APP_DB_USER:-shopware}"
html=/var/www/html

root_sql() {
    docker exec -i --user root "$container" \
        mysql --no-defaults --protocol=TCP -h 127.0.0.1 -uroot -proot -N "$@" \
        2> >(grep -v 'Using a password on the command line' >&2)
}

# Prints user, host, port and database of the DATABASE_URL Shopware actually
# uses, resolved the way Shopware resolves it (.env, then .env.local and friends).
current_dsn() {
    docker exec --user root -w "$html" "$container" php -r '
        require "vendor/autoload.php";
        (new Symfony\Component\Dotenv\Dotenv())->bootEnv(getcwd()."/.env");
        $p = parse_url($_SERVER["DATABASE_URL"]);
        printf("%s\t%s\t%s\t%s\n", $p["user"] ?? "", $p["host"] ?? "", $p["port"] ?? 3306, ltrim($p["path"] ?? "", "/"));
    '
}

IFS=$'\t' read -r user host port dbname < <(current_dsn)
[[ "$dbname" =~ ^[A-Za-z0-9_]+$ ]] || { echo "unexpected database name" >&2; exit 1; }
echo "$container: Shopware connects as $user to $host:$port/$dbname"

if [[ "$user" == root ]]; then
    password="$(openssl rand -hex 24)"

    printf "CREATE USER IF NOT EXISTS '%s'@'localhost' IDENTIFIED WITH mysql_native_password BY '%s';
ALTER USER '%s'@'localhost' IDENTIFIED WITH mysql_native_password BY '%s';
GRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'localhost';\n" \
        "$app_user" "$password" "$app_user" "$password" "$dbname" "$app_user" | root_sql
    echo "$container: account $app_user@localhost created with privileges on $dbname only"

    # Every DATABASE_URL line in .env is rewritten, not only the last one, so no
    # stale root DSN is left to win after a later edit reorders the file.
    docker exec --user root "$container" cp -p "$html/.env" "$html/.env.pre-db-account"
    printf '%s' "$password" | docker exec -i --user root -w "$html" "$container" php -r '
        $password = stream_get_contents(STDIN);
        [$user, $host, $port, $db] = array_slice($argv, 1);
        $dsn = sprintf("mysql://%s:%s@%s:%s/%s", $user, $password, $host, $port, $db);
        $env = file_get_contents(".env");
        $env = preg_replace("/^DATABASE_URL=.*$/m", "DATABASE_URL=\"".$dsn."\"", $env, -1, $count);
        if ($count < 1) { fwrite(STDERR, "no DATABASE_URL line\n"); exit(1); }
        file_put_contents(".env", $env);
        printf("%d DATABASE_URL line(s) rewritten\n", $count);
    ' -- "$app_user" "$host" "$port" "$dbname"
    unset password
fi

# Shopware's own connection, through the same resolution Shopware uses.
docker exec --user root -w "$html" "$container" php -r '
    require "vendor/autoload.php";
    (new Symfony\Component\Dotenv\Dotenv())->bootEnv(getcwd()."/.env");
    $p = parse_url($_SERVER["DATABASE_URL"]);
    $pdo = new PDO(sprintf("mysql:host=%s;port=%s;dbname=%s", $p["host"], $p["port"] ?? 3306, ltrim($p["path"], "/")),
        urldecode($p["user"]), urldecode($p["pass"] ?? ""));
    printf("'"$container"': Shopware login works as %s, %d tables visible\n",
        $pdo->query("SELECT CURRENT_USER()")->fetchColumn(),
        $pdo->query("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()")->fetchColumn());
'

if [[ "$(root_sql -e "SELECT COUNT(*) FROM mysql.user WHERE user = 'root' AND host = '%'")" != 0 ]]; then
    root_sql -e "DROP USER 'root'@'%'"
    echo "$container: root@'%' dropped"
else
    echo "$container: root@'%' already absent"
fi

# The boot path dockware depends on, see the header.
echo "$container: dockware's boot login matches $(root_sql -e 'SELECT CURRENT_USER()')"
