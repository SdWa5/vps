# Infrastructure

- Docker: dockware image, ports 8001 (HTTP) / 8443 (HTTPS), reverse-proxied via **Caddy**, not nginx.
  See [../caddy.md](../caddy.md)
- Volume: `./shopware-html-data:/var/www/html`, `./shopware-mysql-data:/var/lib/mysql`
- APP_URL: `https://sdwa5.org`. Keep it in `/opt/docker/shopware-html-data/.env.local`, because
  Dockware's `/var/www/scripts/shopware6/update_domain.sh` rewrites `.env` to HTTP on startup.
  FPM clears inherited environment variables, so the Compose variable alone does not cover web requests.
  On 2026-10-15 HTTP in FPM triggered `ShopIdChangeSuggestedException` in the cart while the CLI check
  passed with HTTPS. The `.env.local` override restored HTTP 200 in EN/DE and the existing shop ID was kept.
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

## Local mirror

[`tools/shopware/dev-instance.sh`](../../tools/shopware/dev-instance.sh) builds a copy of the live shop
on a workstation, so an update or a plugin change is rehearsed there before production gets it. It runs
the image `docker-compose.yml` pins, or the one in `SDWA5_SHOPWARE_DEV_IMAGE`, against the shop files
and the newest hourly database archive.

```bash
tools/shopware/dev-instance.sh fetch      # read the shop files and the archive over ssh
tools/shopware/dev-instance.sh restore    # rebuild the mirror, http://localhost:8090/
tools/shopware/dev-instance.sh up|down|status
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
