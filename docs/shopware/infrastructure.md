# Infrastructure

- Docker: dockware image, ports 8001 (HTTP) / 8443 (HTTPS), reverse-proxied via **Caddy**, not nginx.
  See [../caddy.md](../caddy.md)
- Volume: `./shopware-html-data:/var/www/html`, `./shopware-mysql-data:/var/lib/mysql`
- APP_URL: `https://sdwa5.org`. Keep it in `/opt/docker/shopware-html-data/.env.local`, because
  Dockware's `/var/www/scripts/shopware6/update_domain.sh` rewrites `.env` to HTTP on startup.
  FPM clears inherited environment variables, so the Compose variable alone does not cover web requests.
  On 2026-10-15 HTTP in FPM triggered `ShopIdChangeSuggestedException` in the cart while the CLI check
  passed with HTTPS. The `.env.local` override restored HTTP 200 in EN/DE and the existing shop ID was kept.
- `.env`, `.env.local` and the other `.env*` files in `shopware-html-data/` are mode 600, owner
  `www-data`. They hold `APP_SECRET` and the database password. `update_domain.sh` edits `.env` with
  `sed -i`, which keeps the mode. It also leaves an empty line where the old `APP_URL` was on every
  start, which is harmless. `.env` used to repeat `APP_ENV=dev` and `DATABASE_URL` from dockware's
  own template further down. `.env.local` (`APP_ENV=prod`) won, but the second block was removed on
  2026-10-16 so the file says what runs.
- dockware's `sshd` and `mailcatcher` are stopped on every boot by
  [`hardening/dockware-boot-end.sh`](../../hardening/dockware-boot-end.sh), mounted as
  `/var/www/boot_end.sh`, see [../infrastructure.md](../infrastructure.md#no-sshd-in-the-shop-containers).
  This shop sends through `core.mailerSettings` to `smtp-relay.gmail.com`, so mailcatcher had nothing
  to catch.
- DockwareSamplePlugin: uninstalled
- `composer.json`/`.lock`, `symfony.lock` and `config/{packages,routes*,services.yaml,bundles.php}` are tracked
  in the repo (everything else in `shopware-html-data/` — `.env`, `var/`, `vendor/`, `public/`, `files/`,
  `config/jwt/` — stays gitignored)
- **Twelve plugins are installed and active.** Which ones exist, where each comes from and what
  records it lives in [plugins.md](plugins.md). All twelve are exact `composer.json` requires. The only
  plugin source tracked here is the shop's own theme in `custom/static-plugins/SdWa5Theme/`, see
  [theme.md](theme.md).

## Runtime: what runs Shopware's background work

Shopware needs a process to run its scheduled tasks and to consume its message queue. **Until
2026-09-08 there was none on this host**, and that had gone unnoticed for 47 days. What it cost is
kept below, because the shape of the failure is the reason the monitoring now watches it.

What runs it now:

| Piece | Where |
|---|---|
| The worker | [`../../monitoring/shopware-worker.sh`](../../monitoring/shopware-worker.sh), running `scheduled-task:run` and then `messenger:consume async low_priority failed` |
| Its schedule | `/etc/cron.d/shopware-worker`, every minute, under `flock -n` |
| The admin worker | off, in [`../../shopware-html-data/config/packages/shopware.yaml`](../../shopware-html-data/config/packages/shopware.yaml) |
| The watchdog | the `shopware_tasks` check in [`../monitoring.md`](../monitoring.md), CRIT past `SHOPWARE_TASK_MAX_AGE_HOURS` (2) |

Three details are deliberate. **`flock -n` is not decoration**, because Shopware's own documentation
warns that cron-driven workers pile up: cron does not wait for the previous run, and a message that
outlives the time limit keeps its worker alive. **The `failed` transport is consumed too**, because
without it a failed message is never retried and sits there forever. And **the tasks run before the
consumer**, so a message a task enqueues is picked up in the same minute rather than the next.

### What it cost while nothing ran it

Measured on 2026-09-08, before the fix. There was no host cron entry, no container crontab entry
beyond Debian's own `e2scrub_all` and `php sessionclean`, no running `scheduled-task:run` or
`messenger:consume`, and no worker service in `docker-compose.yml`.

* **Every scheduled task last ran on 2026-07-22 or 2026-07-23**, so every "next execution" was 47 days
  in the past.
* `shopware.sitemap_generate` last ran 2026-07-22, which was exactly the `lastmod` the published
  sitemap carried. The stale sitemap was a symptom of this rather than a separate problem.
* `shopware.invalidate_cache` has a 300-second interval and last ran 2026-07-23T14:31, so cache
  invalidation was dead and content edits may not have appeared.
* Every cleanup task was dead, so `log_entry`, `cart`, `payment_token`, `sales_channel_context`,
  `version` and `import_export_file` grew without being pruned.
* **9 messages sat unconsumed in the `async` transport**, with 0 failed.

**The likely mechanism was the admin worker, and that is a hypothesis rather than a measurement.** All
the tasks stopped at the same moment, and `shopware.invalidate_cache` showed a last run four minutes
before its next due time, which is what the admin worker looks like: it runs tasks only while somebody
has the administration open in a browser, so they ran while someone was working in the admin in late
July and not since. The effective `enable_admin_worker` value could not be read to confirm it, because
`bin/console debug:config` fails with "Impossible to call set() on a frozen ParameterBag" in this
build. It is off explicitly now either way.

### What the queue actually held

Worth recording, because the queue was drained by hand before the cron was enabled and the content was
unknown beforehand. Consuming one message with `--limit=1 -vv` showed
`Shopware\Core\Service\Message\UpdateServiceMessage`, which called
`registry.services.shopware.io`, updated the `ShopwarePayments` service app and then **enqueued a
dozen `GenerateThumbnailsMessage`**. So the queue grows before it drains, and both message types are
routine.

That surfaced something separate worth a look. **Five Shopware AG service apps are installed and four
are active**, namely `ShopwarePayments`, `Swag3DModelPipeline`, `SwagAIImageEditor` and `SwagCopilot`,
with `ShopwareNexusIngestionService` present but inactive. They install and update themselves through
the `services.install` task and phone home to Shopware's registry. None of that is in
the 2026-07-22 legal review, which now lives in Google Drive, so whether a non-profit wants an
AI image editor, a Copilot and an event ingestion service active on its shop is an open question rather
than a settled one. Filed in [TODO.md](TODO.md). The production backup of 2026-10-16 03:40 holds
eight apps with seven active, because `SwagRecommendations`, `SwagPreviewGenerator` and
`SwagGmvReportingService` installed themselves since.

### Service apps disabled (SEC-29, 2026-10-17)

`POST /api/services/disable` ran on production on 2026-10-17 after a database backup. It persists
`core.services.disabled` and uninstalled seven of the eight apps, `ShopwarePayments` included, so a cart
no longer calls Shopware's payment gateway. The shop offers only prepayment and pickup. The flag keeps
every service with the `services_enabled` requirement from installing again, which
`system:update:finish` and `services:install` confirmed on the mirror.

`docker-compose.yml` sets `ENABLE_SERVICES=false` for the shop, which makes the daily `services.install`
task and `bin/console services:install` do nothing. Without it the task would keep updating
`SwagGmvReportingService` and reinstall it after a removal.

`SwagGmvReportingService` requires only a Shopware account, so the disabled flag does not reach it, and
its privileges (`order:read` among them) are granted while an admin user holds a store token. It is
removed with `bin/console app:uninstall SwagGmvReportingService`, which works **only while
`ENABLE_SERVICES` is off**. `UninstallAppCommandDecorator` then hands the name to
`ServiceLifecycle::uninstall`. With services enabled the plain command looks up apps with
`selfManaged = false` and answers "No app with name … installed", as do the extension store and
`/api/service/uninstall`, which answers only to the service's own integration. Measured on the mirror
on 2026-10-17 in both states.

The way back is `POST /api/services/enable` plus removing the `ENABLE_SERVICES` line. That clears the
flag and queues an install of every service from the registry.

## Local mirror

[`tools/shopware/dev-instance.sh`](../../tools/shopware/dev-instance.sh) builds a copy of the live shop
on a workstation, so an update or a plugin change is rehearsed there before production gets it. It runs
the image `docker-compose.yml` pins, or the one in `SDWA5_SHOPWARE_DEV_IMAGE`, against the shop files
and the newest hourly database archive.

```bash
tools/shopware/dev-instance.sh fetch      # read the shop files and the archive over ssh
tools/shopware/dev-instance.sh restore    # rebuild the mirror, http://localhost:8090/
tools/shopware/dev-instance.sh up|down|status
tools/shopware/dev-instance.sh composer ARGS   # Composer on the mirror's files, with network
tools/shopware/dev-instance.sh console ARGS    # bin/console inside the mirror
tools/shopware/dev-instance.sh purge      # remove volumes and fetched copies
```

`fetch` only reads on the host. It streams `/opt/docker/shopware-html-data` without `var/cache`,
`var/log` and the dated `.env` backups, and copies `database-backup/shopware.tar.gz`, both into
`~/.local/share/sdwa5-shopware-dev` with mode 700. The files and the MySQL data then live in the Docker
volumes `sdwa5-shopware-dev-html` and `sdwa5-shopware-dev-mysql`, with production's `www-data`
ownership kept. The database is the one the dockware image ships, with its `root`/`root` login, and
the archive replaces its `shopware` schema.

The copy holds customer data, `auth.json` and every stored credential, so it is made harmless in two
layers, and the proxy that publishes it starts last.

- **No route out.** Shopware runs on an `--internal` Docker network. An `alpine/socat` container on a
  second network publishes `127.0.0.1:8090` and forwards inbound connections only. Mail, app
  webhooks, the service registry and Shopmon therefore cannot leave, which matters because mail is
  configured in `system_config` as SMTP rather than in `MAILER_DSN`, and eight service apps exist.
- **Neutralised settings.** `.env.local` gets the local `APP_URL`, a new `APP_SECRET`, the local
  `DATABASE_URL` and `MAILER_DSN=null://null`. `core.mailerSettings.disableDelivery` is set to the
  boolean `true`, every `http(s)` sales channel domain moves to `http://localhost:8090` with its path,
  and `FroshShopmon` is deactivated. The shop has no `config/jwt`, so the new `APP_SECRET` also means
  an admin token from the mirror is not valid in production.

The new URL makes Shopware suspect a moved shop and answer the cart with
`ShopIdChangeSuggestedException`, as it did in production on 2026-10-15. `restore` resolves that with
`app:shop-id:change reinstall-apps`, which gives the mirror a shop ID of its own. The registration of
the apps under it then fails with "App system target is not allowed" and exit code 1, because there
is no egress, and `app:shop-id:check` decides instead. The apps stay installed but unregistered.

Measured on 2026-10-16 with 6.7.11.1: `fetch` took 29 s for 146 MB of files and a 1.1 MB archive,
`restore` 1 min 40 s, and `up` 43 s. Storefront EN and DE, the cart, the admin and the health check
answered 200, `curl` from inside the container to the service registry and to 1.1.1.1 failed, and
`status` reported `mails disabled`.

The admin takes the production login, because the user table is copied. A browser login to the
mirror is local, and nothing it changes reaches production.

Every Shopware service app is deactivated through the admin API as well, with an integration whose keys
stay in `integration.env` in the private directory. That is needed since 6.7.15, because a checkout
gateway whose host does not resolve fails the cart with a 400. `AppSystemHttpMiddleware` throws an
`AppException` that the gateway's `GuzzleException` catch misses, and `ShopwarePayments` holds such a
gateway. `SwagGmvReportingService` is always-on in Shopware's own design, so `system:update:finish`
reactivates it, and `status` then shows `services 1 active`. Without egress it reaches nobody.

`composer` runs in a container of its own on the proxy's network, because the mirror has no egress. It
adds `--no-scripts` to `install`, `update`, `require` and `remove`, since the scripts boot Shopware.
`up` only reports a storefront that answers 503 or 500, because that is the state during an update.

## Updating Shopware

Rehearsed on the mirror on 2026-10-16 from 6.7.11.1 to 6.7.15.1. `composer audit` reported 22 advisories
for the old lock and none for the new one. That needed 6.7.15.1, because 6.7.11.1 pins `dompdf/dompdf`
3.1.4 exactly.

1. **New lock on the mirror.** Start it with the old image, then make the lock with Composer. The
   administration, storefront and elasticsearch packages pin core exactly, so `require
   --update-with-all-dependencies` fails, and the order that works is:

   ```bash
   tools/shopware/dev-instance.sh restore
   docker exec -u root sdwa5-shopware-dev chown 33:33 /var/www/html/composer.json /var/www/html/composer.lock
   tools/shopware/dev-instance.sh composer require --no-update shopware/core:v6.7.15.1
   tools/shopware/dev-instance.sh composer update shopware/core shopware/administration \
       shopware/storefront shopware/elasticsearch --with-all-dependencies
   docker run --rm --network sdwa5-shopware-dev-web --user www-data --workdir /var/www/html \
       --entrypoint php --mount type=volume,src=sdwa5-shopware-dev-html,dst=/var/www/html,volume-nocopy=true \
       "$(docker inspect -f '{{.Config.Image}}' sdwa5-shopware-dev)" \
       vendor/composer/composer/bin/composer audit --locked
   ```

   The dockware images ship Composer 2.2.9, which has no `audit`, so the vendored Composer runs it. The
   application container has no route out, so the audit runs beside it on the web network, the way the
   tool's own `composer` subcommand does. Copy
   `composer.json` and `composer.lock` into `shopware-html-data/` and give them back to `root:root`, as
   the git pull leaves them in production.
2. **Rehearse the live order.** Restore again, then replay the production steps with the new image:
   `sales-channel:maintenance:enable --all`, `system:update:prepare`, the new composer files copied in,
   `SDWA5_SHOPWARE_DEV_IMAGE=<new image> tools/shopware/dev-instance.sh up`, `composer install --no-dev`,
   `system:update:finish`, `theme:compile --active-only`, `cache:clear` and
   `sales-channel:maintenance:disable --all`. Measured on 2026-10-16 this took 1 min 22 s, with 15 s for
   the install and 16 s for the migrations.
3. **Accept on the mirror.** Storefront EN and DE, the cart, the admin and the health check answer 200.
   `plugin:list --json` matches production's apart from the deactivated `FroshShopmon`. An invoice
   preview renders as a PDF through `/api/_action/order/{id}/{deepLinkCode}/document/invoice/preview`,
   which exercises dompdf. The colour scan in [theme.md](theme.md) is compared with the last list and
   new rules are overridden in the theme.
4. **Pin the image by tag and digest** in `docker-compose.yml`, because dockware rebuilds tags.
5. **Live, after a Contabo snapshot.** `monitoring/database-backup.sh` and
   `monitoring/database-restore-check.sh shopware`, the worker lock `/run/lock/shopware-worker.lock`
   held throughout, maintenance on, `system:update:prepare`, `git pull --ff-only`, `docker compose up -d
   shopware`, `composer install --no-dev` in the container, `system:update:finish`, `plugin:refresh`
   and `plugin:update SdWa5Theme` for a bumped theme, `theme:compile --active-only`, `cache:clear`, the FPM reload with `pkill -USR2 -f '^php-fpm: master'` and maintenance off.
   The rollback is the previous image line and lock from git plus the SQL archive, or the snapshot.

   Live on 2026-10-16 from 15:13:51 to 15:16:18, so ca. 2.5 minutes of maintenance. The install took 24 s and
   the migrations 18 s. Afterwards the plugin list matched the previous one apart from SdWa5Theme 1.2.1, the
   colour scan matched the mirror's, `security-recheck.sh` reported 29 OK and Dependabot had no open alert.

### Updating plugins

A plugin update keeps the image and core, so steps 4 and the `docker compose up -d` drop out, and the
rest of the procedure stays. On the mirror, `composer require --no-update` with the new exact pins and
`composer update` with only those packages, so nothing else moves. Live, `plugin:update <Name>` runs once
per plugin after `plugin:refresh`.

Rehearsed on 2026-10-18 for FroshTools 3.9.0 to 3.15.1, SwagLanguagePack 5.58.0 to 5.75.0,
TcinnCopyrightCustom 1.0.7 to 1.1.1 and SwagExtensionStore 4.2.2 to 7.0.0. The lock changed in those four
packages alone and the audit found no advisory. The live order from maintenance on to maintenance off took
23 s on the mirror, with 5 s for the language pack and 5 s for the theme compile. SwagExtensionStore 7.0.0
brings one migration, which sets `SwagExtensionStore.config.iframeUrl` to
`https://sky-bridge-store.production.shopware.in`, the page the admin's extension store loads in a frame.

Live on 2026-10-18 the shop was in maintenance from 03:41:53 to 03:43:08. The extra minute came from an
FPM reload typed with an unanchored `pgrep`, the pitfall [plugins.md](plugins.md) describes, so the
reload line is copied from step 5 rather than retyped. Afterwards the plugin list showed the four new
versions, the log had no ERROR and the vendored audit found no advisory.
