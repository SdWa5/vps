# Shopware plugins on sdwa5.org

Which plugins the live shop runs, where each one comes from, and what in this repository records it.
Everything here was measured on the running instance on 2026-09-16 with `plugin:list`, the `plugin`
table and the Packagist API. Nothing is inferred from the directory listing alone.

## The inventory

Eleven plugins are installed and active. `Recorded` is what would bring the plugin back if
`/opt/docker` were lost.

| Directory under `custom/plugins/` | Composer name | Version | Recorded |
|---|---|---|---|
| `DneStorefrontDarkMode` | `dne/storefront-dark-mode` | 4.0.0 | **nothing** |
| `FroshLazySizes` | `frosh/lazy-sizes` | 3.2.0 | tracked source |
| `FroshPlatformFilterSearch` | `frosh/platform-filter-search` | 3.1.0 | tracked source |
| `FroshPlatformMailArchive` | `frosh/mail-platform-archive` | 3.6.0 | `composer.json` |
| `FroshPlatformThumbnailProcessor` | `frosh/platform-thumbnail-processor` | 5.4.0 | `composer.json` |
| `FroshShopmon` | `frosh/shopmon` | 0.2.1 | tracked source |
| `FroshTools` | `frosh/tools` | 3.9.0 | **nothing** |
| `SwagExtensionStore` | `swag/swag-extension-store` | 4.2.2 | **nothing** |
| `SwagLanguagePack` | `swag/language-pack` | 5.58.0 | **nothing** |
| `SwagPlatformSecurity` | `swag/platform-security` | 4.0.11 | tracked source |
| `TcinnCopyrightCustom` | `tcinn/copyright-custom` | 1.0.7 | **nothing** |

**Five active plugins are recorded nowhere.** `.gitignore` ignores
`shopware-html-data/custom/plugins/*` and then lifts exactly four directories back out of that
exclusion, so everything installed since simply falls out of the repository without anything saying
so. That is a reproducibility gap rather than a disclosure one, and it is the reason this page
exists.

## Where composer puts a Shopware plugin here

Into `custom/plugins/<PluginName>/`, not into `vendor/`. Measured on 2026-09-16:
`vendor/frosh/mail-platform-archive` holds **zero** files, `custom/plugins/FroshPlatformMailArchive`
holds 61, and the `plugin` table gives that plugin `path = custom/plugins/FroshPlatformMailArchive/`
with `managed_by_composer = 1`.

This matters for the migration below, because it means moving a plugin to composer changes where a
directory came from and not where it sits. The `managed_by_composer` column is what distinguishes the
two, and the directory listing cannot.

## What could move to composer today, and what could not

Checked against the Packagist API for the exact installed version:

- **Six are available at exactly the version that runs**, so a `composer require` would be a no-op in
  content terms: `frosh/lazy-sizes`, `frosh/platform-filter-search`, `frosh/shopmon`, `frosh/tools`,
  `swag/swag-extension-store` and `swag/language-pack`. Newer releases exist for the last three, so
  the require has to pin rather than float, or the migration silently becomes an upgrade.
- **Three are not on Packagist in the version that runs.** `swag/platform-security` and
  `tcinn/copyright-custom` answer 404 there entirely. `dne/storefront-dark-mode` exists but stops at
  2.0.0, while 4.0.0 is installed. All three come through the Shopware Store, so they need
  `packages.shopware.com` as an additional composer repository and a Shopware account token in an
  untracked `auth.json`. That is the same missing capability as item 8 in [TODO.md](../../TODO.md),
  seen from the other instance.

## Licences of the four that this repository carries as source

Read from each plugin's own `composer.json` on 2026-09-16. All four declare **MIT**, which is what
makes publishing this repository with them in it permissible:

| Plugin | Declared licence | Tracked files |
|---|---|---|
| `FroshLazySizes` | MIT | 18 |
| `FroshPlatformFilterSearch` | MIT | 22 |
| `FroshShopmon` | MIT | 11 |
| `SwagPlatformSecurity` | MIT | 115 |

The root `README.md` carve-out calls this content "store-installed plugin content under its vendors'
own terms". That stays the right wording, because it also covers whatever is vendored next, and this
table is the measurement behind it for what is vendored today.

## The migration, which is planned and not done

Recorded as item 9 in [TODO.md](../../TODO.md). It was scoped on 2026-09-16 and deliberately not
executed, because it replaces plugin directories on a live shop. When it runs, it runs behind
Shopware's maintenance mode, which was the decision taken the same day.

## Reading the current state yourself

```bash
docker exec shopware php bin/console plugin:list
docker exec -u root shopware mysql -uroot -proot -N -B \
    -e "SELECT name, path, managed_by_composer FROM shopware.plugin ORDER BY name;"
```
