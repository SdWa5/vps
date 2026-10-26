# The shop image

Since SEC-31 the sdwa5.org shop runs from its own image, `localhost/sdwa5-shopware:<Shopware version>-<build>`,
instead of the dockware development image. [`shopware/Dockerfile`](../../shopware/Dockerfile) builds it on
Shopware's FrankenPHP `docker-base`, [`tools/shopware/image.sh`](../../tools/shopware/image.sh) builds and ships
it, and [`tools/shopware/deploy.sh`](../../tools/shopware/deploy.sh) deploys it with Shopware's deployment helper.
The database is `shopware_db` on `mysql:8.4`. Chimo Diazz still runs on dockware, see
[../chimodiazz.md](../chimodiazz.md).

dockware brought an end-of-life MySQL 8.0 without a clean stop, an sshd, MailCatcher and setuid sudo, Composer 2.2.9
and development PHP settings into production. The image carries none of them.

## Build

```bash
tools/shopware/image.sh build              # on the workstation, prints the image ID
tools/shopware/image.sh ship [HOST]        # docker save | gzip | ssh HOST docker load
tools/shopware/image.sh composer ARGS...   # Composer on shopware-html-data/ in the build image
```

- **The build context is a git export** of the tracked files of `shopware/` and `shopware-html-data/`, uncommitted
  edits to tracked files included. A new file needs `git add` before a build. The revision label gets `-dirty`
  while either directory has edits, and `ship` refuses such an image.
- **Two directories.** `shopware/` holds what the image needs beyond the shop's own sources: `bin/`,
  `public/index.php`, a non-secret `.env` and the Dockerfile. `shopware-html-data/` holds the Composer files, the
  `config/` and the theme. On the host it is also the dockware docroot of the rollback window, so the shop sources
  stay there until that window is over.
- **The store token** for `packages.shopware.com` lives in `~/.config/sdwa5/shopware-auth.json` (or
  `SDWA5_SHOPWARE_AUTH`) and enters the build as a BuildKit secret, so no layer holds it.
- **The build stage** runs `shopware-cli project ci` in `ghcr.io/shopware/shopware-cli`, which installs the
  Composer packages without dev requirements, builds the administration and storefront assets and the theme's
  storefront javascript, and leaves `public/bundles` in the image. The deployment helper therefore runs with
  `--skip-assets-install`.
- **Composer** runs only through `image.sh composer` with `--no-install --no-scripts --no-plugins` for `require`
  and `update`, because the project's scripts need `vendor/` and a database, and Symfony Flex would write recipes.
  Its CLI image is the one of the Dockerfile's build stage.
- **Ship** loads the image onto the host over ssh, without a registry. The first build takes 1.07 GB unpacked.

Building on the workstation keeps the store token and the three licensed Store plugins off any registry and puts
no build load on production. A GitHub Actions build into a private registry is the target together with the push
deploy in [TODO #1](../../TODO.md). Deployer was weighed and not used, because the image, `docker compose`, the
volumes and the previous tag already provide its releases, shared directories and rollback.

## Tags

The tag is `<Shopware version>-<build>`, such as `6.7.15.1-1`. The `image:` line of the `shopware` service in
`docker-compose.yml` is the only place that names it, and the scripts read it from there. A test ties the version
part to `shopware/core` in `composer.lock`. The build number rises for a rebuild of the same version, such as one
for a new base digest.

A shipped tag never changes, because `ship` refuses a tag that the host holds as another image. The previous image
stays on the host for a rollback, and the prune in [../maintenance.md](../maintenance.md) spares every shop image
by its label, because no registry could restore it. Older shop images are removed by hand: list them with
`docker image ls localhost/sdwa5-shopware` and `docker image rm` each tag older than the previous one.

Dependabot proposes new digests for the two `FROM` lines of the Dockerfile. Merging such a pull request deploys
nothing until the image is rebuilt and shipped. The image is only as patched as its last build, so a base digest
pull request is the signal to rebuild.

## Runtime

The final stage changes four things in Shopware's base image, so compose and the mirror inherit them.

- **No file capability on `frankenphp`.** The shop listens on 8000, and with `cap_net_bind_service` the binary
  cannot start under `cap_drop: [ALL]`.
- **No access log in the inner Caddy.** Caddy on the host writes the access log with redaction and a 14-day
  retention ([../caddy.md](../caddy.md)), and a second log would bypass both.
- **`admin off`** closes the inner Caddy's admin API on `localhost:2019`, which a server-side request from PHP
  could otherwise reach. The security recheck watches that port. The image's own healthcheck replaces the
  inherited one, which polled that API, and asks `/api/_info/health-check`.
- **`INSTALL_ADMIN_PASSWORD` is empty**, `DO_NOT_TRACK=1` stops the helper's telemetry and
  `SHOPWARE_DISABLE_UPDATE_CHECK=1` stops Shopware's update check, because only a rebuild updates the image.

The container runs as www-data (82) with `cap_drop: [ALL]` and `no-new-privileges`. `FRANKENPHP_CONFIG=num_threads 5`
in compose sizes FrankenPHP for this host, which would otherwise start two threads per CPU at a `memory_limit` of
512m each. The shop's data lives in bind mounts under `./shopware-data/`: `files`, `media`, `thumbnail`,
`sitemap`, `theme` and `log`. The error log stays on that volume, because `docker logs` end with the container at
every deploy. Runtime extension management is off, so plugins come only from Composer in the image.

Measured on the mirror on 2026-10-25: the probe container ran with an empty effective capability set, PID 1 was
`frankenphp`, the admin API did not answer, the log held no access line, FrankenPHP reported 5 threads, and the
app used 227 MiB after the storefront suite.

## Proxy headers

Caddy on the host terminates TLS and proxies plain HTTP to `127.0.0.1:8001`. An HTTP upstream receives the client's
`Host`, which Shopware picks the sales channel by. Only Caddy reaches 8001, and it overwrites any `X-Forwarded-*`
that a client sends, so `SYMFONY_TRUSTED_PROXIES=REMOTE_ADDR` trusts the direct peer, whichever address the inner
Caddy hands PHP. Measured on the mirror: a request with `X-Forwarded-Proto: https` answered 400 and the same request
without it 200, so Symfony trusts the header.

## Mail

The shop sends through the Google Workspace relay without credentials, because the relay admits this host by its
IP. The transport comes from `MAILER_DSN` in compose:

```
smtp://smtp-relay.gmail.com:587?local_domain=sdwa5.org&require_tls=true
```

- **Why the environment, not the admin.** Symfony Mailer greets with `EHLO [127.0.0.1]` unless the DSN sets
  `local_domain`. Shopware 6.7's mailer settings build the DSN from `system_config` and cannot set it. On
  2026-10-25 the relay refused every `EHLO [127.0.0.1]` and `EHLO localhost` with `421-4.7.0 Try again later`,
  and it accepted `sdwa5.org`, container IDs and the host's name. The last mails with the old setting went out on
  2026-10-15.
- **The admin must keep the environment configuration.** Shopware uses `MAILER_DSN` only while
  `core.mailerSettings.emailAgent` is empty. Choosing SMTP in the admin's mailer settings switches back to
  `[127.0.0.1]`. The base image sets `MAILER_DSN=null://localhost`, and dotenv does not override a real environment
  variable, so `.env.local` cannot carry the DSN. Without the compose line an empty `emailAgent` would drop every
  mail silently.
- **`require_tls=true`** refuses a plaintext fallback if the relay ever stops offering STARTTLS.
- **The mirror** passes `MAILER_DSN=null://null` and runs in staging mode, so it sends nothing whichever agent the
  copied `system_config` names.

Check it on the host:

```bash
docker exec shopware php bin/console system:config:get core.mailerSettings.emailAgent --format=json
# {"core.mailerSettings.emailAgent":""}; the default format prints `key => value`, never an empty line
docker exec shopware printenv MAILER_DSN
```

Shopware sends from the queue, so a mail goes out within a minute through the worker. FroshMailArchive records
each mail with `transport_state` `sent` or `failed`, and vps-health warns about every failed mail of the last 24
hours ([../monitoring.md](../monitoring.md#outgoing-email-verification)).

## Secrets

- `secrets/shopware_db_root_password` and `secrets/shopware_db_password` come from
  `tools/secrets/write-secret-files.sh NAME=random`.
- `secrets/shopware_env_local` holds `APP_SECRET` and `INSTANCE_ID` from the dockware shop's `.env` plus the new
  `DATABASE_URL`. It has owner 82 and mode 400 and is mounted as a compose secret at `/var/www/html/.env.local`.
  `APP_SECRET` must stay, because the admin's tokens are keyed by it and `config/jwt/` is empty.
- `shopware/.env` is tracked and holds no secret. It has to exist, because `public/index.php`, `bin/console` and
  the helper load dotenv, and with it `.env.local`, only when `.env` exists.

Nothing secret goes into `environment:`, and a compose test checks that.

## Deploy

```bash
# on the workstation
tools/shopware/image.sh build && tools/shopware/image.sh ship
# on the host, from /opt/docker
git pull --ff-only && tools/shopware/deploy.sh
```

`deploy.sh` deploys the image that `docker-compose.yml` names and never installs a shop. In order it:

1. requires the image on the host;
2. takes the worker cron's lock `/run/lock/shopware-worker.lock`, so no scheduled task or queue consumer runs
   against a half-migrated database;
3. starts `shopware_db` and requires an installed shop (`shopware-deployment-helper is-installed`);
4. writes a fresh backup of `shopware_db`, because migrations cannot be undone, and requires the archive to be
   newer than the run's start;
5. runs the helper in a one-off container of the new image while the old container keeps serving;
6. runs `system:check --context=pre_rollout`, which renders the storefront in-process, because the health route
   that `up --wait` waits for renders no storefront page;
7. switches to the new container with `docker compose up -d --wait`, while Caddy holds requests for up to 15 s
   (`lb_try_duration`).

A failure before step 7 leaves the old container serving.

**The deployment helper** (`shopware/deployment-helper`, configured in
[`.shopware-project.yml`](../../shopware-html-data/.shopware-project.yml)) runs `system:update:finish` when the
Shopware version changed, refreshes, installs, activates and updates the plugins that Composer put into the image,
and compiles the theme synchronously into the theme volume. Plugins are therefore declarative: every plugin in the
image ends up installed and active, and one that has to stay inactive needs an
`extension-management.overrides` entry. The helper's one-time tasks are the place for a future data fix that has
to run once per environment.

**It never installs a shop.** Without its `pre-install` hook the helper would install a fresh shop with a default
admin into any database that it does not find installed. The hook exits 1. Measured on 2026-10-25 against an empty
MySQL 8.4: `is-installed` exited 1, `run` failed at the hook, and the database held 0 tables.

**Maintenance and the readiness gate.** `deploy.sh` skips `system:check` while a sales channel is in maintenance,
because the check then fails. Measured on the mirror: with maintenance on and the cache cleared, the storefront
answered 307 and `system:check --context=pre_rollout` exited 1. Before the cache clear the HTTP cache still served
200 and the check passed, so the maintenance flag takes effect only with the next cache clear.

The helper does not run as an `init` service, because compose would rerun it at every unscoped `up -d` without a
backup or a lock. Its own maintenance mode stays off, because it would set the flag from the one-off container
while each container keeps its own cache.

## Updates

For a Shopware, plugin or PHP bump, or a merged Dependabot pull request of the `FROM` digests:

1. Change the Composer files with `tools/shopware/image.sh composer require|update … --no-install --no-scripts
   --no-plugins`, or take the digest, and raise the tag in `docker-compose.yml`.
2. `tools/shopware/image.sh build`, then `tools/shopware/dev-instance.sh restore` as the preview and rehearsal, and
   `SDWA5_STOREFRONT_URL=http://localhost:8090 tests/storefront/run.sh`.
3. Commit, merge, `tools/shopware/image.sh ship`, then on the host `git pull --ff-only` and
   `tools/shopware/deploy.sh`.
4. A Shopware version change switches maintenance on in the old container before `deploy.sh`
   (`docker exec shopware php bin/console sales-channel:maintenance:enable --all`, then `cache:clear`), and off in
   the new one afterwards. Then run the skipped `system:check --context=pre_rollout` by hand.

Whether Dependabot alerts watch `composer.lock` is a repository setting that still needs confirming.

## Mirror

[`tools/shopware/dev-instance.sh`](../../tools/shopware/dev-instance.sh) runs the production image against a copy
of the shop's data and the newest database archive, on `http://localhost:8090/`.

```bash
tools/shopware/dev-instance.sh fetch      # read the data and the archive over ssh
tools/shopware/dev-instance.sh restore    # rebuild the mirror
tools/shopware/dev-instance.sh up|down|status
tools/shopware/dev-instance.sh console ARGS
tools/shopware/dev-instance.sh purge      # remove volumes and fetched copies
```

`restore` unpacks the data into five volumes, starts the database on an internal network, imports the archive,
runs the same helper call as `deploy.sh` with `SHOPWARE_DEPLOYMENT_STAGING=1`, asserts the result in the database,
starts the application, runs `system:check --context=pre_rollout` and only then starts the proxy on
`127.0.0.1:8090`.

Shopware's staging mode, configured in
[`staging.yaml`](../../shopware-html-data/config/packages/staging.yaml), is what Shopware's docs require after
copying production data. It turns mail delivery off, moves every `http(s)` domain to the mirror's URL, deactivates
FroshShopmon, and deletes every app with an app server and the shop ID. Only the mirror's helper run sets the
variable, never production. Before the application starts, `restore` and `up` assert that mail delivery is off,
that every http domain points at the mirror and at least one does, that FroshShopmon is inactive and that no app
exists. Besides that, the mirror has no egress, `MAILER_DSN=null://null` and a new `APP_SECRET`.

Measured on 2026-10-25 with the dockware data and the archive of the night:

| | Result |
|---|---|
| M1 rows and plugins | orders, customers, products, media and documents equal to an independent import of the dump; 262 tables, the dump's 261 plus the helper's `one_time_tasks`; twelve plugins installed, all active except FroshShopmon |
| M2 database login after a restart | storefront 200, so PDO completes a `caching_sha2_password` full login |
| M3 proxy headers | 400 with `X-Forwarded-Proto: https`, 200 without |
| M4 layout | `tests/storefront` green, 66 passed |
| M5 admin, API, health | 200, 200 and `healthy` |
| M6 backup and restore drill | `flavor mysql`, version 8.4.13, restore verified |
| M7 clean stop | `docker stop -t 60` logged `Shutdown complete`, no crash recovery after the start |
| M8 memory and time | app 227 MiB, database 491 MiB; the helper took 27 s |
| M9 readiness gate under maintenance | exit 1 once the cache is cleared, so `deploy.sh` keeps its skip |

The fetch for the first rehearsal named the dockware paths:
`SDWA5_SHOPWARE_DATA=/opt/docker/shopware-html-data SDWA5_SHOPWARE_DATA_PATHS='files public/media public/thumbnail public/sitemap' SDWA5_SHOPWARE_ARCHIVE=/opt/docker/database-backup/shopware.tar.gz`.
The defaults read `/opt/docker/shopware-data` and `shopware_db.tar.gz`, which exist from the cutover on.

## Rollback

- **Before the shop opens on the image**, dockware's data stays untouched for 14 days after the cutover, so the
  previous `shopware` service and the previous Caddy upstream bring dockware back.
- **After a deploy**, the previous tag in `docker-compose.yml` and `docker compose up -d shopware` restore the
  previous image, which stays on the host. When the deploy ran migrations, the database comes back from the
  pre-deploy archive that `deploy.sh` wrote (`database-backup/shopware_db.tar.gz`, see [../backup.md](../backup.md)).
- **After the shop has opened on the image**, a return to dockware would mean dumping `shopware_db`, importing it
  into dockware's MySQL 8.0 and copying the five data directories back. That path is untested, so a forward fix
  comes first.
