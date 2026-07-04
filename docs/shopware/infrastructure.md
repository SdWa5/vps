# Infrastructure

- Docker: dockware image, ports 8001 (HTTP) / 8443 (HTTPS), reverse-proxied via nginx
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
