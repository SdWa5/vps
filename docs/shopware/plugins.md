# Shopware plugins on sdwa5.org

Which plugins the live shop runs, where each one comes from, and what in this repository records it.
The state below was measured on the running instance on 2026-10-01, right after the migration to
composer, with `plugin:list`, the `plugin` table and `composer.lock`.

## The inventory

Twelve plugins are installed and active. **All twelve are exact requires in
[`composer.json`](../../shopware-html-data/composer.json)**, so `composer install` on a fresh checkout
reproduces the whole set. Eleven are locked as zip downloads in `composer.lock`. The twelfth is the
shop's own theme `SdWa5Theme`, which lives in this repository and is locked as a path, see
[The one path lock](#the-one-path-lock). `tests/shopware-plugins.bats` keeps it that way.

| Plugin | Composer name | Version | Source |
|---|---|---|---|
| `DneStorefrontDarkMode` | `store.shopware.com/dnestorefrontdarkmode` | 4.0.0 | Shopware Store |
| `FroshLazySizes` | `frosh/lazy-sizes` | 3.2.0 | Packagist |
| `FroshPlatformFilterSearch` | `frosh/platform-filter-search` | 3.1.0 | Packagist |
| `FroshPlatformMailArchive` | `frosh/mail-platform-archive` | 3.6.0 | Packagist |
| `FroshPlatformThumbnailProcessor` | `frosh/platform-thumbnail-processor` | 5.4.0 | Packagist |
| `FroshShopmon` | `frosh/shopmon` | 0.2.1 | Packagist |
| `FroshTools` | `frosh/tools` | 3.9.0 | Packagist |
| `SwagExtensionStore` | `swag/swag-extension-store` | 4.2.2 | Packagist |
| `SwagLanguagePack` | `swag/language-pack` | 5.58.0 | Packagist |
| `SwagPlatformSecurity` | `store.shopware.com/swagplatformsecurity` | 4.0.16 | Shopware Store |
| `SdWa5Theme` | `sdwa5/sdwa5-theme` | 1.0.0 | this repository, [theme.md](theme.md) |
| `TcinnCopyrightCustom` | `store.shopware.com/tcinncopyrightcustom` | 1.0.7 | Shopware Store |

Every require is pinned to the exact version, because a floating constraint would turn the next
`composer update` into an unplanned plugin upgrade on a live shop. An upgrade is a deliberate change of
the pin. On 2026-10-01 newer releases existed for `TcinnCopyrightCustom` (1.1.1), `FroshTools` (3.14.1),
`SwagExtensionStore` (7.0.0) and `SwagLanguagePack` (5.72.0).

An update follows the run of `SwagPlatformSecurity` from 4.0.11 to 4.0.16 on 2026-10-01, which took two
minutes of maintenance mode with the worker lock held, as in the migration below:

```bash
composer require --no-interaction store.shopware.com/swagplatformsecurity:4.0.16
php bin/console plugin:update SwagPlatformSecurity
php bin/console cache:clear
kill -USR2 "$(pgrep -f 'php-fpm: master')"     # as root in the container
```

The FPM reload is a precaution, because the path of an updated plugin stays the same.

## Where composer puts a plugin here

Into `vendor/<vendor>/<package>/`. The `plugin` table gives each plugin that path with
`managed_by_composer = 1`, and `custom/plugins/` is empty apart from its own `.gitignore`.

`composer.json` still lists the three path repositories Shopware ships with (`custom/plugins/*`,
`custom/plugins/*/packages/*` and `custom/static-plugins/*`). They come first, so a directory dropped into
`custom/plugins/` wins over Packagist and the Store and is locked as `dist.type: path`. A plugin uploaded
through the admin's plugin manager lands exactly there. **Install plugins with `composer require`, not
through the admin.** A path lock is not reproducible, because `custom/plugins/` is not in the repository,
and the test suite fails on it.

### The one path lock

`SdWa5Theme` is the exception, and it is reproducible because its source is tracked. It sits in
`custom/static-plugins/SdWa5Theme/`, which `.gitignore` lifts out of the ignored `shopware-html-data/`
with three negations and nothing else, so `custom/plugins/` stays untracked. Composer finds it through
the `custom/static-plugins/*` path repository and symlinks it into `vendor/sdwa5/sdwa5-theme`. The test
suite allows a path lock only for a `custom/static-plugins/` directory whose `composer.json` is in the
repository and whose negation is in `.gitignore`.

The lock records a `reference` for a path package, which is a hash of its `composer.json` rather than
of its code. A version bump of the theme therefore changes the lock, so the lock is updated with the
bump:

```bash
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD/shopware-html-data:/app" -w /app composer:2.2 \
    update --no-install --no-scripts --no-plugins --ignore-platform-reqs sdwa5/sdwa5-theme
```

The path repository throws if `custom/plugins/` is missing, so a fresh checkout needs
`mkdir -p shopware-html-data/custom/plugins` before that call. The directory stays ignored.

## The Shopware Store repository

The three Store plugins come from `https://packages.shopware.com`, the fourth repository in
`composer.json`. It needs the composer token of the shop `sdwa5.org` from the Shopware Account, which
lives in Vaultwarden and on the host in `shopware-html-data/auth.json`:

```json
{"bearer": {"packages.shopware.com": "<token>"}}
```

`auth.json` is gitignored through the `shopware-html-data/*` line. A restore from this repository therefore
needs that file put back before `composer install`, and without it the three Store plugins fail to
download. The repository answers HTTP 400 with the body `"Token invalid."` for a wrong token, while
the same URL without any token answers 200 with a public package list. A 400 therefore means the token,
not an outage.

## How the migration ran on 2026-10-01

The shop was in maintenance mode from about 07:22 to 07:27 Berlin.

1. A database dump plus a tar of `custom/plugins/`, `vendor/`, `composer.json` and `composer.lock` went to
   `/root/plugin-migration-2026-10-01/` on the host. The old plugin directories are there as well.
2. The worker's lock `/run/lock/shopware-worker.lock` was held, so no queue run loaded plugins halfway.
3. All eleven directories moved out of `custom/plugins/`, and one `composer require` with the eleven exact
   pins installed them into `vendor/`. Before that, nine plugins were not in composer at all, and
   `FroshPlatformMailArchive` and `FroshPlatformThumbnailProcessor` were locked as `dist.type: path`, so
   `vendor/frosh/*` were symlinks into the untracked `custom/plugins/`.
4. The lock diff added exactly the nine missing packages and changed no other version. `shopware/core`
   stayed `v6.7.11.1`.
5. `plugin:refresh`, `assets:install`, `theme:compile` and `cache:clear` followed.

**One trap showed up and is worth knowing for the next time a plugin path changes.** Right after the
change the admin answered HTTP 500 on some requests and 200 on others, depending on the FPM worker. The FPM error log
`/var/log/php/fpm_errors.log` showed `include(/var/www/html/custom/plugins/FroshPlatformMailArchive/...)`,
which is the old symlink target. `realpath_cache_ttl` is 600 seconds in this image, so the long-lived
PHP-FPM workers kept resolving the old path. A graceful reload of the FPM master (`kill -USR2` on the
`php-fpm: master process`) cleared it. The Shopware log itself recorded nothing, because the error
happens before the kernel boots.

## Reading the current state yourself

```bash
docker exec shopware php bin/console plugin:list
docker exec -u root shopware mysql -uroot -proot -N -B \
    -e "SELECT name, version, managed_by_composer, path FROM shopware.plugin ORDER BY name;"
```
