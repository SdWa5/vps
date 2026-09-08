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

## Runtime: nothing runs Shopware's background work

**Measured 2026-09-08, and this is a live defect rather than a design note.** Shopware needs a process
to run its scheduled tasks and to consume its message queue. On this host there is none:

| Where a runner would live | State |
|---|---|
| Host cron (`/etc/cron.d`, root crontab) | no Shopware entry |
| Container crontab | only Debian's own `e2scrub_all` and `php sessionclean` |
| A running `scheduled-task:run` or `messenger:consume` | neither present in the container's process list |
| A worker service in `docker-compose.yml` | none. The only cron container is `dolibarr_cron` |

What that costs, from `bin/console scheduled-task:list` and `messenger:stats`:

* **Every scheduled task last ran on 2026-07-22 or 2026-07-23**, and every "next execution" is
  therefore 47 days in the past.
* `shopware.sitemap_generate` last ran 2026-07-22, which is exactly the `lastmod` the published
  sitemap carries. So the stale sitemap is a symptom of this and not a separate problem.
* `shopware.invalidate_cache` has a 300-second interval and last ran 2026-07-23T14:31, so cache
  invalidation is dead too.
* Every cleanup task is dead, so `log_entry`, `cart`, `payment_token`, `sales_channel_context`,
  `version` and `import_export_file` grow without being pruned.
* **9 messages sit unconsumed in the `async` transport**, with 0 failed.

**The likely mechanism, stated as a hypothesis rather than a measurement.** All the tasks stop at the
same moment, and `shopware.invalidate_cache` shows a last run 4 minutes before its next due time,
which is what the **admin worker** looks like: it runs tasks only while somebody has the
administration open in a browser, so the tasks ran while someone was working in the admin in late July
and have not run since. The effective `enable_admin_worker` value could not be read here, because
`bin/console debug:config` fails with "Impossible to call set() on a frozen ParameterBag" in this
build, so this is not confirmed.

The production fix is a real runner rather than the admin worker, which means a cron or a worker
service running roughly

```
bin/console scheduled-task:run --time-limit=60
bin/console messenger:consume async low_priority --time-limit=60
```

every minute, plus turning the admin worker off so the two do not overlap. Filed as item 1 in
[TODO.md](TODO.md), because it needs a decision about where that process lives and it touches a live
internet-facing shop.
