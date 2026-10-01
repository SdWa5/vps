# Chimo Diazz

Artist website at <https://chimodiazz.sdwa5.org>, hosted here as a favour rather than as an SdWa5
service. The site itself is developed in the private repository `chimodiazz/website`, which this host
pulls with its own read-only deploy key.

**Live since 2026-09-15.** It served a static placeholder for a few hours that afternoon, between
the Caddy block being added and the container's first start.

## Routing

| Domain                 | Upstream                 | Notes                                         |
|------------------------|--------------------------|-----------------------------------------------|
| `chimodiazz.sdwa5.org` | `https://127.0.0.1:8444` | TLS skip verify, same shape as `sdwa5.org`     |

`/adminer`, `/mailcatcher` and `/logs` are answered with 404 by Caddy before anything reaches the
container. See the section on dockware's bundled tools below.

The A record already pointed at this host before any of this existed. Measured 2026-09-15:
`chimodiazz.sdwa5.org` resolved to the same address as `sdwa5.org`, and HTTPS failed with
`tlsv1 alert internal error`, which is what Caddy does for a name it has no site block for. Adding
the block is therefore all that was needed for the certificate.

## The placeholder, now a maintenance page

`chimodiazz-placeholder/index.html` is a single self-contained file with no external resources,
tracked in this repository. It is no longer routed: the site block proxies to the container instead.
It is kept because it is what this block falls back to while the instance is down, and swapping the
`handle` body for `root` plus `file_server` is a two-line edit and a reload.

It lives under `/opt/docker/`, so the daily restic backup takes it along. `/opt/docker` is `755
root:root`, which is why the `caddy` user can read it without any permission change.

Editing it is a `git pull` on the host plus nothing else — Caddy serves the file directly and needs
no reload for a content change.

## How the site's code reaches this host

`chimodiazz/website` is private and owned by someone else. GitHub refuses the same deploy key on two
repositories, so the key this host already uses for `SdWa5/vps` could not be reused.

- Key: `/root/.ssh/id_ed25519_chimodiazz_20260915`, ed25519, no passphrase, generated on this host on
  2026-09-15 and never transported anywhere. Fingerprint
  `SHA256:KAVEnhxAUwt4Hi/QFlrcMXNTAiVugeWDBFmM3jJo/go`.
- Registered on `chimodiazz/website` as a **read-only** deploy key. This host never writes there.
- Reached through the alias `github-chimodiazz` in `/root/.ssh/config`, which pins that one key with
  `IdentitiesOnly yes`, exactly as the `github.com` entry does for `SdWa5/vps`. Without
  `IdentitiesOnly` ssh offers every key it can find and GitHub answers as whichever repository the
  first accepted key belongs to.
- Verified 2026-09-15: `ssh -T github-chimodiazz` answers `Hi chimodiazz/website!` while
  `ssh -T github.com` still answers `Hi SdWa5/vps!`.

Checkout target is `/opt/docker/chimodiazz-src`, a nested git repository that this repository ignores
rather than tracks, because its history is not ours to carry.

```bash
git clone github-chimodiazz:chimodiazz/website.git /opt/docker/chimodiazz-src
cd /opt/docker/chimodiazz-src && git pull --ff-only    # later updates
```

**Nothing notices when this key dies.** The `git_remote` health check watches the `SdWa5/vps` key
only. That check exists because the first deploy key kept expiring silently, so the same trap is open
here — see [monitoring.md](monitoring.md) and [ssh-hardening.md](ssh-hardening.md).

## The container, defined and switched off

`docker-compose.projects.yml` holds `chimodiazz_shopware`: one `dockware/shopware:6.7.11.1`
container, the same exact pin as the `sdwa5.org` instance. dockware bundles PHP, the web server and
MySQL in one image, which is how Shopware already runs on this host, so both instances stay the same
shape and a Shopware upgrade is one decision rather than two.

It is gated behind `profiles: ["chimodiazz"]`. A bare `docker-compose -f docker-compose.projects.yml
up -d` must not bring up an empty shop carrying dockware's default credentials on a public subdomain.

Mounts:

| Host path                                              | Container path                                 | Why                                           |
|--------------------------------------------------------|------------------------------------------------|-----------------------------------------------|
| `chimodiazz-mysql-data/`                                | `/var/lib/mysql`                               | database, gitignored                          |
| `chimodiazz-html-data/`                                 | `/var/www/html`                                | Shopware web root, gitignored                 |
| `chimodiazz-src/shopware/custom/plugins/ChimodiazzTheme` | `/var/www/html/custom/plugins/ChimodiazzTheme` | the theme, mounted so a `git pull` updates it |

The theme mount is read-write on purpose: Shopware's storefront build writes into the plugin's own
`dist` directory, and a read-only mount breaks it.

## The two data directories have to be seeded first

**A bind mount is not filled from the image, and both of these mounts need what is in the image.**
Measured on 2026-09-15 against `dockware/shopware:6.7.11.1` on this host:

- `/var/www/html` contains exactly one file in the image, `shopware.tar.zst`. `/entrypoint.sh` line
  144 unpacks it, but only inside `if [ -f "$swCompressedFile" ]`. A bind mount over that path hides
  the archive, the condition is false, and the container comes up with an empty web root and no
  error about it.
- `/var/lib/mysql` is a populated MySQL data directory in the image. An empty bind mount replaces it
  with nothing.

A named volume would not have this problem, because Docker seeds one from the image on first use.
Bind mounts are still the right shape here: it is what the `sdwa5.org` instance uses, and restic
backs up `/opt/docker` rather than Docker's volume store. The `shopware-html-data/` directory that
instance uses was filled once, years ago, which is why the trap has never been visible on this host.

So, before the first start:

```bash
cd /opt/docker
mkdir -p chimodiazz-html-data chimodiazz-mysql-data
cid="$(docker create dockware/shopware:6.7.11.1)"
docker cp "$cid:/var/www/html/." chimodiazz-html-data/
docker cp "$cid:/var/lib/mysql/." chimodiazz-mysql-data/
docker rm "$cid"
```

The archive is copied rather than unpacked on purpose. The entrypoint unpacks it into the mounted
directory on first start and sets the file ownership Apache needs while doing so.

## dockware's bundled tools were public, and are not any more

**Measured 2026-09-15 against the live `sdwa5.org`, before this instance existed:**
`https://sdwa5.org/adminer/` returned a database login form, `https://sdwa5.org/logs/` the
PimpMyLog viewer, and `https://sdwa5.org/mailcatcher` the MailCatcher inbox holding every mail the
shop had sent, password-reset links included. All three answered 200 to anyone.

The cause is the image rather than any configuration here. dockware wires Adminer, MailCatcher and
PimpMyLog into the same Apache vhost as the shop, and its own startup banner prints them as
`http://<SHOP_DOMAIN>/adminer` and so on. Nothing in this repository ever pointed at them, which is
why they went unnoticed.

The `block_dockware_tools` snippet in the Caddyfile answers those paths with 404 for every dockware
site here. It is a snippet rather than a copied block because the second instance runs the same image
and would otherwise have repeated the exposure the hour it went up.

**What this does not fix:** the tools are still listening inside both containers, so anyone who
reaches the loopback ports directly still has them. That is the host's firewall and SSH doing the
work, not this rule.

The administrator credentials were a separate question and were checked separately. dockware ships a
published default pair. Measured 2026-09-15: the `sdwa5.org` instance already rejected it, and this
instance accepted it until the password was rotated, which was done before Caddy ever pointed at it.

## How it was brought up

Kept as a recipe, because the next Shopware instance on this host will need the same steps.

1. `git clone github-chimodiazz:chimodiazz/website.git /opt/docker/chimodiazz-src`
2. Seed the two data directories from the image, as above. This is the step that is easy to skip and
   fails silently.
3. `cd /opt/docker && docker-compose -f docker-compose.projects.yml --profile chimodiazz up -d chimodiazz_shopware`
4. Rotate dockware's default administrator password **before** the public name points at it.
5. `docker exec chimodiazz_shopware php bin/console plugin:refresh`, then
   `plugin:install --activate ChimodiazzTheme`, then `theme:compile`, then `cache:clear`.
6. Swap the Caddy block to the `reverse_proxy`, `install -m 644 -o root -g root /opt/docker/Caddyfile
   /etc/caddy/Caddyfile`, `systemctl reload caddy`.
7. `install -m 644 -o root -g root monitoring/cron.d/chimodiazz-worker /etc/cron.d/chimodiazz-worker`
   and deploy the `monitoring/vps-health.sh` that lists `chimodiazz_shopware` in
   `EXPECTED_CONTAINERS`.

Step 7 is not decoration. Without a worker Shopware's scheduled tasks stop and nothing says so, which
is what happened to the `sdwa5.org` instance for 47 days in 2026 — see [monitoring.md](monitoring.md).
The worker script takes its container from `SERVICE`, so the second instance needs a second cron file
and no second script. Its lock file is its own, because `flock -n` makes the loser exit rather than
queue, and a shared lock would let either instance starve the other.

Memory measured on the host on 2026-09-15 before any of this: 5937 MB total, 2054 MB used, 3883 MB
available, with the existing Shopware container at 1.01 GiB. A second instance of the same shape
fits, and it is the largest single thing this host would then be running twice.

## Deployment, and why this host pulls

A change to the theme reaches the site without anyone touching this host.
`monitoring/chimodiazz-deploy.sh` runs **every five minutes** from
`/etc/cron.d/chimodiazz-deploy`, fetches the checkout's branch, and when the commit moved it resets
to it, refreshes and updates the plugin, recompiles the storefront and clears the cache. Then it asks
the public URL for a 200. If the rebuild fails or the site does not come back, it resets to the
commit that was serving before, rebuilds from that and sends one mail. Silent otherwise, which is
almost every run.

**The checkout follows every commit, but only a commit under `REBUILD_PATHS` is rebuilt**, and that
defaults to `shopware/`. Everything else in `chimodiazz/website` is documentation, CI and planning
material the container never reads, and without the filter a README fix cost a full `theme:compile`
and a `cache:clear` on the live shop. A documentation commit therefore moves the checkout and leaves
the storefront alone, so the next real change is still built from the right base. `--force` rebuilds
regardless, and `REBUILD_PATHS=` turns the filter off. A diff that cannot be computed counts as
"rebuild", because compiling for nothing costs twenty seconds while skipping a real theme change
leaves the site stale with nothing saying so.

**A failed `cache:clear` earns one retry before the rollback.** Symfony builds a fresh cache
directory and swaps it in, so two clears at once leave the loser with a half-built directory and a
router that cannot find `url_matching_routes.php`. That happened on 2026-09-16, when
`theme:change --all` and `cache:clear` were run by hand against this container while a deploy was in
flight, and it rolled back a commit that had only changed Markdown. The retry empties
`var/cache/prod_*` and asks again. A second failure is a real failure and still rolls back.

**The lock lives in the script rather than in the cron line**, on
`/run/lock/chimodiazz-deploy.lock`. A run that finds it held exits silently. Manual maintenance
against this container takes the same lock, which is what the 2026-09-16 collision was missing:

```bash
flock /run/lock/chimodiazz-deploy.lock \
    docker exec chimodiazz_shopware php bin/console cache:clear
```

**It pulls rather than being pushed to, and that departs from [TODO.md](../TODO.md) on purpose.**
That file settled on a push-based GitHub Action on 2026-09-03 and asked not to re-open the
comparison. The reason here is different in kind rather than in cost: a push deployment out of
`chimodiazz/website` would put an SSH key to this host into a repository whose collaborators and
permissions somebody else administers. Pulling keeps the credential here, keeps it read-only and
opens nothing inbound. The decision for `SdWa5/vps` itself is untouched.

**What gets deployed is whatever branch `chimodiazz-src/` is checked out on.** Switching it is a
`git switch` in that directory rather than an edit to the script, and it is visible to anyone who
looks. A detached checkout, a branch that disappeared upstream and a failing fetch each send their
own mail rather than going quiet. The fetch failure names the deploy key, because that key lives on a
repository this host does not own and can be revoked without anything here noticing.

**A fetch that fails for one run mails nothing.** On 2026-09-29 the run at 16:55 failed its fetch
between two good runs, and the mail blamed the deploy key, which authenticated and fetched fine when
it was checked on 2026-10-01. A failed fetch is therefore only logged, with git's own output, until it
has failed for `FETCH_GRACE` seconds (900, three runs). Then it mails with that output, reminds after
1, 2, 4, 8 and 16 days and then every 30 days, and mails once more when the fetch works again. A
branch that is gone from the remote mails at once, since git only says so after reaching the
remote. The fetch runs under `LC_ALL=C`, because the script tells the two apart by git's English text.
The state sits in `/var/lib/vps-health/chimodiazz-deploy-remote` while a fault lasts.

The checkout is never edited by hand, which is what makes `git reset --hard` safe as the rollback.

**The deploy runs no `composer install`**, so it can only build what is already in the checkout. A
plugin that `chimodiazz/website` requires through composer, and a plugin bought in the Shopware
store, both have to be installed on this host by hand today. That is item 8 in
[TODO.md](../TODO.md).

The storefront serves `de-DE` by default since 2026-09-16, with `en-GB` reachable at
`https://chimodiazz.sdwa5.org/en`. Both are `sales_channel_domain` rows on the one Storefront sales
channel, so adding a language is a domain rather than a second channel.

## What Chimo can reach, and what he cannot

| Path | State |
|---|---|
| Admin UI, `https://chimodiazz.sdwa5.org/admin` | user `chimo`, full administrator |
| Admin API, password grant with the same credentials | works |
| Admin API, client credentials for an MCP server | integration `Chimo agent MCP`, admin, since 2026-09-16 |
| MySQL | not published at all, only `127.0.0.1:8005` and `127.0.0.1:8444` are |
| Adminer, MailCatcher, the log viewer | blocked at Caddy, see above |
| SSH to the host | none |
| The result of his own deploy | nothing, see below |

Measured on 2026-09-16. The database and the host stay closed on purpose, because opening either
would cost the whole stack something for one guest project. A genuine need for SQL is a request to
run the query here rather than a reason to publish 3306 or hand out an SSH account.

**The deploy tells him nothing.** `monitoring/chimodiazz-deploy.sh` writes no state file and
no log that anything off this host can read, and it mails only `MONITOR_MAIL_TO`, which is the
monitoring address of the whole host rather than his. So a push into `chimodiazz/website` is
handed over and goes quiet, and neither he nor an agent of his can see which commit is checked
out, whether the last `theme:compile` succeeded or why a rollback happened. That is item 9 in
[TODO.md](../TODO.md), where three ways to close it are weighed.

**The MCP integration exists since 2026-09-16** and is what keeps a machine's access off a human's
credentials. Its client id and secret live in the `SSD` Vaultwarden collection next to the login,
and the block that uses them is:

```json
"shopware-admin-mcp": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@shopware-ag/admin-mcp"],
  "env": {
    "SHOPWARE_API_URL": "https://chimodiazz.sdwa5.org",
    "SHOPWARE_API_CLIENT_ID": "<from the vault>",
    "SHOPWARE_API_CLIENT_SECRET": "<from the vault>"
  }
}
```

Verified on creation with a `client_credentials` grant, which answered 200, and with
`GET /api/_info/version`, which answered `6.7.11.1`.

## Monitoring

`chimodiazz=https://chimodiazz.sdwa5.org/` is in the built-in `HEALTH_URLS` default, and
`chimodiazz_shopware` is in `EXPECTED_CONTAINERS`. The container is profile-gated but permanently
running, so a missing one is a real fault rather than an expected absence.

## Backup

`chimodiazz-placeholder/` and `chimodiazz-src/` sit under `/opt/docker` and are picked up by the
daily restic run. So would `chimodiazz-html-data/` and `chimodiazz-mysql-data/` once they exist, and
the MySQL directory carries the same live-file caveat as the `sdwa5.org` one — see
[backup.md](backup.md).
