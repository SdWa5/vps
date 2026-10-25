# Infrastructure

- **Container.** `shopware` runs the shop's own image on Shopware's FrankenPHP base and listens on
  `127.0.0.1:8001` (HTTP). Caddy on the host terminates TLS and proxies to it, see [../caddy.md](../caddy.md).
  How the image is built, shipped and deployed is in [image.md](image.md).
- **Database.** `shopware_db` on `mysql:8.4`, on the internal network `shop_db`, with its data in
  `./shopware-db-data`.
- **Data.** Bind mounts under `./shopware-data/`: `files`, `media`, `thumbnail`, `sitemap`, `theme` and `log`,
  owned by www-data (82).
- **Environment.** `APP_URL=https://sdwa5.org` and the other settings are in the `shopware` service of
  `docker-compose.yml`. `APP_SECRET`, `INSTANCE_ID` and `DATABASE_URL` come from the compose secret
  `shopware_env_local`, mounted as `.env.local` ([image.md#secrets](image.md#secrets)).
- `composer.json`/`.lock`, `symfony.lock`, `.shopware-project.yml` and `config/{packages,routes*,services.yaml,bundles.php}`
  are tracked in `shopware-html-data/`, and `shopware/` holds the Dockerfile and the remaining files the image
  needs. Everything else in `shopware-html-data/` is the dockware docroot of the rollback window and stays
  gitignored.
- **Twelve plugins are installed and active.** Which ones exist, where each comes from and what
  records it lives in [plugins.md](plugins.md). All twelve are exact `composer.json` requires, and the deployment
  helper installs and activates what the image carries. The only plugin source tracked here is the shop's own
  theme in `custom/static-plugins/SdWa5Theme/`, see [theme.md](theme.md).

### Before SEC-31: dockware

Until SEC-31 the shop ran in `dockware/shopware` with its own MySQL 8.0, on ports 8001 and 8443, with the docroot
`./shopware-html-data` and the data in `./shopware-mysql-data`. Records of that time:

- dockware's `/var/www/scripts/shopware6/update_domain.sh` rewrote `.env` to HTTP on every start, and FPM cleared
  inherited environment variables, so `APP_URL` had to live in `.env.local`. On 2026-10-15 HTTP in FPM triggered
  `ShopIdChangeSuggestedException` in the cart while the CLI check passed with HTTPS.
- dockware's `sshd` and `mailcatcher` were stopped on every boot by
  [`hardening/dockware-boot-end.sh`](../../hardening/dockware-boot-end.sh), which Chimo Diazz still mounts.
- The `.env*` files were mode 600, owner `www-data`, and held `APP_SECRET` and the database password.

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

## Local mirror and updates

The local mirror and the update runbook moved to [image.md#mirror](image.md#mirror) and
[image.md#updates](image.md#updates) with SEC-31. The records below are history from the dockware era.

### Updating Shopware on dockware (2026-10-16)

Rehearsed on the mirror from 6.7.11.1 to 6.7.15.1. `composer audit` reported 22 advisories for the old lock
and none for the new one. That needed 6.7.15.1, because 6.7.11.1 pins `dompdf/dompdf` 3.1.4 exactly. The
administration, storefront and elasticsearch packages pin core exactly, so `require
--update-with-all-dependencies` failed, and `require --no-update shopware/core:v6.7.15.1` followed by
`update shopware/core shopware/administration shopware/storefront shopware/elasticsearch --with-all-dependencies`
worked. The dockware images shipped Composer 2.2.9, which has no `audit`, so the vendored Composer ran it.

Live on 2026-10-16 from 15:13:51 to 15:16:18, so ca. 2.5 minutes of maintenance, with
`system:update:prepare`, `composer install --no-dev` in the container, `system:update:finish`,
`theme:compile --active-only`, `cache:clear` and an FPM reload. The install took 24 s and the migrations 18 s.

### Updating plugins on dockware (2026-10-18)

FroshTools 3.9.0 to 3.15.1, SwagLanguagePack 5.58.0 to 5.75.0, TcinnCopyrightCustom 1.0.7 to 1.1.1 and
SwagExtensionStore 4.2.2 to 7.0.0. The lock changed in those four packages alone and the audit found no
advisory. SwagExtensionStore 7.0.0 brings one migration, which sets `SwagExtensionStore.config.iframeUrl` to
`https://sky-bridge-store.production.shopware.in`, the page the admin's extension store loads in a frame. Live
the shop was in maintenance from 03:41:53 to 03:43:08, and the extra minute came from an FPM reload typed with an
unanchored `pgrep`.
