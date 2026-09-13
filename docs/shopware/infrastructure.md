# Infrastructure

- Docker: dockware image, ports 8001 (HTTP) / 8443 (HTTPS), reverse-proxied via **Caddy**, not nginx.
  See [../caddy.md](../caddy.md)
- Volume: `./shopware-html-data:/var/www/html`, `./shopware-mysql-data:/var/lib/mysql`
- APP_URL: `https://sdwa5.org` (set in `/opt/docker/shopware-html-data/.env`)
- DockwareSamplePlugin: uninstalled
- `composer.json`/`.lock`, `symfony.lock` and `config/{packages,routes*,services.yaml,bundles.php}` are tracked
  in the repo (everything else in `shopware-html-data/` — `.env`, `var/`, `vendor/`, `public/`, `files/`,
  `config/jwt/` — stays gitignored)
- Store-installed plugins **FroshLazySizes, FroshPlatformFilterSearch, SwagPlatformSecurity, FroshShopmon** are
  tracked too — they're not in `composer.lock` (Store install, not `composer require`), so without a repo copy
  they'd only be recoverable via the Shopware Store account. `FroshPlatformThumbnailProcessor` and
  `FroshPlatformMailArchive` don't need this — they're real composer requires.

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
than a settled one. Filed in [TODO.md](TODO.md).
